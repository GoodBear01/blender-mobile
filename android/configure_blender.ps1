$ErrorActionPreference = "Stop"
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$NdkVersion = "27.2.12479018"
$Root = Split-Path -Parent $PSScriptRoot
$Blender = Join-Path $Root "blender-5.2.0"
$BuildDir = Join-Path $Root "build_android"
$LibDir = Join-Path $Blender "lib\android_arm64"
$Ndk = Join-Path $SdkRoot "ndk\$NdkVersion"
$CMake = Join-Path $SdkRoot "cmake\3.31.6\bin\cmake.exe"
$Ninja = Join-Path $SdkRoot "cmake\3.31.6\bin\ninja.exe"
$Toolchain = Join-Path $Ndk "build\cmake\android.toolchain.cmake"
$HostPython = Join-Path $PSScriptRoot ".tools\python-host\python.exe"
$HostTools = Join-Path $Root "build_host_tools"
$config = Join-Path $Blender "build_files\cmake\config\blender_android.cmake"

if (-not (Test-Path $CMake)) { throw "CMake missing: $CMake" }
if (-not (Test-Path $Toolchain)) { throw "Toolchain missing: $Toolchain" }
if (-not (Test-Path $HostPython)) { throw "Host Python missing: $HostPython" }

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Write-Host "Configuring with toolchain $Toolchain"

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
    "-DWITH_CYCLES=ON"
    "-DWITH_CYCLES_OSL=OFF"
    "-DWITH_CYCLES_EMBREE=OFF"
    "-DWITH_CYCLES_PATH_GUIDING=OFF"
    "-DWITH_CYCLES_DEVICE_CUDA=OFF"
    "-DWITH_CYCLES_DEVICE_HIP=OFF"
    "-DWITH_CYCLES_DEVICE_OPTIX=OFF"
    "-DWITH_CYCLES_DEVICE_ONEAPI=OFF"
)
& $CMake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "Blender CMake configure failed with $LASTEXITCODE" }
Write-Host "Configure succeeded"
