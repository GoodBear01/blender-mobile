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
# A leftover wrapper at ios/clang++ makes Xcode report every ld failure as
# ios/clang++:1:1 and can drop the iPhone sysroot on the link line.
rm -f "$ROOT/ios/clang" "$ROOT/ios/clang++" "$ROOT/ios/cc" "$ROOT/ios/c++"
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
  -DLIBDIR="$LIBDIR" \
  -DHOST_TOOLS_DIR="$HOST_TOOLS_DIR" \
  -DPYTHON_EXECUTABLE="$PY3" \
  "$@"

if ! grep -q 'CMAKE_SYSTEM_NAME:STRING=iOS' "$BUILD/CMakeCache.txt"; then
  echo "error: configure did not set CMAKE_SYSTEM_NAME=iOS" >&2
  grep CMAKE_SYSTEM_NAME "$BUILD/CMakeCache.txt" >&2 || true
  exit 1
fi
if ! grep -q 'libblender.dylib' "$BUILD/build.ninja"; then
  echo "error: ninja graph is not linking libblender.dylib (macOS app graph?)" >&2
  grep -E 'Blender.app|libblender' "$BUILD/build.ninja" | head -n 20 >&2 || true
  exit 1
fi

echo "Configured $BUILD. Next: ios/scripts/build_native.sh"
