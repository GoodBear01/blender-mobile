#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLENDER="$ROOT/blender-5.2.0"
BUILD="${BUILD_IOS:-$ROOT/build_ios}"
TOOLCHAIN="$ROOT/ios/cmake/ios.toolchain.cmake"
PRESET="$BLENDER/build_files/cmake/config/blender_ios.cmake"

mkdir -p "$BUILD"
cmake -S "$BLENDER" -B "$BUILD" \
  -G Ninja \
  -C "$PRESET" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  "$@"

echo "Configured $BUILD. Next: ios/scripts/build_native.sh"
