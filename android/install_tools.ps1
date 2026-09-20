# Downloads JDK, Android NDK/CMake, Gradle, and Ninja if they are missing.
param(
    [string]$SdkRoot = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }),
    [string]$ToolsRoot = $(Join-Path $PSScriptRoot ".tools")
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null

function Get-FileIfMissing([string]$Url, [string]$Dest) {
    if (Test-Path $Dest) { return $Dest }
    Write-Host "Downloading $Url"
    $tmp = "$Dest.partial"
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
    Move-Item -Force $tmp $Dest
    return $Dest
}

# --- JDK 17 ---
$jdkHome = Join-Path $ToolsRoot "jdk-17"
if (-not (Test-Path (Join-Path $jdkHome "bin\java.exe"))) {
    $jdkZip = Join-Path $ToolsRoot "jdk17.zip"
    Get-FileIfMissing "https://aka.ms/download-jdk/microsoft-jdk-17.0.13-windows-x64.zip" $jdkZip
    $extract = Join-Path $ToolsRoot "jdk-extract"
    if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
    Expand-Archive -Path $jdkZip -DestinationPath $extract
    $inner = Get-ChildItem $extract | Select-Object -First 1
    if (Test-Path $jdkHome) { Remove-Item -Recurse -Force $jdkHome }
    Move-Item $inner.FullName $jdkHome
    Remove-Item -Recurse -Force $extract -ErrorAction SilentlyContinue
}
$env:JAVA_HOME = $jdkHome
$env:PATH = "$(Join-Path $jdkHome 'bin');$env:PATH"
Write-Host "JAVA_HOME=$env:JAVA_HOME"

# --- Android cmdline-tools ---
$cmdTools = Join-Path $SdkRoot "cmdline-tools\latest"
if (-not (Test-Path (Join-Path $cmdTools "bin\sdkmanager.bat"))) {
    $zip = Join-Path $ToolsRoot "cmdline-tools.zip"
    Get-FileIfMissing "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" $zip
    $extract = Join-Path $ToolsRoot "cmdline-extract"
    if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
    Expand-Archive -Path $zip -DestinationPath $extract
    New-Item -ItemType Directory -Force -Path (Join-Path $SdkRoot "cmdline-tools") | Out-Null
    $src = Join-Path $extract "cmdline-tools"
    if (Test-Path $cmdTools) { Remove-Item -Recurse -Force $cmdTools }
    Move-Item $src $cmdTools
    Remove-Item -Recurse -Force $extract -ErrorAction SilentlyContinue
}

$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_HOME = $SdkRoot

# --- Accept licenses and install NDK / CMake / platform ---
$sdkmanager = Join-Path $cmdTools "bin\sdkmanager.bat"
$packages = @(
    "platform-tools",
    "platforms;android-35",
    "build-tools;35.0.0",
    "cmake;3.31.6",
    "ndk;27.2.12479018"
)
Write-Host "Installing Android SDK packages (this can take a while)..."
$yes = "y`ny`ny`ny`ny`n"
$yes | & $sdkmanager --sdk_root=$SdkRoot --licenses | Out-Null
& $sdkmanager --sdk_root=$SdkRoot $packages

# --- Gradle ---
$gradleHome = Join-Path $ToolsRoot "gradle-8.9"
if (-not (Test-Path (Join-Path $gradleHome "bin\gradle.bat"))) {
    $gradleZip = Join-Path $ToolsRoot "gradle-8.9-bin.zip"
    Get-FileIfMissing "https://services.gradle.org/distributions/gradle-8.9-bin.zip" $gradleZip
    $extract = Join-Path $ToolsRoot "gradle-extract"
    if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
    Expand-Archive -Path $gradleZip -DestinationPath $extract
    if (Test-Path $gradleHome) { Remove-Item -Recurse -Force $gradleHome }
    Move-Item (Join-Path $extract "gradle-8.9") $gradleHome
    Remove-Item -Recurse -Force $extract -ErrorAction SilentlyContinue
}

$ndk = Join-Path $SdkRoot "ndk\27.2.12479018"
$cmake = Join-Path $SdkRoot "cmake\3.31.6"
$localProps = Join-Path $PSScriptRoot "local.properties"
@"
sdk.dir=$($SdkRoot -replace '\\','\\')
ndk.dir=$($ndk -replace '\\','\\')
blender.native.outdir=$($PSScriptRoot -replace '\\','\\')\\..\\build_android\\lib
"@ | Set-Content -Path $localProps -Encoding ASCII

Write-Host "Tools ready."
Write-Host "  SDK   = $SdkRoot"
Write-Host "  NDK   = $ndk"
Write-Host "  CMake = $cmake"
Write-Host "  JDK   = $jdkHome"
Write-Host "  Gradle= $gradleHome"
