#!/usr/bin/env bash
set -euo pipefail

# Xcode copies this script into DerivedData. Do not derive paths from $0.
if [[ -n "${SRCROOT:-}" && -d "${SRCROOT}/scripts" ]]; then
  IOS_ROOT="$SRCROOT"
else
  IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
if [[ ! -f "$IOS_ROOT/scripts/xcode_build_blender.sh" ]]; then
  echo "error: ios scripts not found under $IOS_ROOT" >&2
  echo "error: Open ios/BlenderMobile.xcodeproj from the cloned repo." >&2
  exit 1
fi
export ROOT="$(cd "$IOS_ROOT/.." && pwd)"
export IOS_ROOT IOS_VENDOR="$IOS_ROOT/Vendor"
VENDOR="$IOS_VENDOR"
mkdir -p "$VENDOR"
DEST="${BUILT_PRODUCTS_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
RES="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"

mkdir -p "$DEST" "$RES"

if [[ ! -f "$VENDOR/libblender.dylib" && "${STUB:-}" != "1" ]]; then
  echo "Blender iOS: libblender.dylib is not staged yet. Compiling it now."
  WORK="${DERIVED_FILE_DIR:-/tmp}/blender-compile"
  mkdir -p "$WORK"
  /usr/bin/tr -d '\r' < "$IOS_ROOT/scripts/xcode_build_blender.sh" > "$WORK/xcode_build_blender.sh"
  export SRCROOT="$IOS_ROOT"
  /bin/bash "$WORK/xcode_build_blender.sh"
fi

if [[ ! -f "$VENDOR/libblender.dylib" && "${STUB:-}" != "1" ]]; then
  echo "error: libblender.dylib is still missing after compile." >&2
  echo "error: expected $VENDOR/libblender.dylib" >&2
  echo "error: Open Report navigator → Compile libblender, or see ~/Library/Logs/blender-ios-xcode.log" >&2
  exit 1
fi

/bin/bash "$IOS_ROOT/scripts/fix_python_rpaths.sh" "$VENDOR"

if [[ -d "$VENDOR" ]]; then
  for f in "$VENDOR"/*.dylib; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "$DEST/"
  done
  rm -rf "$DEST/MoltenVK.framework"
  for f in "$VENDOR"/*.framework; do
    [[ -d "$f" ]] || continue
    case "$(basename "$f")" in
      MoltenVK.framework|Python.framework) continue ;;
    esac
    rsync -a "$f" "$DEST/"
  done
  rm -rf "$DEST/MoltenVK.framework"
fi

/bin/bash "$IOS_ROOT/scripts/fix_python_rpaths.sh" "$DEST"

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
elif [[ -d "$IOS_ROOT/BlenderMobile/Runtime/blender" ]]; then
  rsync -a "$IOS_ROOT/BlenderMobile/Runtime" "$RES/"
fi
