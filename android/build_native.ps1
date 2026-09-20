$ErrorActionPreference = "Stop"
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$CMake = Join-Path $SdkRoot "cmake\3.31.6\bin\cmake.exe"
$BuildDir = Join-Path (Split-Path -Parent $PSScriptRoot) "build_android"
Write-Host "Building libblender.so in $BuildDir"
& $CMake --build $BuildDir --target blender --parallel
if ($LASTEXITCODE -ne 0) { throw "Native Blender build failed with $LASTEXITCODE" }
Write-Host "Native build succeeded"
