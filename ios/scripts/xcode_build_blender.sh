#!/usr/bin/env bash
# Called by Xcode. Compiles the full editor. Never writes back into ios/scripts.
set -e
trap 'echo "note: compile failed at line $LINENO running: $BASH_COMMAND" >&2' ERR

if [ -n "${SRCROOT:-}" ]; then
  ROOT="$(cd "${SRCROOT}/.." && pwd)"
elif [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
export ROOT

echo "note: ROOT=$ROOT"
echo "note: SRCROOT=${SRCROOT:-}"

if [ ! -d "$ROOT/blender-5.2.0" ]; then
  echo "error: blender-5.2.0 not found next to ios/. Open ios/BlenderMobile.xcodeproj from the repo." >&2
  echo "error: ROOT=$ROOT SRCROOT=${SRCROOT:-}" >&2
  exit 1
fi

if [ ! -d "$ROOT/ios/scripts" ]; then
  echo "error: ios/scripts is missing under $ROOT" >&2
  exit 1
fi

# Strip Windows CRLF into DerivedData. Do not touch the checkout.
WORK="${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}/blender-ios}/scripts"
mkdir -p "$WORK"
for f in "$ROOT/ios/scripts/"*.sh; do
  [ -f "$f" ] || continue
  /usr/bin/tr -d '\r' < "$f" > "$WORK/$(basename "$f")"
  chmod +x "$WORK/$(basename "$f")" || true
done
if [ ! -f "$WORK/xcode_env.sh" ]; then
  echo "error: failed to stage ios scripts into $WORK" >&2
  ls -la "$ROOT/ios/scripts" >&2 || true
  exit 1
fi
export IOS_SCRIPTS="$WORK"

# shellcheck source=xcode_env.sh
. "$WORK/xcode_env.sh"

echo "note: Compiling full Blender UI for iOS into $ROOT"
echo "note: git=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "note: First Xcode Run can take hours. Later Runs only rebuild what changed."

if ! ensure_cmake_ninja; then
  exit 1
fi
echo "note: cmake=$(command -v cmake)"
echo "note: ninja=$(command -v ninja)"

LIBDIR_IOS="$ROOT/blender-5.2.0/lib/ios_arm64"
if [ ! -f "$LIBDIR_IOS/python/.built" ] || [ ! -f "$LIBDIR_IOS/sdl/.built" ] \
    || { [ ! -e "$LIBDIR_IOS/vulkan/lib/libvulkan.a" ] && [ ! -e "$LIBDIR_IOS/moltenvk/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK" ]; }; then
  echo "note: Building iOS libraries (SDL, Python, MoltenVK)"
  /bin/bash "$WORK/build_deps.sh"
fi

if [ ! -x "${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}/makesrna" ]; then
  echo "note: Building macOS host codegen tools"
  /bin/bash "$WORK/build_host_tools.sh"
fi

if [ ! -d "$ROOT/ios/BlenderMobile/Runtime/blender/5.2/scripts" ]; then
  echo "note: Packing Blender scripts and datafiles"
  /bin/bash "$WORK/package_runtime.sh"
fi

BUILD_IOS_DIR="${BUILD_IOS:-$ROOT/build_ios}"
if [ ! -f "$BUILD_IOS_DIR/build.ninja" ] \
    || ! grep -q -- '-funsigned-char' "$BUILD_IOS_DIR/CMakeCache.txt" 2>/dev/null \
    || grep -q 'fsmenu_system_macos.mm' "$BUILD_IOS_DIR/build.ninja" 2>/dev/null; then
  echo "note: Configuring libblender"
  rm -f "$BUILD_IOS_DIR/CMakeCache.txt"
  /bin/bash "$WORK/configure_blender.sh"
fi

echo "note: Compiling libblender.dylib"
/bin/bash "$WORK/build_native.sh"
/bin/bash "$WORK/stage_native.sh"

if [ ! -f "$ROOT/ios/Vendor/libblender.dylib" ]; then
  echo "error: libblender.dylib was not produced" >&2
  exit 1
fi

echo "note: Full Blender UI is ready for the app target"
