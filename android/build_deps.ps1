# Cross-compile the lite Android arm64 dependency set into blender-5.2.0/lib/android_arm64
param(
    [string]$SdkRoot = $(if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }),
    [string]$NdkVersion = "27.2.12479018",
    [string]$Api = "26",
    [string]$Abi = "arm64-v8a"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Blender = Join-Path $Root "blender-5.2.0"
$Packages = Join-Path $Root "packages"
$LibDir = Join-Path $Blender "lib\android_arm64"
$Work = Join-Path $PSScriptRoot ".deps"
$Src = Join-Path $Work "src"
$Build = Join-Path $Work "build"
$Ndk = Join-Path $SdkRoot "ndk\$NdkVersion"
$CMake = Join-Path $SdkRoot "cmake\3.31.6\bin\cmake.exe"
$Ninja = Join-Path $SdkRoot "cmake\3.31.6\bin\ninja.exe"
$Toolchain = Join-Path $Ndk "build\cmake\android.toolchain.cmake"
$HostTag = "windows-x86_64"
$Clang = Join-Path $Ndk "toolchains\llvm\prebuilt\$HostTag\bin\aarch64-linux-android$Api-clang.cmd"
$Clangxx = Join-Path $Ndk "toolchains\llvm\prebuilt\$HostTag\bin\aarch64-linux-android$Api-clang++.cmd"
$Sysroot = Join-Path $Ndk "toolchains\llvm\prebuilt\$HostTag\sysroot"

if (-not (Test-Path $CMake)) { throw "CMake not found at $CMake. Run android/install_tools.ps1 first." }
if (-not (Test-Path $Toolchain)) { throw "NDK toolchain missing: $Toolchain" }

New-Item -ItemType Directory -Force -Path $LibDir, $Src, $Build | Out-Null

function Expand-Package([string]$ArchiveName, [string]$DestName) {
    $dest = Join-Path $Src $DestName
    if ((Test-Path (Join-Path $dest "CMakeLists.txt")) -or (Test-Path (Join-Path $dest "configure"))) {
        return $dest
    }
    $archive = Get-ChildItem $Packages -Filter $ArchiveName | Select-Object -First 1
    if (-not $archive) { throw "Missing package $ArchiveName in $Packages" }
    Write-Host "Extracting $($archive.Name) -> $dest"
    $tmp = Join-Path $Work "extract-$DestName"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    if ($archive.Name -match "\.(tar\.(gz|xz|bz2)|tgz)$") {
        tar -xf $archive.FullName -C $tmp
    } else {
        Expand-Archive -Path $archive.FullName -DestinationPath $tmp
    }
    $inner = Get-ChildItem $tmp | Select-Object -First 1
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Move-Item $inner.FullName $dest
    Remove-Item -Recurse -Force $tmp
    return $dest
}

function Invoke-CMakeDep {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Prefix,
        [string[]]$ExtraArgs = @()
    )
    $stamp = Join-Path $Prefix ".built"
    if (Test-Path $stamp) {
        Write-Host "[skip] $Name already built"
        return
    }
    $bdir = Join-Path $Build $Name
    New-Item -ItemType Directory -Force -Path $bdir, $Prefix | Out-Null
    Write-Host "===== Configuring $Name ====="
    $args = @(
        "-S", $Source,
        "-B", $bdir,
        "-G", "Ninja",
        "-DCMAKE_TOOLCHAIN_FILE=$Toolchain",
        "-DANDROID_ABI=$Abi",
        "-DANDROID_PLATFORM=android-$Api",
        "-DANDROID_STL=c++_shared",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=$Prefix",
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
        "-DCMAKE_MAKE_PROGRAM=$Ninja",
        "-DCMAKE_PREFIX_PATH=$LibDir",
        "-DCMAKE_FIND_ROOT_PATH=$LibDir;$Sysroot",
        "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH",
        "-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH",
        "-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH",
        "-DCMAKE_POLICY_DEFAULT_CMP0074=NEW",
        "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
        "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384",
        "-DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,max-page-size=16384",
        "-DCMAKE_MODULE_LINKER_FLAGS=-Wl,-z,max-page-size=16384"
    ) + $ExtraArgs
    & $CMake @args
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $Name" }
    Write-Host "===== Building $Name ====="
    & $CMake --build $bdir --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $Name" }
    & $CMake --install $bdir
    if ($LASTEXITCODE -ne 0) { throw "Install failed for $Name" }
    Set-Content -Path $stamp -Value (Get-Date -Format o)
}

