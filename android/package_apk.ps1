param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$AndroidDir = $PSScriptRoot
$Root = Split-Path -Parent $AndroidDir
$Blender = Join-Path $Root "blender-5.2.0"
$BuildDir = Join-Path $Root "build_android"
$LibDir = Join-Path $Blender "lib\android_arm64"
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$Ndk = Join-Path $SdkRoot "ndk\27.2.12479018"
$Jdk = Join-Path $AndroidDir ".tools\jdk-17"
$Gradle = Join-Path $AndroidDir ".tools\gradle-8.9\bin\gradle.bat"

$env:JAVA_HOME = $Jdk
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_HOME = $SdkRoot
$env:PATH = "$(Join-Path $Jdk 'bin');$(Join-Path $SdkRoot 'platform-tools');$env:PATH"

$localProps = Join-Path $AndroidDir "local.properties"
if (-not (Test-Path $localProps)) {
    $sdkEscaped = ($SdkRoot -replace '\\', '\\')
    Set-Content -Path $localProps -Value "sdk.dir=$($SdkRoot -replace '\\', '/')"
}

function Test-Elf16kAlignment([string]$SoPath, [string]$Readelf) {
    $out = & $Readelf -l $SoPath 2>&1 | Out-String
    $loads = [regex]::Matches($out, "LOAD\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)")
    if ($loads.Count -eq 0) { throw "No ELF LOAD segments in $SoPath" }
    foreach ($m in $loads) {
        $align = [Convert]::ToInt64($m.Groups[1].Value, 16)
        if ($align -lt 16384) {
            throw "$SoPath LOAD Align=$($m.Groups[1].Value) is not 16KB (Android 15 requires 0x4000)"
        }
    }
    Write-Host "16KB OK: $(Split-Path $SoPath -Leaf)"
}

Write-Host "== Staging native libraries =="
$jni = Join-Path $AndroidDir "app\src\main\jniLibs\arm64-v8a"
New-Item -ItemType Directory -Force -Path $jni | Out-Null
$soCandidates = @(
    (Join-Path $BuildDir "lib\libblender.so"),
    (Join-Path $BuildDir "bin\libblender.so"),
    (Join-Path $BuildDir "source\creator\libblender.so")
)
$blenderSo = $soCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $blenderSo) {
    $blenderSo = Get-ChildItem $BuildDir -Recurse -Filter "libblender.so" | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $blenderSo) { throw "libblender.so not found under $BuildDir" }
Copy-Item -Force $blenderSo (Join-Path $jni "libblender.so")
Write-Host "Copied $blenderSo"

$shared = @()
$shared += Get-ChildItem (Join-Path $LibDir "sdl") -Recurse -Filter "libSDL3.so" -ErrorAction SilentlyContinue
$shared += Get-ChildItem (Join-Path $LibDir "tbb") -Recurse -Filter "libtbb.so*" -ErrorAction SilentlyContinue
$shared += Get-ChildItem (Join-Path $LibDir "python") -Recurse -Filter "libpython3*.so*" -ErrorAction SilentlyContinue
$shared += Get-ChildItem (Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android") -Recurse -Filter "libc++_shared.so" -ErrorAction SilentlyContinue
foreach ($f in $shared) {
    Copy-Item -Force $f.FullName (Join-Path $jni $f.Name)
    Write-Host "Copied $($f.Name)"
}

$readelf = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe"
$nm = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe"
Write-Host "== Verifying 16KB ELF alignment and SDL_main =="
Get-ChildItem $jni -Filter "*.so" | ForEach-Object { Test-Elf16kAlignment $_.FullName $readelf }
$sdlMain = & $nm -D --defined-only (Join-Path $jni "libblender.so") 2>&1 | Out-String
if ($sdlMain -notmatch '(?m)^\S+\s+T\s+SDL_main\s*$') {
    throw "libblender.so does not export C SDL_main (SDLActivity dlsym will fail). Symbols:`n$sdlMain"
}
Write-Host "SDL_main export OK"

Write-Host "== Packaging runtime assets =="
& (Join-Path $AndroidDir "package_runtime.ps1")

$gradleTask = if ($Release) { "assembleRelease" } else { "assembleDebug" }
Write-Host "== Gradle $gradleTask =="
Push-Location $AndroidDir
try {
    & $Gradle $gradleTask --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle $gradleTask failed" }
} finally {
    Pop-Location
}

$apk = if ($Release) {
    Join-Path $AndroidDir "app\build\outputs\apk\release\app-release.apk"
} else {
    Join-Path $AndroidDir "app\build\outputs\apk\debug\app-debug.apk"
}
if (-not (Test-Path $apk)) { throw "APK not produced: $apk" }
if ($Release) {
    $distDir = Join-Path $AndroidDir "dist"
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    $distApk = Join-Path $distDir "Blender-5.2.0-android-test-arm64.apk"
    Copy-Item -Force $apk $distApk
    $downloads = Join-Path $env:USERPROFILE "Downloads\Blender-5.2.0-android-test-arm64.apk"
    Copy-Item -Force $apk $downloads
    Write-Host "Release APK ready: $distApk"
    Write-Host "Copy: $downloads"
    $apk = $distApk
} else {
    Write-Host "APK ready: $apk"
}

$adb = Join-Path $SdkRoot "platform-tools\adb.exe"
if (Test-Path $adb) {
    Write-Host "== adb devices =="
    & $adb devices
    $devices = & $adb devices | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] }
    if ($devices) {
        Write-Host "Installing onto $($devices -join ', ')"
        if ($Release) {
            & $adb uninstall org.blender.experimental
        }
        & $adb install -r --no-incremental $apk
        if ($LASTEXITCODE -eq 0) {
            & $adb shell am force-stop org.blender.experimental
        }
    } else {
        Write-Host "No Android device reported by adb."
        Write-Host "Enable Developer options + USB debugging, then:"
        Write-Host "  `"$adb`" install -r `"$apk`""
    }
}
