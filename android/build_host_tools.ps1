$ErrorActionPreference = "Stop"
$AndroidDir = $PSScriptRoot
$Root = Split-Path -Parent $AndroidDir
$Mingw = Join-Path $AndroidDir ".tools\w64devkit\w64devkit\bin"
if (-not (Test-Path (Join-Path $Mingw "g++.exe"))) {
    throw "w64devkit g++ not found at $Mingw"
}
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$CMake = Join-Path $SdkRoot "cmake\3.31.6\bin\cmake.exe"
$Ninja = Join-Path $SdkRoot "cmake\3.31.6\bin\ninja.exe"
$BuildDir = Join-Path $Root "build_host_tools"
$env:PATH = "$Mingw;$env:PATH"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Write-Host "Configuring Windows host codegen tools"
$cmakeArgs = @(
    "-S", (Join-Path $AndroidDir "host_tools")
    "-B", $BuildDir
    "-G", "Ninja"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=$(Join-Path $Mingw 'gcc.exe')"
    "-DCMAKE_CXX_COMPILER=$(Join-Path $Mingw 'g++.exe')"
    "-DCMAKE_MAKE_PROGRAM=$Ninja"
)
& $CMake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "Host tools CMake configure failed" }
Write-Host "Building host tools"
& $CMake --build $BuildDir --parallel
if ($LASTEXITCODE -ne 0) { throw "Host tools build failed" }
Write-Host "Host tools ready in $BuildDir"
