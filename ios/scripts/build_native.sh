#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${BUILD_IOS:-$ROOT/build_ios}"

if [[ ! -f "$BUILD/CMakeCache.txt" ]]; then
  "$ROOT/ios/scripts/configure_blender.sh"
fi

cmake --build "$BUILD" --target blender --parallel
echo "Native iOS Blender library is in $BUILD/lib or $BUILD/bin"
echo "Add that library plus SDL3 and MoltenVK to the Xcode app target, then Product > Run."
