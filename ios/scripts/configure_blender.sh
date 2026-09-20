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
cmake -S "$BLENDER" -B "$BUILD" \
  -G Ninja \
  -C "$PRESET" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBDIR="$LIBDIR" \
  -DHOST_TOOLS_DIR="$HOST_TOOLS_DIR" \
  -DPYTHON_EXECUTABLE="$(command -v python3)" \
  "$@"

echo "Configured $BUILD. Next: ios/scripts/build_native.sh"