# --- zlib ---
$zlibSrc = Expand-Package "zlib-*.tar.gz" "zlib"
Invoke-CMakeDep "zlib" $zlibSrc (Join-Path $LibDir "zlib")

# --- zstd ---
$zstdSrc = Expand-Package "zstd-*.tar.gz" "zstd"
Invoke-CMakeDep "zstd" (Join-Path $zstdSrc "build\cmake") (Join-Path $LibDir "zstd") @(
    "-DZSTD_BUILD_PROGRAMS=OFF", "-DZSTD_BUILD_TESTS=OFF", "-DZSTD_BUILD_SHARED=OFF", "-DZSTD_BUILD_STATIC=ON"
)

# --- brotli ---
$brotliSrc = Expand-Package "brotli-*.tar.gz" "brotli"
Invoke-CMakeDep "brotli" $brotliSrc (Join-Path $LibDir "brotli") @(
    "-DBROTLI_BUNDLED_MODE=OFF", "-DBUILD_SHARED_LIBS=OFF"
)

# --- fmt ---
$fmtSrc = Expand-Package "fmt-*.tar.gz" "fmt"
Invoke-CMakeDep "fmt" $fmtSrc (Join-Path $LibDir "fmt") @(
    "-DFMT_TEST=OFF", "-DFMT_DOC=OFF", "-DBUILD_SHARED_LIBS=OFF"
)

# --- Eigen (header-only) ---
$eigenSrc = Expand-Package "eigen-*.tar.gz" "eigen"
$eigenPrefix = Join-Path $LibDir "eigen"
if (-not (Test-Path (Join-Path $eigenPrefix ".built"))) {
    Invoke-CMakeDep "eigen" $eigenSrc $eigenPrefix @(
        "-DBUILD_TESTING=OFF", "-DEIGEN_BUILD_DOC=OFF", "-DEIGEN_BUILD_PKGCONFIG=OFF"
    )
}

# --- libpng ---
$pngSrc = Expand-Package "libpng-*.tar.xz" "libpng"
Invoke-CMakeDep "png" $pngSrc (Join-Path $LibDir "png") @(
    "-DPNG_SHARED=OFF", "-DPNG_TESTS=OFF", "-DZLIB_ROOT=$(Join-Path $LibDir 'zlib')"
)

# --- libjpeg-turbo ---
$jpegSrc = Expand-Package "libjpeg-turbo-*.tar.gz" "libjpeg-turbo"
Invoke-CMakeDep "jpeg" $jpegSrc (Join-Path $LibDir "jpeg") @(
    "-DENABLE_SHARED=OFF", "-DENABLE_STATIC=ON", "-DWITH_TURBOJPEG=ON"
)

# --- tiff ---
$tiffSrc = Expand-Package "tiff-*.tar.gz" "tiff"
Invoke-CMakeDep "tiff" $tiffSrc (Join-Path $LibDir "tiff") @(
    "-Dtiff-tools=OFF", "-Dtiff-tests=OFF", "-Dtiff-docs=OFF", "-DBUILD_SHARED_LIBS=OFF",
    "-DZLIB_ROOT=$(Join-Path $LibDir 'zlib')", "-DJPEG_ROOT=$(Join-Path $LibDir 'jpeg')"
)

