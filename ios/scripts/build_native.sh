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

if ! cmake --build "$BUILD" --target blender --parallel; then
  echo "error: libblender compile/link failed. Retrying the failed step with -v:" >&2
  cmake --build "$BUILD" --target blender -- -v -j1 || true
  exit 1
fi
LIB="$(find "$BUILD" \( -name 'libblender.dylib' -o -name 'libblender.so' \) -print -quit || true)"
if [[ -z "$LIB" ]]; then
  echo "libblender.dylib was not produced" >&2
  echo "note: blender outputs under $BUILD:" >&2
  find "$BUILD" \( -name 'libblender*' -o -name 'Blender.app' -o -name 'blender' \) -print >&2 || true
  if [[ -d "$BUILD/bin/Blender.app" ]]; then
    echo "error: ninja built a macOS Blender.app. CMAKE_SYSTEM_NAME is not iOS." >&2
  fi
  exit 1
fi
if [[ "$LIB" == *.so ]]; then
  DYLIB="${LIB%.so}.dylib"
  ln -sfn "$(basename "$LIB")" "$DYLIB"
  LIB="$DYLIB"
fi
echo "Native iOS Blender library: $LIB"
echo "Next: ios/scripts/stage_native.sh && TEAM=... ./ios/scripts/install_device.sh"
