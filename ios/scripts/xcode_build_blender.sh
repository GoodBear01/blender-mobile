#!/usr/bin/env bash
# Called by Xcode (Run Script or libblender target). Compiles the full editor.
set -eu

if [[ -n "${SRCROOT:-}" ]]; then
  ROOT="$(cd "${SRCROOT}/.." && pwd)"
elif [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
else
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

# Windows checkouts give scripts CRLF; bash then dies on `set -o pipefail`.
for f in "$ROOT/ios/scripts/"*.sh; do
  [[ -f "$f" ]] || continue
  [[ "$f" -ef "$0" ]] && continue
  tr -d '\r' < "$f" > "$f.lf"
  mv "$f.lf" "$f"
  chmod +x "$f" || true
done

# shellcheck source=xcode_env.sh
source "$ROOT/ios/scripts/xcode_env.sh"
set -o pipefail

echo "note: Compiling full Blender UI for iOS into $ROOT"
echo "note: First Xcode Run can take hours. Later Runs only rebuild what changed."

if ! ensure_cmake_ninja; then
  exit 1
fi
echo "note: cmake=$(command -v cmake) ninja=$(command -v ninja)"

chmod +x "$ROOT/ios/scripts/"*.sh 2>/dev/null || true

if [[ ! -f "$ROOT/blender-5.2.0/lib/ios_arm64/python/.built" || ! -f "$ROOT/blender-5.2.0/lib/ios_arm64/sdl/.built" ]]; then
  echo "note: Building iOS libraries (SDL, Python, MoltenVK, …)"
  "$ROOT/ios/scripts/build_deps.sh"
fi

if [[ ! -x "${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}/makesrna" ]]; then
  echo "note: Building macOS host codegen tools"
  "$ROOT/ios/scripts/build_host_tools.sh"
fi

if [[ ! -d "$ROOT/ios/BlenderMobile/Runtime/blender/5.2/scripts" ]]; then
  echo "note: Packing Blender scripts and datafiles"
  "$ROOT/ios/scripts/package_runtime.sh"
fi

if [[ ! -f "${BUILD_IOS:-$ROOT/build_ios}/CMakeCache.txt" ]]; then
  echo "note: Configuring libblender"
  "$ROOT/ios/scripts/configure_blender.sh"
fi

echo "note: Compiling libblender.dylib"
"$ROOT/ios/scripts/build_native.sh"
"$ROOT/ios/scripts/stage_native.sh"

if [[ ! -f "$ROOT/ios/Vendor/libblender.dylib" ]]; then
  echo "error: libblender.dylib was not produced" >&2
  exit 1
fi

echo "note: Full Blender UI is ready for the app target"
