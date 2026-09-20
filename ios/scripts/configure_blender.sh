#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLENDER="$ROOT/blender-5.2.0"
BUILD="${BUILD_IOS:-$ROOT/build_ios}"
TOOLCHAIN="$ROOT/ios/cmake/ios.toolchain.cmake"
PRESET="$BLENDER/build_files/cmake/config/blender_ios.cmake"
LIBDIR="$BLENDER/lib/ios_arm64"

if [[ ! -f "$LIBDIR/zlib/.built" && ! -f "$LIBDIR/sdl/.built" ]]; then
  echo "iOS libraries are not built yet. That is why cmake prints a wall of errors." >&2
  echo "On this Mac run first:" >&2
  echo "  ./ios/scripts/build_deps.sh" >&2
  echo "To only prove the phone install, open ios/BlenderMobile.xcodeproj and run the stub." >&2
  exit 1
fi

mkdir -p "$BUILD"
cmake -S "$BLENDER" -B "$BUILD" \
  -G Ninja \
  -C "$PRESET" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  "$@"

echo "Configured $BUILD. Next: ios/scripts/build_native.sh"