# --- freetype ---
$ftSrc = Expand-Package "freetype-*.tar.gz" "freetype"
$pngInc = Join-Path $LibDir "png\include"
$pngLib = Get-ChildItem (Join-Path $LibDir "png") -Recurse -Include "libpng.a","libpng16.a" | Select-Object -First 1
$zInc = Join-Path $LibDir "zlib\include"
$zLib = Get-ChildItem (Join-Path $LibDir "zlib") -Recurse -Include "libz.a","libzlib.a" | Select-Object -First 1
$brInc = Join-Path $LibDir "brotli\include"
$brDec = Get-ChildItem (Join-Path $LibDir "brotli") -Recurse -Include "libbrotlidec-static.a","libbrotlidec.a" | Select-Object -First 1
Invoke-CMakeDep "freetype" $ftSrc (Join-Path $LibDir "freetype") @(
    "-DFT_DISABLE_HARFBUZZ=ON", "-DFT_DISABLE_BZIP2=ON", "-DFT_REQUIRE_ZLIB=ON",
    "-DFT_REQUIRE_BROTLI=ON", "-DFT_DISABLE_PNG=ON",
    "-DZLIB_INCLUDE_DIR=$zInc",
    "-DZLIB_LIBRARY=$($zLib.FullName)",
    "-DBROTLIDEC_INCLUDE_DIRS=$brInc",
    "-DBROTLIDEC_LIBRARIES=$($brDec.FullName)"
)

# --- Imath / OpenEXR ---
$imathSrc = Expand-Package "imath-*.tar.gz" "imath"
Invoke-CMakeDep "imath" $imathSrc (Join-Path $LibDir "imath") @(
    "-DBUILD_SHARED_LIBS=OFF", "-DBUILD_TESTING=OFF"
)
$exrSrc = Expand-Package "openexr-*.tar.gz" "openexr"
Invoke-CMakeDep "openexr" $exrSrc (Join-Path $LibDir "openexr") @(
    "-DBUILD_SHARED_LIBS=OFF", "-DBUILD_TESTING=OFF", "-DOPENEXR_BUILD_TOOLS=OFF",
    "-DOPENEXR_INSTALL_EXAMPLES=OFF", "-DImath_ROOT=$(Join-Path $LibDir 'imath')",
    "-DZLIB_ROOT=$(Join-Path $LibDir 'zlib')"
)
$openjphLib = Get-ChildItem (Join-Path $Work "build\openexr") -Recurse -Filter "libopenjph.a" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($openjphLib) {
    $ojPrefix = Join-Path $LibDir "openjph\lib"
    New-Item -ItemType Directory -Force -Path $ojPrefix | Out-Null
    Copy-Item -Force $openjphLib.FullName (Join-Path $ojPrefix "libopenjph.a")
    Copy-Item -Force $openjphLib.FullName (Join-Path $LibDir "openexr\lib\libopenjph.a")
}

