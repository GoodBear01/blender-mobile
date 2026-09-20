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
CMAKE_BIN="$(command -v cmake || true)"
NINJA_BIN="$(command -v ninja || true)"

if [ -z "$CMAKE_BIN" ] || [ ! -x "$CMAKE_BIN" ]; then
  echo "error: cmake not found on PATH=$PATH" >&2
  exit 127
fi
if [ -z "$NINJA_BIN" ] || [ ! -x "$NINJA_BIN" ]; then
  echo "error: ninja not found on PATH=$PATH" >&2
  exit 127
fi

mkdir -p "$BUILD"
# Host codegen runs binaries from this directory; '.' is not on macOS PATH.
export PATH="$BUILD:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

echo "note: host cmake=$CMAKE_BIN"
echo "note: host ninja=$NINJA_BIN"
echo "note: host SDK=$MACSDK"

# Reconfigure so new host include/stub paths are picked up.
rm -f "$BUILD/CMakeCache.txt"
"$CMAKE_BIN" -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Darwin \
  -DCMAKE_OSX_SYSROOT="$MACSDK" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DCMAKE_MAKE_PROGRAM="$NINJA_BIN"
"$CMAKE_BIN" --build "$BUILD" --parallel

stage_tool() {
  local name="$1"
  if [ -x "$BUILD/$name" ]; then
    return 0
  fi
  local found=""
  local cand
  for cand in "$BUILD/$name" "$BUILD/Release/$name" "$BUILD/Debug/$name"; do
    if [ -f "$cand" ]; then
      found="$cand"
      break
    fi
  done
  if [ -z "$found" ]; then
    found="$(find "$BUILD" -name "$name" -type f -print -quit 2>/dev/null || true)"
  fi
  if [ -n "$found" ] && [ -f "$found" ]; then
    chmod +x "$found" || true
    ln -sf "$found" "$BUILD/$name"
  fi
  if [ ! -x "$BUILD/$name" ]; then
    echo "error: host tool $name was not produced in $BUILD" >&2
    find "$BUILD" -maxdepth 2 -type f -print >&2 || true
    return 1
  fi
}

for t in makesdna makesrna datatoc shader_tool; do
  stage_tool "$t"
done

echo "Host tools: $BUILD"
ls -l "$BUILD/makesdna" "$BUILD/makesrna" "$BUILD/datatoc" "$BUILD/shader_tool"
