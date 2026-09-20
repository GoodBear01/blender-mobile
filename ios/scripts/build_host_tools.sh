#!/usr/bin/env bash
# Native macOS makesdna/makesrna/datatoc/shader_tool for the iOS cross-build.
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

BUILD="${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}"
SRC="$ROOT/android/host_tools"
MACSDK="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$BUILD"
# Reconfigure so new host include/stub paths are picked up.
rm -f "$BUILD/CMakeCache.txt"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Darwin \
  -DCMAKE_OSX_SYSROOT="$MACSDK" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
cmake --build "$BUILD" --parallel
echo "Host tools: $BUILD"
ls -l "$BUILD/makesdna" "$BUILD/makesrna" "$BUILD/datatoc" "$BUILD/shader_tool"
