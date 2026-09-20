# Configure, compile Blender for Android arm64, package a debug APK, optionally adb install.
param(
    [switch]$SkipDeps,
    [switch]$SkipInstall,
    [string]$SdkRoot = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }),
    [string]$NdkVersion = "27.2.12479018"
)

$ErrorActionPreference = "Stop"
$AndroidDir = $PSScriptRoot
$Root = Split-Path -Parent $AndroidDir
$Blender = Join-Path $Root "blender-5.2.0"
$BuildDir = Join-Path $Root "build_android"
$LibDir = Join-Path $Blender "lib\android_arm64"
$Ndk = Join-Path $SdkRoot "ndk\$NdkVersion"
$CMake = Join-Path $SdkRoot "cmake\3.31.6\bin\cmake.exe"
$Ninja = Join-Path $SdkRoot "cmake\3.31.6\bin\ninja.exe"
$Toolchain = Join-Path $Ndk "build\cmake\android.toolchain.cmake"
$Tools = Join-Path $AndroidDir ".tools"
$Jdk = Join-Path $Tools "jdk-17"
$Gradle = Join-Path $Tools "gradle-8.9\bin\gradle.bat"

Write-Host "== Installing Android / JDK tools =="
& (Join-Path $AndroidDir "install_tools.ps1") -SdkRoot $SdkRoot
if (-not (Test-Path $CMake)) { throw "CMake missing after install_tools" }

if (-not $SkipDeps) {
    Write-Host "== Cross-compiling Android libraries =="
    & (Join-Path $AndroidDir "build_deps.ps1") -SdkRoot $SdkRoot -NdkVersion $NdkVersion
}

Write-Host "== Building Windows host codegen tools =="
& (Join-Path $AndroidDir "build_host_tools.ps1")
$HostTools = Join-Path $Root "build_host_tools"

Write-Host "== Configuring Blender (Android arm64 / Vulkan / SDL) =="
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$env:JAVA_HOME = $Jdk
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_NDK = $Ndk
$env:PATH = "$(Join-Path $Jdk 'bin');$(Join-Path $SdkRoot 'cmake\3.31.6\bin');$(Join-Path $SdkRoot 'platform-tools');$env:PATH"

$config = Join-Path $Blender "build_files\cmake\config\blender_android.cmake"
$HostPython = Join-Path $Tools "python-host\python.exe"
$cmakeArgs = @(
    "-S", $Blender
    "-B", $BuildDir
    "-G", "Ninja"
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain"
    "-DANDROID_ABI=arm64-v8a"
    "-DANDROID_PLATFORM=android-29"
    "-DANDROID_STL=c++_shared"
    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_MAKE_PROGRAM=$Ninja"
    "-C", $config
    "-DLIBDIR=$LibDir"
    "-DPYTHON_EXECUTABLE=$HostPython"
    "-DHOST_TOOLS_DIR=$HostTools"
    "-UHAVE_EXECINFO_H"
)
& $CMake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "Blender CMake configure failed" }

Write-Host "== Building libblender.so =="
& $CMake --build $BuildDir --target blender --parallel
if ($LASTEXITCODE -ne 0) { throw "Blender native build failed" }

Write-Host "== Staging native libraries into the APK =="
$jni = Join-Path $AndroidDir "app\src\main\jniLibs\arm64-v8a"
New-Item -ItemType Directory -Force -Path $jni | Out-Null
$soCandidates = @(
    (Join-Path $BuildDir "bin\libblender.so"),
    (Join-Path $BuildDir "lib\libblender.so"),
    (Join-Path $BuildDir "source\creator\libblender.so")
)
$blenderSo = $soCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $blenderSo) {
    $blenderSo = Get-ChildItem $BuildDir -Recurse -Filter "libblender.so" | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $blenderSo) { throw "libblender.so not found under $BuildDir" }
Copy-Item -Force $blenderSo (Join-Path $jni "libblender.so")

# Shared deps that must be packaged next to libblender.so
$shared = @()
$shared += Get-ChildItem (Join-Path $LibDir "sdl") -Recurse -Filter "libSDL3.so" -ErrorAction SilentlyContinue
$shared += Get-ChildItem (Join-Path $LibDir "tbb") -Recurse -Filter "libtbb.so*" -ErrorAction SilentlyContinue
$shared += Get-ChildItem (Join-Path $LibDir "python") -Recurse -Filter "libpython3*.so*" -ErrorAction SilentlyContinue
$shared += Get-ChildItem (Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android") -Recurse -Filter "libc++_shared.so" -ErrorAction SilentlyContinue
foreach ($f in $shared) {
    Copy-Item -Force $f.FullName (Join-Path $jni $f.Name)
}

Write-Host "== Packaging scripts / datafiles / Python =="
& (Join-Path $AndroidDir "package_runtime.ps1")

Write-Host "== Gradle assembleDebug =="
Push-Location $AndroidDir
try {
    & $Gradle assembleDebug --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle assembleDebug failed" }
} finally {
    Pop-Location
}

$apk = Join-Path $AndroidDir "app\build\outputs\apk\debug\app-debug.apk"
if (-not (Test-Path $apk)) { throw "APK not produced: $apk" }
Write-Host "APK ready: $apk"

if (-not $SkipInstall) {
    $adb = Join-Path $SdkRoot "platform-tools\adb.exe"
    if (Test-Path $adb) {
        Write-Host "== adb devices =="
        & $adb devices
        $devices = & $adb devices | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] }
        if ($devices) {
            Write-Host "Installing onto $($devices -join ', ')"
            & $adb install -r $apk
        } else {
            Write-Host "No Samsung/Android device reported by adb."
            Write-Host "Enable Developer options + USB debugging, then rerun:"
            Write-Host "  `"$adb`" install -r `"$apk`""
        }
    }
}
