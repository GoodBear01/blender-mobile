#!/usr/bin/env bash
# Called by Xcode. Compiles the full editor. Never writes back into ios/scripts.
set -e
trap 'echo "Blender iOS: compile failed at line $LINENO running: $BASH_COMMAND" >&2' ERR

if [ -n "${SRCROOT:-}" ] && [ -d "${SRCROOT}/../blender-5.2.0" ]; then
  IOS_ROOT="${SRCROOT}"
  ROOT="$(cd "${SRCROOT}/.." && pwd)"
elif [ -n "${SRCROOT:-}" ] && [ -d "${SRCROOT}/blender-5.2.0" ]; then
  ROOT="${SRCROOT}"
  IOS_ROOT="${ROOT}/ios"
elif [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  IOS_ROOT="${ROOT}/ios"
else
  IOS_ROOT="${IOS_ROOT:-${ROOT}/ios}"
fi
export ROOT IOS_ROOT

echo "Blender iOS: ROOT=$ROOT"
echo "Blender iOS: SRCROOT=${SRCROOT:-}"

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
for f in "$ROOT/ios/scripts/"*.sh "$ROOT/ios/scripts/"*.py; do
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

echo "Blender iOS: compiling the editor into $ROOT"
echo "Blender iOS: git=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Blender iOS: only files that changed are rebuilt."

if ! ensure_cmake_ninja; then
  exit 1
fi
echo "Blender iOS: cmake=$(command -v cmake)"
echo "Blender iOS: ninja=$(command -v ninja)"

LIBDIR_IOS="$ROOT/blender-5.2.0/lib/ios_arm64"
if [ ! -f "$LIBDIR_IOS/python/.built" ] || [ ! -f "$LIBDIR_IOS/sdl/.built" ] \
    || { [ ! -e "$LIBDIR_IOS/vulkan/lib/libvulkan.a" ] && [ ! -e "$LIBDIR_IOS/moltenvk/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK" ]; }; then
  echo "Blender iOS: building SDL, Python, and MoltenVK"
  /bin/bash "$WORK/build_deps.sh"
fi

if [ ! -x "${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}/makesrna" ]; then
  echo "Blender iOS: building macOS host codegen tools"
  /bin/bash "$WORK/build_host_tools.sh"
fi

if [ ! -d "$ROOT/ios/BlenderMobile/Runtime/blender/5.2/scripts" ] \
    || [ ! -f "$ROOT/ios/BlenderMobile/Runtime/blender/5.2/python/lib/python3.13/encodings/__init__.py" ] \
    || [ ! -f "$ROOT/ios/BlenderMobile/Runtime/blender/5.2/scripts/addons_core/cycles/__init__.py" ] \
    || [ ! -f "$ROOT/ios/BlenderMobile/Runtime/blender/5.2/datafiles/fonts/Inter.woff2" ]; then
  echo "Blender iOS: packing scripts, datafiles, and the Python standard library"
  /bin/bash "$WORK/package_runtime.sh"
fi

BUILD_IOS_DIR="${BUILD_IOS:-$ROOT/build_ios}"
# Always keep working iPhone compiler wrappers at ios/clang++.
for _w in clang clang++; do
  cat >"$ROOT/ios/$_w" <<EOF
#!/bin/bash
exec xcrun --sdk iphoneos $_w "\$@"
EOF
  chmod +x "$ROOT/ios/$_w"
done
# Stale Mac checkouts still call shaderc SetMaxIdBound, which 2025.3 does not have.
SHADER_CC="$ROOT/blender-5.2.0/source/blender/gpu/vulkan/vk_shader_compiler.cc"
if [ -f "$SHADER_CC" ] && grep -q 'SetMaxIdBound' "$SHADER_CC"; then
  /usr/bin/python3 - "$SHADER_CC" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines(True)
out = []
changed = False
for line in lines:
    stripped = line.lstrip()
    if "SetMaxIdBound" in line and not stripped.startswith(("//", "/*", "*")):
        out.append("  /* SetMaxIdBound omitted: iOS shaderc 2025.3 has no such method */\n")
        changed = True
    else:
        out.append(line)
if changed:
    path.write_text("".join(out), encoding="utf-8")
    print("Blender iOS: removed SetMaxIdBound so shaderc 2025.3 can compile")
PY
fi
CREATOR_CMAKE="$ROOT/blender-5.2.0/source/creator/CMakeLists.txt"
if grep -q 'else# BLENDER_IOS_FORCE_DYLIB' "$CREATOR_CMAKE" 2>/dev/null; then
  echo "Blender iOS: restoring creator CMakeLists.txt after a bad dylib patch"
  git -C "$ROOT" checkout -- blender-5.2.0/source/creator/CMakeLists.txt || true
fi
if [ -f "$WORK/force_ios_dylib.py" ]; then
  /usr/bin/python3 "$WORK/force_ios_dylib.py" "$CREATOR_CMAKE" || true
fi
# A Darwin cache or a Blender.app ninja graph must not be reused.
NEED_CONFIG=0
if [ ! -f "$BUILD_IOS_DIR/build.ninja" ] || [ ! -f "$BUILD_IOS_DIR/CMakeCache.txt" ]; then
  NEED_CONFIG=1
fi
if ! grep -q 'CMAKE_SYSTEM_NAME:STRING=iOS' "$BUILD_IOS_DIR/CMakeCache.txt" 2>/dev/null; then
  NEED_CONFIG=1
fi
if grep -q 'Blender.app' "$BUILD_IOS_DIR/build.ninja" 2>/dev/null; then
  NEED_CONFIG=1
fi
if [ -d "$BUILD_IOS_DIR/bin/Blender.app" ]; then
  NEED_CONFIG=1
fi
if [ -f "$BUILD_IOS_DIR/build.ninja" ] && ! find "$BUILD_IOS_DIR" -iname 'libblender.dylib' -print -quit | grep -q .; then
  NEED_CONFIG=1
fi
if grep -q '/ios/clang' "$BUILD_IOS_DIR/CMakeCache.txt" 2>/dev/null; then
  NEED_CONFIG=1
fi
if grep -q 'fsmenu_system_macos.mm' "$BUILD_IOS_DIR/build.ninja" 2>/dev/null; then
  NEED_CONFIG=1
fi
if [ "$NEED_CONFIG" = 1 ]; then
  echo "Blender iOS: clearing the macOS ninja graph and configuring libblender.dylib"
  rm -rf "$BUILD_IOS_DIR"
  /bin/bash "$WORK/configure_blender.sh"
fi

echo "Blender iOS: compiling libblender.dylib"
/bin/bash "$WORK/build_native.sh"
/bin/bash "$WORK/stage_native.sh"

if [ ! -f "$IOS_ROOT/Vendor/libblender.dylib" ]; then
  echo "error: libblender.dylib was not produced at $IOS_ROOT/Vendor/libblender.dylib" >&2
  exit 1
fi

echo "Blender iOS: full editor library is ready for the app target"
