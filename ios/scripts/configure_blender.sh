#!/usr/bin/env bash
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
BUILD="${BUILD_IOS:-$ROOT/build_ios}"
TOOLCHAIN="$ROOT/ios/cmake/ios.toolchain.cmake"
PRESET="$BLENDER/build_files/cmake/config/blender_ios.cmake"
LIBDIR="$BLENDER/lib/ios_arm64"
HOST_TOOLS_DIR="${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}"

if [[ ! -f "$LIBDIR/zlib/.built" || ! -f "$LIBDIR/sdl/.built" || ! -f "$LIBDIR/python/.built" ]]; then
  echo "iOS libraries are incomplete. Run:" >&2
  echo "  ./ios/scripts/build_full_app.sh" >&2
  exit 1
fi
if [[ ! -x "$HOST_TOOLS_DIR/makesrna" ]]; then
  echo "Host tools missing. Run ./ios/scripts/build_host_tools.sh" >&2
  exit 1
fi

mkdir -p "$BUILD"
if [[ -f "$BUILD/CMakeCache.txt" && ! -f "$BUILD/build.ninja" ]]; then
  echo "note: Removing incomplete iOS CMake cache"
  rm -f "$BUILD/CMakeCache.txt"
fi
NINJA_BIN="$(command -v ninja || true)"
PY3="$(command -v python3 || true)"
if [ -z "$PY3" ] && [ -x /usr/bin/python3 ]; then
  PY3=/usr/bin/python3
fi
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IOS_CC="$(xcrun --sdk iphoneos -f clang)"
IOS_CXX="$(xcrun --sdk iphoneos -f clang++)"
cmake -S "$BLENDER" -B "$BUILD" \
  -G Ninja \
  -C "$PRESET" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_C_COMPILER="$IOS_CC" \
  -DCMAKE_CXX_COMPILER="$IOS_CXX" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
  -DIOS=TRUE \
  -DLIBDIR="$LIBDIR" \
  -DHOST_TOOLS_DIR="$HOST_TOOLS_DIR" \
  -DPYTHON_EXECUTABLE="$PY3" \
  "$@"

if ! grep -qE 'libblender\.(dylib|so)|CXX_SHARED_LIBRARY_LINKER' "$BUILD/build.ninja"; then
  echo "Blender iOS: ninja graph is not a shared libblender. Dumping blender link rules:" >&2
  grep -n -E 'libblender|Blender.app|CXX_SHARED|CXX_EXECUTABLE|CXX_MODULE' "$BUILD/build.ninja" | head -n 40 >&2 || true
  echo "Blender iOS: CMAKE_SYSTEM_NAME/IOS/LIBDIR from cache:" >&2
  grep -E 'CMAKE_SYSTEM_NAME|IOS:|LIBDIR:' "$BUILD/CMakeCache.txt" | head -n 20 >&2 || true
  exit 1
fi

echo "Configured $BUILD. Next: ios/scripts/build_native.sh"
