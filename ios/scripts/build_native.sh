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
BUILD="${BUILD_IOS:-$ROOT/build_ios}"

if [[ ! -f "$BUILD/CMakeCache.txt" ]]; then
  "${IOS_SCRIPTS:-$ROOT/ios/scripts}/configure_blender.sh"
fi

cmake --build "$BUILD" --target blender --parallel
LIB="$(find "$BUILD" -name 'libblender.dylib' -print -quit || true)"
if [[ -z "$LIB" ]]; then
  echo "libblender.dylib was not produced" >&2
  exit 1
fi
echo "Native iOS Blender library: $LIB"
echo "Next: ios/scripts/stage_native.sh && TEAM=... ./ios/scripts/install_device.sh"
