#!/usr/bin/env bash
# Build the lite iOS-arm64 dependency set into blender-5.2.0/lib/ios_arm64.
# Must run on a Mac with Xcode and cmake.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLENDER="$ROOT/blender-5.2.0"
PACKAGES="$ROOT/packages"
LIBDIR="$BLENDER/lib/ios_arm64"
WORK="$ROOT/ios/.deps"
SRC="$WORK/src"
BUILD="$WORK/build"
TOOLCHAIN="$ROOT/ios/cmake/ios.toolchain.cmake"

if ! command -v cmake >/dev/null; then
  echo "cmake is required. brew install cmake" >&2
  exit 1
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "Xcode iOS SDK not found. Open Xcode and install the iOS platform." >&2
  exit 1
fi

mkdir -p "$LIBDIR" "$SRC" "$BUILD"

expand_package() {
  local pattern="$1" dest_name="$2"
  local dest="$SRC/$dest_name"
  if [[ -f "$dest/CMakeLists.txt" || -f "$dest/configure" ]]; then
    echo "$dest"
    return
  fi
  local archive
  archive="$(ls -1 "$PACKAGES"/$pattern 2>/dev/null | head -n 1 || true)"
  if [[ -z "$archive" ]]; then
    echo "Missing package $pattern in $PACKAGES" >&2
    exit 1
  fi
  echo "Extracting $(basename "$archive") -> $dest"
  local tmp="$WORK/extract-$dest_name"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  tar -xf "$archive" -C "$tmp"
  local inner
  inner="$(find "$tmp" -mindepth 1 -maxdepth 1 | head -n 1)"
  rm -rf "$dest"
  mv "$inner" "$dest"
  rm -rf "$tmp"
  echo "$dest"
}

cmake_dep() {
  local name="$1" source="$2" prefix="$3"
  shift 3
  if [[ -f "$prefix/.built" ]]; then
    echo "[skip] $name already built"
    return
  fi
  local bdir="$BUILD/$name"
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
    -DBUILD_SHARED_LIBS=OFF \
    "$@"
  echo "===== Building $name ====="
  cmake --build "$bdir" --config Release --parallel
  cmake --install "$bdir"
  date -Iseconds >"$prefix/.built"
}

# zlib, zstd, brotli, fmt, eigen, png, jpeg, tiff, freetype, imath, openexr,
# expat, yaml-cpp, SDL3, vulkan headers, shaderc, tbb, python, moltenvk.
# Sources can come from packages/ (same archives as Android) or ios/.deps/src.

if [[ -d "$ROOT/android/.deps/src" && ! -d "$SRC/sdl3" ]]; then
  echo "Reusing extracted sources under android/.deps/src where present."
fi

cmake_dep zlib "$(expand_package 'zlib-*.tar.gz' zlib)" "$LIBDIR/zlib"
cmake_dep zstd "$(expand_package 'zstd-*.tar.gz' zstd)/build/cmake" "$LIBDIR/zstd" \
  -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON
cmake_dep brotli "$(expand_package 'brotli-*.tar.gz' brotli)" "$LIBDIR/brotli" \
  -DBROTLI_BUNDLED_MODE=OFF
cmake_dep fmt "$(expand_package 'fmt-*.tar.gz' fmt)" "$LIBDIR/fmt" \
  -DFMT_TEST=OFF -DFMT_DOC=OFF
cmake_dep eigen "$(expand_package 'eigen-*.tar.gz' eigen)" "$LIBDIR/eigen" \
  -DBUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF
cmake_dep png "$(expand_package 'libpng-*.tar.xz' libpng)" "$LIBDIR/png" \
  -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DZLIB_ROOT="$LIBDIR/zlib"
cmake_dep jpeg "$(expand_package 'libjpeg-turbo-*.tar.gz' libjpeg-turbo)" "$LIBDIR/jpeg" \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=ON

echo "===== SDL3 xcframework ====="
SDL_SRC="${SDL_SRC:-$ROOT/android/.deps/src/sdl3}"
if [[ ! -d "$SDL_SRC" ]]; then
  SDL_SRC="$(expand_package 'SDL3-*.tar.gz' sdl3)"
fi
if [[ ! -f "$LIBDIR/sdl/.built" ]]; then
  if [[ -f "$SDL_SRC/Xcode/SDL/SDL.xcodeproj/project.pbxproj" ]]; then
    xcodebuild -project "$SDL_SRC/Xcode/SDL/SDL.xcodeproj" \
      -scheme SDL3 \
      -sdk iphoneos \
      -arch arm64 \
      -configuration Release \
      BUILD_DIR="$BUILD/sdl3" \
      CODE_SIGNING_ALLOWED=NO
  else
    cmake_dep sdl "$SDL_SRC" "$LIBDIR/sdl" \
      -DSDL_SHARED=ON -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_TESTS=OFF
  fi
  mkdir -p "$LIBDIR/sdl"
  date -Iseconds >"$LIBDIR/sdl/.built"
fi

echo "===== MoltenVK ====="
if [[ ! -f "$LIBDIR/moltenvk/.built" ]]; then
  if command -v brew >/dev/null && brew list molten-vk >/dev/null 2>&1; then
    mkdir -p "$LIBDIR/moltenvk"
    echo "Use the MoltenVK xcframework from Homebrew when linking the Xcode app."
    date -Iseconds >"$LIBDIR/moltenvk/.built"
  else
    echo "Install MoltenVK on the Mac: brew install molten-vk"
    echo "Then copy MoltenVK.xcframework into the Xcode project's Frameworks."
  fi
fi

echo "===== Vulkan headers ====="
if [[ ! -f "$LIBDIR/vulkan/.built" ]]; then
  VULKAN_SRC="${VULKAN_SRC:-$ROOT/android/.deps/src/vulkan-headers}"
  if [[ -d "$VULKAN_SRC" ]]; then
    cmake_dep vulkan "$VULKAN_SRC" "$LIBDIR/vulkan"
  else
    echo "Unpack vulkan-headers into android/.deps/src/vulkan-headers or packages/"
  fi
fi

cat >"$LIBDIR/README.md" <<'EOF'
iOS arm64 prebuilts produced by ios/scripts/build_deps.sh on a Mac.
Android lib/android_arm64 binaries cannot be reused here.
EOF

echo "iOS dependency build finished. Remaining optional deps (Python, OpenImageIO, TBB, shaderc)"
echo "use the same cmake_dep pattern as android/build_deps.ps1 once their sources are unpacked."
echo "LIBDIR=$LIBDIR"
