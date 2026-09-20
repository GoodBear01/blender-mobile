#!/usr/bin/env bash
# Native macOS makesdna/makesrna/datatoc/shader_tool for the iOS cross-build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}"
SRC="$ROOT/android/host_tools"

if ! command -v cmake >/dev/null; then
  echo "cmake is required. brew install cmake ninja" >&2
  exit 1
fi

mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel
echo "Host tools: $BUILD"
ls -l "$BUILD/makesdna" "$BUILD/makesrna" "$BUILD/datatoc" "$BUILD/shader_tool"
