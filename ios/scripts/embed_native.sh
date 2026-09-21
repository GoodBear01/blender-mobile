#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
DEST="${BUILT_PRODUCTS_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
RES="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"

mkdir -p "$DEST" "$RES"

if [[ ! -f "$VENDOR/libblender.dylib" && "${STUB:-}" != "1" ]]; then
  echo "Blender iOS: libblender.dylib is not staged yet. Compiling it now."
  WORK="${DERIVED_FILE_DIR:-/tmp}/blender-compile"
  mkdir -p "$WORK"
  /usr/bin/tr -d '\r' < "$ROOT/scripts/xcode_build_blender.sh" > "$WORK/xcode_build_blender.sh"
  /bin/bash "$WORK/xcode_build_blender.sh"
fi

if [[ ! -f "$VENDOR/libblender.dylib" && "${STUB:-}" != "1" ]]; then
  echo "error: libblender.dylib is still missing after compile." >&2
  echo "error: Open Report navigator → Compile libblender." >&2
  exit 1
fi

/bin/bash "$ROOT/scripts/fix_python_rpaths.sh" "$VENDOR"

if [[ -d "$VENDOR" ]]; then
  for f in "$VENDOR"/*.dylib; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "$DEST/"
  done
  rm -rf "$DEST/MoltenVK.framework" "$DEST/Python.framework"
  for f in "$VENDOR"/*.framework; do
    [[ -d "$f" ]] || continue
    case "$(basename "$f")" in
      MoltenVK.framework|Python.framework) continue ;;
    esac
    rsync -a "$f" "$DEST/"
  done
  rm -rf "$DEST/MoltenVK.framework" "$DEST/Python.framework"
fi

/bin/bash "$ROOT/scripts/fix_python_rpaths.sh" "$DEST"

if [[ -d "$VENDOR" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
  for f in "$DEST"/*.dylib; do
    [[ -f "$f" ]] || continue
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$f" || true
  done
  for fw in "$DEST"/*.framework; do
    [[ -d "$fw" ]] || continue
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$fw" || true
  done
fi

if [[ -d "$VENDOR/Runtime" ]]; then
  rsync -a "$VENDOR/Runtime" "$RES/"
elif [[ -d "$ROOT/BlenderMobile/Runtime/blender" ]]; then
  rsync -a "$ROOT/BlenderMobile/Runtime" "$RES/"
fi