# --- expat / yaml-cpp / pystring / minizip-ng ---
$expatSrc = Expand-Package "libexpat-*.tar.gz" "expat"
$expatCmake = $expatSrc
if (Test-Path (Join-Path $expatSrc "expat\CMakeLists.txt")) { $expatCmake = Join-Path $expatSrc "expat" }
Invoke-CMakeDep "expat" $expatCmake (Join-Path $LibDir "expat") @(
    "-DEXPAT_SHARED_LIBS=OFF", "-DEXPAT_BUILD_TESTS=OFF", "-DEXPAT_BUILD_TOOLS=OFF", "-DEXPAT_BUILD_EXAMPLES=OFF"
)
$yamlSrc = Expand-Package "yaml-cpp-*.tar.gz" "yaml-cpp"
Invoke-CMakeDep "yaml-cpp" $yamlSrc (Join-Path $LibDir "yaml-cpp") @(
    "-DYAML_BUILD_SHARED_LIBS=OFF", "-DYAML_CPP_BUILD_TESTS=OFF", "-DYAML_CPP_BUILD_TOOLS=OFF"
)
$pystringSrc = Expand-Package "pystring-*.tar.gz" "pystring"
if (-not (Test-Path (Join-Path $pystringSrc "CMakeLists.txt"))) {
    @"
cmake_minimum_required(VERSION 3.16)
project(pystring CXX)
add_library(pystring STATIC pystring.cpp)
target_include_directories(pystring PUBLIC `$<BUILD_INTERFACE:`${CMAKE_CURRENT_SOURCE_DIR}> `$<INSTALL_INTERFACE:include>)
install(TARGETS pystring EXPORT pystringTargets ARCHIVE DESTINATION lib)
install(FILES pystring.h DESTINATION include)
"@ | Set-Content (Join-Path $pystringSrc "CMakeLists.txt")
}
Invoke-CMakeDep "pystring" $pystringSrc (Join-Path $LibDir "pystring")
$minizipSrc = Expand-Package "minizip-ng-*.tar.gz" "minizip-ng"
Invoke-CMakeDep "minizip" $minizipSrc (Join-Path $LibDir "minizip-ng") @(
    "-DMZ_COMPAT=OFF", "-DMZ_BZIP2=OFF", "-DMZ_LZMA=OFF", "-DMZ_ZSTD=ON",
    "-DMZ_OPENSSL=OFF", "-DMZ_LIBCOMP=OFF", "-DBUILD_SHARED_LIBS=OFF",
    "-DZLIB_ROOT=$(Join-Path $LibDir 'zlib')", "-Dzstd_ROOT=$(Join-Path $LibDir 'zstd')"
)

# --- OpenColorIO ---
$ocioSrc = Expand-Package "OpenColorIO-*.tar.gz" "opencolorio"
Invoke-CMakeDep "opencolorio" $ocioSrc (Join-Path $LibDir "opencolorio") @(
    "-DOCIO_BUILD_APPS=OFF", "-DOCIO_BUILD_TESTS=OFF", "-DOCIO_BUILD_GPU_TESTS=OFF",
    "-DOCIO_BUILD_PYTHON=OFF", "-DOCIO_BUILD_DOCS=OFF", "-DBUILD_SHARED_LIBS=OFF",
    "-DImath_ROOT=$(Join-Path $LibDir 'imath')",
    "-Dexpat_ROOT=$(Join-Path $LibDir 'expat')",
    "-Dyaml-cpp_DIR=$(Join-Path $LibDir 'yaml-cpp\lib\cmake\yaml-cpp')",
    "-Dminizip-ng_ROOT=$(Join-Path $LibDir 'minizip-ng')"
)

# --- TBB ---
$tbbSrc = Expand-Package "oneTBB-*.tar.gz" "tbb"
Invoke-CMakeDep "tbb" $tbbSrc (Join-Path $LibDir "tbb") @(
    "-DTBB_TEST=OFF", "-DTBB_STRICT=OFF", "-DBUILD_SHARED_LIBS=ON",
    "-DTBBMALLOC_BUILD=OFF", "-DTBBMALLOC_PROXY_BUILD=OFF",
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--undefined-version -Wl,-z,max-page-size=16384"
)

# --- SDL3 ---
$sdlSrc = Expand-Package "SDL3-*.tar.gz" "sdl3"
Invoke-CMakeDep "sdl" $sdlSrc (Join-Path $LibDir "sdl") @(
    "-DSDL_SHARED=ON", "-DSDL_STATIC=OFF", "-DSDL_TEST_LIBRARY=OFF",
    "-DSDL_CAMERA=OFF", "-DSDL_RENDER=ON"
)

# --- Vulkan headers + NDK loader stub ---
$vkSrc = Expand-Package "Vulkan-Headers-*.tar.gz" "vulkan-headers"
$vkPrefix = Join-Path $LibDir "vulkan"
if (-not (Test-Path (Join-Path $vkPrefix ".built"))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $vkPrefix "include"), (Join-Path $vkPrefix "lib") | Out-Null
    Copy-Item -Recurse -Force (Join-Path $vkSrc "include\*") (Join-Path $vkPrefix "include")
    $ndkVulkan = Get-ChildItem (Join-Path $Ndk "toolchains\llvm\prebuilt\$HostTag\sysroot\usr\lib\aarch64-linux-android") -Recurse -Filter "libvulkan.so" | Select-Object -First 1
    if ($ndkVulkan) {
        Copy-Item $ndkVulkan.FullName (Join-Path $vkPrefix "lib\libvulkan.so")
    }
    Set-Content (Join-Path $vkPrefix ".built") (Get-Date -Format o)
}

# --- Host Python for shaderc / later Blender codegen ---
$HostPython = Join-Path $PSScriptRoot ".tools\python-host\python.exe"
if (-not (Test-Path $HostPython)) {
    Write-Host "Downloading host Python 3.13..."
    $pyZip = Join-Path $Work "python-host.zip"
    Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/python/3.13.7" -OutFile $pyZip -UseBasicParsing
    $pyNupkg = Join-Path $Work "python-nupkg"
    if (Test-Path $pyNupkg) { Remove-Item -Recurse -Force $pyNupkg }
    Expand-Archive -Path $pyZip -DestinationPath $pyNupkg
    $toolsDir = Get-ChildItem $pyNupkg -Recurse -Filter "python.exe" | Select-Object -First 1
    if (-not $toolsDir) { throw "python.exe missing from NuGet package" }
    $pyExtract = Join-Path $PSScriptRoot ".tools\python-host"
    if (Test-Path $pyExtract) { Remove-Item -Recurse -Force $pyExtract }
    Copy-Item -Recurse -Force $toolsDir.Directory.FullName $pyExtract
}
$env:PATH = "$(Split-Path $HostPython);$env:PATH"

# --- shaderc (download missing SPIRV-Tools) ---
$shadercSrc = Expand-Package "shaderc-*.tar.gz" "shaderc"
$third = Join-Path $shadercSrc "third_party"
New-Item -ItemType Directory -Force -Path $third | Out-Null
function Ensure-GitCheckout([string]$Url, [string]$Dest) {
    if (Test-Path (Join-Path $Dest "CMakeLists.txt")) { return }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone --depth 1 $Url $Dest
    } else {
        $zip = Join-Path $Work "$($Dest | Split-Path -Leaf).zip"
        $archiveUrl = $Url.TrimEnd(".git") + "/archive/refs/heads/main.zip"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zip -UseBasicParsing
        $tmp = "$Dest-tmp"
        Expand-Archive $zip $tmp
        $inner = Get-ChildItem $tmp | Select-Object -First 1
        if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
        Move-Item $inner.FullName $Dest
        Remove-Item -Recurse -Force $tmp
    }
}
function Ensure-GitRev([string]$Url, [string]$Rev, [string]$Dest) {
    $marker = Join-Path $Dest ".rev"
    if ((Test-Path (Join-Path $Dest "CMakeLists.txt")) -and (Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $Rev)) {
        return
    }
    if (Test-Path $Dest) { cmd /c rmdir /S /Q "$Dest" | Out-Null }
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        Push-Location $Dest
        git init | Out-Null
        git remote add origin $Url
        git fetch --depth 1 origin $Rev
        git checkout FETCH_HEAD
        Pop-Location
    } else {
        $zip = Join-Path $Work ("{0}-{1}.zip" -f (Split-Path $Dest -Leaf), $Rev.Substring(0,8))
        $repo = $Url
        if ($repo.EndsWith(".git")) { $repo = $repo.Substring(0, $repo.Length - 4) }
        $archiveUrl = "$repo/archive/$Rev.zip"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zip -UseBasicParsing
        $tmp = "$Dest-tmp"
        if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
        Expand-Archive $zip $tmp
        $inner = Get-ChildItem $tmp | Select-Object -First 1
        Move-Item $inner.FullName $Dest
        Remove-Item -Recurse -Force $tmp
    }
    Set-Content $marker $Rev
}

Ensure-GitRev "https://github.com/KhronosGroup/glslang.git" "d213562e35573012b6348b2d584457c3704ac09b" (Join-Path $third "glslang")
Ensure-GitRev "https://github.com/KhronosGroup/SPIRV-Headers.git" "01e0577914a75a2569c846778c2f93aa8e6feddd" (Join-Path $third "spirv-headers")
Ensure-GitRev "https://github.com/KhronosGroup/SPIRV-Tools.git" "19042c8921f35f7bec56b9e5c96c5f5691588ca8" (Join-Path $third "spirv-tools")
Invoke-CMakeDep "shaderc" $shadercSrc (Join-Path $LibDir "shaderc") @(
    "-DSHADERC_SKIP_TESTS=ON", "-DSHADERC_SKIP_EXAMPLES=ON", "-DSHADERC_SKIP_COPYRIGHT_CHECK=ON",
    "-DSHADERC_SKIP_INSTALL=OFF", "-DSPIRV_SKIP_EXECUTABLES=ON", "-DSPIRV_SKIP_TESTS=ON",
    "-DENABLE_GLSLANG_BINARIES=OFF", "-DPYTHON_EXECUTABLE=$HostPython"
)

# --- robin-map (header-only, needed by OpenImageIO) ---
$robinPrefix = Join-Path $LibDir "robin-map"
if (-not (Test-Path (Join-Path $robinPrefix ".built"))) {
    $robinZip = Join-Path $Work "robin-map.zip"
    Invoke-WebRequest -Uri "https://github.com/Tessil/robin-map/archive/refs/tags/v1.4.0.zip" -OutFile $robinZip -UseBasicParsing
    $robinTmp = Join-Path $Work "robin-map-src"
    if (Test-Path $robinTmp) { Remove-Item -Recurse -Force $robinTmp }
    Expand-Archive $robinZip $robinTmp
    $robinSrc = Get-ChildItem $robinTmp | Select-Object -First 1
    Invoke-CMakeDep "robin-map" $robinSrc.FullName $robinPrefix @()
}

# --- OpenImageIO (minimal) ---
$oiioSrc = Expand-Package "OpenImageIO-*.tar.gz" "openimageio"
Invoke-CMakeDep "openimageio" $oiioSrc (Join-Path $LibDir "openimageio") @(
    "-DRobinmap_ROOT=$robinPrefix",
    "-DRobinMap_ROOT=$robinPrefix",
    "-DBUILD_MISSING_DEPS=OFF",
    "-DOIIO_BUILD_TOOLS=OFF", "-DOIIO_BUILD_TESTS=OFF", "-DBUILD_TESTING=OFF",
    "-DUSE_PYTHON=OFF", "-DUSE_QT=OFF", "-DUSE_OPENGL=OFF", "-DUSE_OPENCV=OFF",
    "-DUSE_FREETYPE=OFF", "-DUSE_GIF=OFF", "-DUSE_OPENJPEG=OFF", "-DUSE_WEBP=OFF",
    "-DUSE_FFMPEG=OFF", "-DUSE_PTEX=OFF", "-DUSE_LIBHEIF=OFF", "-DUSE_LIBRAW=OFF",
    "-DUSE_DCMTK=OFF", "-DUSE_JXL=OFF", "-DBUILD_SHARED_LIBS=OFF",
    "-DOpenEXR_ROOT=$(Join-Path $LibDir 'openexr')",
    "-DImath_ROOT=$(Join-Path $LibDir 'imath')",
    "-DZLIB_ROOT=$(Join-Path $LibDir 'zlib')",
    "-Dfmt_ROOT=$(Join-Path $LibDir 'fmt')",
    "-DJPEG_ROOT=$(Join-Path $LibDir 'jpeg')",
    "-DPNG_ROOT=$(Join-Path $LibDir 'png')",
    "-DTIFF_ROOT=$(Join-Path $LibDir 'tiff')"
)

# --- CPython 3.13 ---
$pySrc = Expand-Package "Python-3.13*.tar.xz" "python"
$pyPrefix = Join-Path $LibDir "python"
if (-not (Test-Path (Join-Path $pyPrefix ".built"))) {
    Write-Host "===== Building CPython 3.13 for Android ====="
    $portableGit = Join-Path $PSScriptRoot ".tools\portable-git"
    $portableBash = Join-Path $portableGit "usr\bin\bash.exe"
    if (-not (Test-Path $portableBash)) {
        Write-Host "Downloading Portable Git (needed to configure CPython)..."
        $git7z = Join-Path $Work "portablegit.7z.exe"
        Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/PortableGit-2.51.0-64-bit.7z.exe" -OutFile $git7z -UseBasicParsing
        New-Item -ItemType Directory -Force -Path $portableGit | Out-Null
        $seven = Join-Path $SdkRoot "cmake\3.31.6\bin"
        # The 7z.exe sfx extracts when run with -y -oDEST
        & $git7z -y "-o$portableGit"
    }
    $bash = $null
    foreach ($cand in @(
        $portableBash,
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )) {
        if ($cand -and (Test-Path $cand)) { $bash = $cand; break }
    }
    if (-not $bash) {
        Write-Warning @"
No bash/WSL found. CPython 3.13 for Android is not built.
Install Git for Windows or WSL, then rerun android/build_deps.ps1.
Blender's UI will not start without this prefix: $pyPrefix
"@
    } else {
        function ConvertTo-BashPath([string]$p) {
            $full = [System.IO.Path]::GetFullPath($p) -replace '\\','/'
            if ($full -match '^([A-Za-z]):') {
                $full = '/' + $Matches[1].ToLower() + $full.Substring(2)
            }
            return $full
        }
        $ndkUnix = ConvertTo-BashPath $Ndk
        $prefixUnix = ConvertTo-BashPath $pyPrefix
        $srcUnix = ConvertTo-BashPath $pySrc
        $hostPyUnix = ConvertTo-BashPath $HostPython
        $llvmBin = ConvertTo-BashPath (Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin")
        $sysrootUnix = ConvertTo-BashPath $Sysroot
        $makeDir = $null
        foreach ($candMake in @(
            (Join-Path $PSScriptRoot ".tools\w64devkit\w64devkit\bin"),
            (Join-Path $PSScriptRoot ".tools\gnumake")
        )) {
            if (Test-Path (Join-Path $candMake "make.exe")) { $makeDir = $candMake; break }
        }
        if (-not $makeDir) { throw "GNU make not found. Expected w64devkit or android/.tools/gnumake/make.exe" }
        $makeUnix = ConvertTo-BashPath $makeDir
        $usrBin = ConvertTo-BashPath (Join-Path $portableGit "usr\bin")
        $script = @"
set -euo pipefail
cd '$srcUnix'
export PATH='$makeUnix':'$usrBin':'$llvmBin':`$PATH
export CC='clang --target=aarch64-linux-android$Api --sysroot=$sysrootUnix'
export CXX='clang++ --target=aarch64-linux-android$Api --sysroot=$sysrootUnix'
export AR=llvm-ar
export RANLIB=llvm-ranlib
export READELF=llvm-readelf
export STRIP=llvm-strip
export LDFLAGS='-Wl,-z,max-page-size=16384'
./configure --host=aarch64-linux-android --build=x86_64-pc-msys \
  --prefix='$prefixUnix' --enable-shared --disable-test-modules \
  ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no \
  --with-build-python='$hostPyUnix' \
  --with-ensurepip=no --without-static-libpython
make -j`$NUMBER_OF_PROCESSORS
make install
"@
        $sh = Join-Path $Work "build_python.sh"
        Set-Content -Path $sh -Value $script -NoNewline -Encoding ASCII
        $shUnix = ConvertTo-BashPath $sh
        & $bash -lc $shUnix
        if ($LASTEXITCODE -ne 0) { throw "Python configure/build failed" }
        Set-Content (Join-Path $pyPrefix ".built") (Get-Date -Format o)
    }
}

Write-Host "Android arm64 dependencies installed under $LibDir"
