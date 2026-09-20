#!/usr/bin/env bash
# Build the lite iOS-arm64 dependency set into blender-5.2.0/lib/ios_arm64.
# Must run on a Mac with Xcode, cmake, and ninja.
set -euo pipefail

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
export ROOT
# shellcheck source=xcode_env.sh
. "${IOS_SCRIPTS:-$ROOT/ios/scripts}/xcode_env.sh"
if ! ensure_cmake_ninja; then
  exit 1
fi
BLENDER="$ROOT/blender-5.2.0"
PACKAGES="$ROOT/packages"
LIBDIR="$BLENDER/lib/ios_arm64"
WORK="$ROOT/ios/.deps"
SRC="$WORK/src"
BUILD="$WORK/build"
TOOLCHAIN="$ROOT/ios/cmake/ios.toolchain.cmake"

if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "Xcode iOS SDK not found. Open Xcode and install the iOS platform." >&2
  exit 1
fi

"${IOS_SCRIPTS:-$ROOT/ios/scripts}/download_packages.sh"

mkdir -p "$LIBDIR" "$SRC" "$BUILD"

expand_package() {
  local pattern="$1" dest_name="$2"
  local dest="$SRC/$dest_name"
  if [[ -f "$dest/CMakeLists.txt" || -f "$dest/configure" || -f "$dest/include/vulkan/vulkan.h" ]]; then
    printf '%s\n' "$dest"
    return
  fi
  local archive="" cand
  for cand in "$PACKAGES"/$pattern; do
    if [[ -f "$cand" ]]; then
      archive="$cand"
      break
    fi
  done
  if [[ -z "$archive" ]]; then
    echo "error: missing package $pattern in $PACKAGES" >&2
    exit 1
  fi
  echo "note: Extracting $(basename "$archive") -> $dest" >&2
  local tmp="$WORK/extract-$dest_name"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  tar -xf "$archive" -C "$tmp"
  local inner=""
  for cand in "$tmp"/*; do
    if [[ -e "$cand" ]]; then
      inner="$cand"
      break
    fi
  done
  if [[ -z "$inner" ]]; then
    echo "error: $archive extracted empty" >&2
    exit 1
  fi
  rm -rf "$dest"
  mv "$inner" "$dest"
  rm -rf "$tmp"
  printf '%s\n' "$dest"
}

cmake_dep() {
  local name="$1" source="$2" prefix="$3"
  shift 3
  source="${source##*$'\n'}"
  source="${source%%$'\r'}"
  if [[ -f "$prefix/.built" ]]; then
    echo "note: [skip] $name already built"
    return
  fi
  if [[ ! -d "$source" && ! -f "$source/CMakeLists.txt" ]]; then
    echo "error: $name source is not a directory: $source" >&2
    exit 1
  fi
  local bdir="$BUILD/$name"
  rm -rf "$bdir" "$prefix"
  mkdir -p "$bdir" "$prefix"
  echo "===== Configuring $name ====="
  cmake -S "$source" -B "$bdir" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_PREFIX_PATH="$LIBDIR" \
    -DCMAKE_FIND_ROOT_PATH="$LIBDIR" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_SKIP_RPATH=ON \
    -DCMAKE_SKIP_INSTALL_RPATH=ON \
    -DCMAKE_MACOSX_RPATH=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    "$@"
  echo "===== Building $name ====="
  cmake --build "$bdir" --config Release --parallel
  cmake --install "$bdir"
  date -Iseconds >"$prefix/.built"
}

patch_ocio_for_ios() {
  local src="$1"
  python3 - "$src" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
mon = root / "src/OpenColorIO/SystemMonitor.cpp"
if mon.exists():
    t = mon.read_text()
    if "TARGET_OS_IPHONE" not in t:
        t = t.replace(
            '#include "SystemMonitor_macos.cpp"',
            '#include <TargetConditionals.h>\n'
            '#if TARGET_OS_IPHONE\n'
            'namespace OCIO_NAMESPACE { void SystemMonitorsImpl::getAllMonitors() {} }\n'
            '#else\n'
            '#include "SystemMonitor_macos.cpp"\n'
            '#endif',
            1,
        )
        mon.write_text(t)
        print("note: patched OCIO SystemMonitor for iOS")
cm = root / "src/OpenColorIO/CMakeLists.txt"
if cm.exists():
    t = cm.read_text()
    t2, n = re.subn(
        r"if\(APPLE\)\s*\n(\s*)target_link_libraries\(OpenColorIO",
        r'if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n\1target_link_libraries(OpenColorIO',
        t,
        count=1,
    )
    if n:
        cm.write_text(t2)
        print("note: patched OCIO Apple frameworks for iOS")
PY
}

if [[ -d "$ROOT/android/.deps/src" && ! -d "$SRC/sdl3" ]]; then
  echo "Reusing extracted sources under android/.deps/src where present."
fi

cmake_dep zlib "$(expand_package 'zlib-*.tar.gz' zlib)" "$LIBDIR/zlib" \
  -DZLIB_BUILD_EXAMPLES=OFF
cmake_dep zstd "$(expand_package 'zstd-*.tar.gz' zstd)/build/cmake" "$LIBDIR/zstd" \
  -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON
cmake_dep brotli "$(expand_package 'brotli-*.tar.gz' brotli)" "$LIBDIR/brotli" \
  -DBROTLI_BUNDLED_MODE=OFF
cmake_dep fmt "$(expand_package 'fmt-*.tar.gz' fmt)" "$LIBDIR/fmt" \
  -DFMT_TEST=OFF -DFMT_DOC=OFF
cmake_dep eigen "$(expand_package 'eigen-*.tar.gz' eigen)" "$LIBDIR/eigen" \
  -DBUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF -DEIGEN_BUILD_PKGCONFIG=OFF
cmake_dep png "$(expand_package 'libpng-*.tar.*' libpng)" "$LIBDIR/png" \
  -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_FRAMEWORK=OFF -DPNG_TESTS=OFF \
  -DPNG_TOOLS=OFF -DZLIB_ROOT="$LIBDIR/zlib" -DZLIB_USE_STATIC_LIBS=ON
cmake_dep jpeg "$(expand_package 'libjpeg-turbo-*.tar.gz' libjpeg-turbo)" "$LIBDIR/jpeg" \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=ON
cmake_dep tiff "$(expand_package 'tiff-*.tar.gz' tiff)" "$LIBDIR/tiff" \
  -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-docs=OFF -DZLIB_ROOT="$LIBDIR/zlib" -DJPEG_ROOT="$LIBDIR/jpeg"

set +o pipefail
ZLIB_A="$(find "$LIBDIR/zlib" -name 'libz.a' | head -n 1)"
set -o pipefail
cmake_dep freetype "$(expand_package 'freetype-*.tar.gz' freetype)" "$LIBDIR/freetype" \
  -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_BROTLI=ON \
  -DFT_DISABLE_PNG=ON -DFT_REQUIRE_ZLIB=ON \
  -DZLIB_INCLUDE_DIR="$LIBDIR/zlib/include" -DZLIB_LIBRARY="$ZLIB_A"

cmake_dep imath "$(expand_package 'imath-*.tar.gz' imath)" "$LIBDIR/imath" \
  -DBUILD_TESTING=OFF
cmake_dep openexr "$(expand_package 'openexr-*.tar.gz' openexr)" "$LIBDIR/openexr" \
  -DBUILD_TESTING=OFF -DOPENEXR_BUILD_TOOLS=OFF -DOPENEXR_INSTALL_EXAMPLES=OFF \
  -DImath_ROOT="$LIBDIR/imath" -DZLIB_ROOT="$LIBDIR/zlib"

OPENJPH="$(find "$BUILD/openexr" -name 'libopenjph.a' | head -n 1 || true)"
if [[ -n "$OPENJPH" ]]; then
  mkdir -p "$LIBDIR/openjph/lib" "$LIBDIR/openexr/lib"
  cp -f "$OPENJPH" "$LIBDIR/openjph/lib/libopenjph.a"
  cp -f "$OPENJPH" "$LIBDIR/openexr/lib/libopenjph.a"
fi

EXPAT_SRC="$(expand_package 'libexpat-*.tar.gz' expat)"
if [[ -f "$EXPAT_SRC/expat/CMakeLists.txt" ]]; then
  EXPAT_SRC="$EXPAT_SRC/expat"
fi
cmake_dep expat "$EXPAT_SRC" "$LIBDIR/expat" \
  -DEXPAT_SHARED_LIBS=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF
cmake_dep yaml-cpp "$(expand_package 'yaml-cpp-*.tar.gz' yaml-cpp)" "$LIBDIR/yaml-cpp" \
  -DYAML_BUILD_SHARED_LIBS=OFF -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF

PYSTRING_SRC="$(expand_package 'pystring-*.tar.gz' pystring)"
if [[ ! -f "$PYSTRING_SRC/CMakeLists.txt" ]]; then
  cat >"$PYSTRING_SRC/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(pystring CXX)
add_library(pystring STATIC pystring.cpp)
target_include_directories(pystring PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}> $<INSTALL_INTERFACE:include>)
install(TARGETS pystring ARCHIVE DESTINATION lib)
install(FILES pystring.h DESTINATION include)
EOF
fi
cmake_dep pystring "$PYSTRING_SRC" "$LIBDIR/pystring"
cmake_dep minizip "$(expand_package 'minizip-ng-*.tar.gz' minizip-ng)" "$LIBDIR/minizip-ng" \
  -DMZ_COMPAT=OFF -DMZ_BZIP2=OFF -DMZ_LZMA=OFF -DMZ_ZSTD=ON \
  -DMZ_OPENSSL=OFF -DMZ_LIBCOMP=OFF -DZLIB_ROOT="$LIBDIR/zlib" -Dzstd_ROOT="$LIBDIR/zstd"

ensure_imath_cmake() {
  local prefix="$LIBDIR/imath"
  local cfgdir="$prefix/ocio-cmake"
  local cfg="$cfgdir/ImathConfig.cmake"
  set +o pipefail
  local inc="" lib="" hdr
  if [[ -f "$prefix/include/Imath/ImathVec.h" ]]; then
    inc="$prefix/include"
  else
    hdr="$(find "$prefix" -name 'ImathVec.h' 2>/dev/null | head -n 1)"
    if [[ -n "$hdr" ]]; then
      inc="$(cd "$(dirname "$hdr")/.." && pwd)"
    fi
  fi
  lib="$(find "$prefix" \( -name 'libImath*.a' -o -name 'libImath*.dylib' \) 2>/dev/null | head -n 1)"
  if [[ -z "$lib" ]]; then
    lib="$(find "$prefix" -path '*Imath.framework/Imath' 2>/dev/null | head -n 1)"
  fi
  set -o pipefail
  if [[ -z "$inc" || -z "$lib" ]]; then
    echo "error: Imath install is incomplete under $prefix (include=$inc lib=$lib)" >&2
    return 1
  fi
  mkdir -p "$cfgdir"
  cat >"$cfg" <<EOF
set(Imath_FOUND TRUE)
set(Imath_VERSION "3.2.2")
set(Imath_INCLUDE_DIR "$inc")
set(Imath_INCLUDE_DIRS "$inc;$inc/Imath")
set(Imath_LIBRARY "$lib")
set(Imath_LIBRARIES "$lib")
if(NOT TARGET Imath::Config)
  add_library(Imath::Config INTERFACE IMPORTED)
  set_target_properties(Imath::Config PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "$inc;$inc/Imath")
endif()
if(NOT TARGET Imath::Imath)
  add_library(Imath::Imath STATIC IMPORTED)
  set_target_properties(Imath::Imath PROPERTIES
    IMPORTED_LOCATION "$lib"
    INTERFACE_INCLUDE_DIRECTORIES "$inc;$inc/Imath"
    INTERFACE_LINK_LIBRARIES Imath::Config)
endif()
EOF
  cat >"$cfgdir/ImathConfigVersion.cmake" <<EOF
set(PACKAGE_VERSION "3.2.2")
set(PACKAGE_VERSION_COMPATIBLE TRUE)
set(PACKAGE_VERSION_EXACT FALSE)
EOF
  echo "note: Imath package include=$inc lib=$lib"
  IMATH_DIR="$cfgdir"
  IMATH_INCLUDE="$inc"
  IMATH_LIB="$lib"
}

if ! ensure_imath_cmake; then
  echo "note: rebuilding Imath so OCIO can find it"
  rm -f "$LIBDIR/imath/.built"
  cmake_dep imath "$(expand_package 'imath-*.tar.gz' imath)" "$LIBDIR/imath" \
    -DBUILD_TESTING=OFF -DCMAKE_INSTALL_LIBDIR=lib
  ensure_imath_cmake || exit 1
fi

OCIO_SRC="$(expand_package 'OpenColorIO-*.tar.gz' opencolorio)"
patch_ocio_for_ios "$OCIO_SRC"
cmake_dep opencolorio "$OCIO_SRC" "$LIBDIR/opencolorio" \
  -DOCIO_BUILD_APPS=OFF -DOCIO_BUILD_TESTS=OFF -DOCIO_BUILD_GPU_TESTS=OFF \
  -DOCIO_BUILD_PYTHON=OFF -DOCIO_BUILD_DOCS=OFF \
  -DOCIO_INSTALL_EXT_PACKAGES=NONE \
  -DOCIO_USE_SIMD=OFF -DOCIO_USE_SSE=OFF -DOCIO_USE_SSE2=OFF \
  -DOCIO_USE_AVX=OFF -DOCIO_USE_AVX2=OFF -DOCIO_USE_AVX512=OFF -DOCIO_USE_F16C=OFF \
  -DImath_ROOT="$LIBDIR/imath" -DImath_DIR="$IMATH_DIR" \
  -DImath_INCLUDE_DIR="$IMATH_INCLUDE" -DImath_LIBRARY="$IMATH_LIB" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
  -Dexpat_ROOT="$LIBDIR/expat" \
  -Dpystring_ROOT="$LIBDIR/pystring" \
  -Dyaml-cpp_DIR="$LIBDIR/yaml-cpp/lib/cmake/yaml-cpp" \
  -Dminizip-ng_ROOT="$LIBDIR/minizip-ng"
cmake_dep tbb "$(expand_package 'oneTBB-*.tar.gz' tbb)" "$LIBDIR/tbb" \
  -DTBB_TEST=OFF -DTBB_STRICT=OFF -DBUILD_SHARED_LIBS=ON \
  -DTBBMALLOC_BUILD=OFF -DTBBMALLOC_PROXY_BUILD=OFF
cmake_dep sdl "$(expand_package 'SDL3-*.tar.gz' sdl3)" "$LIBDIR/sdl" \
  -DSDL_SHARED=ON -DSDL_STATIC=ON -DSDL_TEST_LIBRARY=OFF -DSDL_CAMERA=OFF

echo "===== Vulkan headers ====="
if [[ ! -f "$LIBDIR/vulkan/.built" ]]; then
  VK_SRC="$(expand_package 'Vulkan-Headers-*.tar.gz' vulkan-headers)"
  mkdir -p "$LIBDIR/vulkan/include"
  rsync -a "$VK_SRC/include/" "$LIBDIR/vulkan/include/"
  date -Iseconds >"$LIBDIR/vulkan/.built"
fi

echo "===== MoltenVK ====="
if [[ ! -f "$LIBDIR/moltenvk/.built" ]]; then
  mkdir -p "$LIBDIR/moltenvk"
  if command -v brew >/dev/null && brew list molten-vk >/dev/null 2>&1; then
    MVK_XC="$(brew --prefix molten-vk)/share/vulkan/MoltenVK.xcframework"
    if [[ ! -d "$MVK_XC" ]]; then
      MVK_XC="$(find "$(brew --prefix molten-vk)" -name 'MoltenVK.xcframework' | head -n 1 || true)"
    fi
    if [[ -d "$MVK_XC" ]]; then
      rsync -a "$MVK_XC" "$LIBDIR/moltenvk/"
    fi
  fi
  if [[ ! -d "$LIBDIR/moltenvk/MoltenVK.xcframework" ]]; then
    echo "Downloading MoltenVK xcframework..."
    MVK_TAR="$WORK/MoltenVK.tar"
    curl -L --fail -o "$MVK_TAR" \
      "https://github.com/KhronosGroup/MoltenVK/releases/download/v1.2.11/MoltenVK-macos.tar" \
      || curl -L --fail -o "$MVK_TAR" \
      "https://github.com/KhronosGroup/MoltenVK/releases/download/v1.3.0/MoltenVK-macos.tar"
    mkdir -p "$WORK/moltenvk-extract"
    tar -xf "$MVK_TAR" -C "$WORK/moltenvk-extract"
    XC="$(find "$WORK/moltenvk-extract" -name 'MoltenVK.xcframework' | head -n 1 || true)"
    if [[ -z "$XC" ]]; then
      echo "Install MoltenVK: brew install molten-vk" >&2
      exit 1
    fi
    rsync -a "$XC" "$LIBDIR/moltenvk/"
  fi
  date -Iseconds >"$LIBDIR/moltenvk/.built"
fi

echo "===== shaderc ====="
SHADERC_SRC="$(expand_package 'shaderc-*.tar.gz' shaderc)"
THIRD="$SHADERC_SRC/third_party"
mkdir -p "$THIRD"
clone_rev() {
  local url="$1" rev="$2" dest="$3"
  if [[ -f "$dest/CMakeLists.txt" ]]; then
    return
  fi
  rm -rf "$dest"
  git clone --depth 1 "$url" "$dest"
}
clone_rev "https://github.com/KhronosGroup/glslang.git" "d213562e35573012b6348b2d584457c3704ac09b" "$THIRD/glslang"
clone_rev "https://github.com/KhronosGroup/SPIRV-Headers.git" "01e0577914a75a2569c846778c2f93aa8e6feddd" "$THIRD/spirv-headers"
clone_rev "https://github.com/KhronosGroup/SPIRV-Tools.git" "19042c8921f35f7bec56b9e5c96c5f5691588ca8" "$THIRD/spirv-tools"
cmake_dep shaderc "$SHADERC_SRC" "$LIBDIR/shaderc" \
  -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
  -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON -DENABLE_GLSLANG_BINARIES=OFF \
  -DPYTHON_EXECUTABLE="$(command -v python3)"

if [[ ! -f "$LIBDIR/robin-map/.built" ]]; then
  ROBIN_ZIP="$WORK/robin-map.zip"
  curl -L --fail -o "$ROBIN_ZIP" "https://github.com/Tessil/robin-map/archive/refs/tags/v1.4.0.zip"
  rm -rf "$WORK/robin-map-src"
  mkdir -p "$WORK/robin-map-src"
  tar -xf "$ROBIN_ZIP" -C "$WORK/robin-map-src" 2>/dev/null || unzip -q "$ROBIN_ZIP" -d "$WORK/robin-map-src"
  set +o pipefail
  ROBIN_INNER="$(find "$WORK/robin-map-src" -mindepth 1 -maxdepth 1 | head -n 1)"
  set -o pipefail
  cmake_dep robin-map "$ROBIN_INNER" "$LIBDIR/robin-map"
fi

cmake_dep openimageio "$(expand_package 'OpenImageIO-*.tar.gz' openimageio)" "$LIBDIR/openimageio" \
  -DRobinmap_ROOT="$LIBDIR/robin-map" -DRobinMap_ROOT="$LIBDIR/robin-map" \
  -DOIIO_BUILD_TOOLS=OFF -DOIIO_BUILD_TESTS=OFF -DBUILD_TESTING=OFF \
  -DUSE_PYTHON=OFF -DUSE_QT=OFF -DUSE_OPENGL=OFF -DUSE_OPENCV=OFF \
  -DUSE_FREETYPE=OFF -DUSE_GIF=OFF -DUSE_OPENJPEG=OFF -DUSE_WEBP=OFF \
  -DUSE_FFMPEG=OFF -DUSE_PTEX=OFF -DUSE_LIBHEIF=OFF -DUSE_LIBRAW=OFF \
  -DOpenEXR_ROOT="$LIBDIR/openexr" -DImath_ROOT="$LIBDIR/imath" \
  -DZLIB_ROOT="$LIBDIR/zlib" -Dfmt_ROOT="$LIBDIR/fmt" \
  -DJPEG_ROOT="$LIBDIR/jpeg" -DPNG_ROOT="$LIBDIR/png" -DTIFF_ROOT="$LIBDIR/tiff"

echo "===== Python 3.13 for iOS ====="
if [[ ! -f "$LIBDIR/python/.built" ]]; then
  PY_SUPPORT="$WORK/python-apple-support"
  PY_TAR="$WORK/Python-iOS-support.tar.gz"
  if [[ ! -f "$PY_SUPPORT/.extracted" ]]; then
    mkdir -p "$WORK"
    set +e
    curl -L --fail -o "$PY_TAR" \
      "https://github.com/beeware/Python-Apple-support/releases/download/3.13-b15/Python-3.13-iOS-support.b15.tar.gz" \
    || curl -L --fail -o "$PY_TAR" \
      "https://github.com/beeware/Python-Apple-support/releases/download/3.13-b11/Python-3.13-iOS-support.b11.tar.gz" \
    || curl -L --fail -o "$PY_TAR" \
      "https://github.com/beeware/Python-Apple-support/releases/download/3.13-b8/Python-3.13-iOS-support.b8.tar.gz"
    set -e
    if [[ ! -s "$PY_TAR" ]]; then
      echo "error: failed to download Python-Apple-support" >&2
      exit 1
    fi
    rm -rf "$PY_SUPPORT"
    mkdir -p "$PY_SUPPORT"
    tar -xf "$PY_TAR" -C "$PY_SUPPORT"
    date -Iseconds >"$PY_SUPPORT/.extracted"
  fi
  echo "note: BeeWare Python entries:"
  set +o pipefail
  find "$PY_SUPPORT" \( -name 'Python.h' -o -name 'libpython3.13*' -o -name 'Python.xcframework' -o -name 'Python.framework' -o -name 'abc.py' \) | head -n 40
  HDR="$(find "$PY_SUPPORT" -name 'Python.h' | grep -v simulator | head -n 1)"
  if [[ -z "$HDR" ]]; then
    HDR="$(find "$PY_SUPPORT" -name 'Python.h' | head -n 1)"
  fi
  LIBPY="$(find "$PY_SUPPORT" \( -name 'libpython3.13.a' -o -name 'libpython3.13.dylib' \) | grep -v simulator | head -n 1)"
  if [[ -z "$LIBPY" ]]; then
    LIBPY="$(find "$PY_SUPPORT" \( -name 'libpython3.13.a' -o -name 'libpython3.13.dylib' \) | head -n 1)"
  fi
  FWBIN="$(find "$PY_SUPPORT" -path '*ios-arm64*' -name 'Python' -type f | grep -v simulator | head -n 1)"
  STDLIB_PY="$(find "$PY_SUPPORT" -name 'abc.py' | grep -v simulator | head -n 1)"
  if [[ -z "$STDLIB_PY" ]]; then
    STDLIB_PY="$(find "$PY_SUPPORT" -name 'abc.py' | head -n 1)"
  fi
  set -o pipefail

  mkdir -p "$LIBDIR/python/include/python3.13" "$LIBDIR/python/lib/python3.13"
  if [[ -n "$HDR" ]]; then
    echo "note: Python.h from $HDR"
    rsync -a "$(dirname "$HDR")/" "$LIBDIR/python/include/python3.13/"
  fi
  if [[ -n "$LIBPY" ]]; then
    echo "note: libpython from $LIBPY"
    cp -f "$LIBPY" "$LIBDIR/python/lib/$(basename "$LIBPY")"
  fi
  if [[ -n "$FWBIN" && ! -e "$LIBDIR/python/lib/libpython3.13.dylib" && ! -e "$LIBDIR/python/lib/libpython3.13.a" ]]; then
    cp -f "$FWBIN" "$LIBDIR/python/lib/libpython3.13.dylib"
  fi
  if [[ -n "$STDLIB_PY" ]]; then
    echo "note: stdlib from $(dirname "$STDLIB_PY")"
    rsync -a "$(dirname "$STDLIB_PY")/" "$LIBDIR/python/lib/python3.13/"
  fi
  XC="$(find "$PY_SUPPORT" -name 'Python.xcframework' | head -n 1 || true)"
  if [[ -d "$XC" ]]; then
    rsync -a "$XC" "$LIBDIR/python/"
  fi
  if [[ ! -f "$LIBDIR/python/include/python3.13/Python.h" ]]; then
    echo "error: Python-Apple-support extracted but Python.h was not found." >&2
    echo "error: Extracted tree:" >&2
    find "$PY_SUPPORT" -maxdepth 5 -print | head -n 80 >&2
    exit 1
  fi
  if [[ ! -e "$LIBDIR/python/lib/libpython3.13.a" && ! -e "$LIBDIR/python/lib/libpython3.13.dylib" ]]; then
    echo "error: Python.h is present but libpython3.13 is missing" >&2
    exit 1
  fi
  date -Iseconds >"$LIBDIR/python/.built"
fi

cat >"$LIBDIR/README.md" <<'EOF'
iOS arm64 prebuilts produced by ios/scripts/build_deps.sh on a Mac.
Android lib/android_arm64 binaries cannot be reused here.
EOF

echo "iOS dependency build finished. LIBDIR=$LIBDIR"
