#!/usr/bin/env bash
# Copy Blender scripts/datafiles/python into the iOS app bundle resources.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/ios/BlenderMobile/Runtime/blender/5.2"
SRC_SCRIPTS="$ROOT/blender-5.2.0/scripts"
SRC_DATA="$ROOT/blender-5.2.0/release/datafiles"
PY_LIB="$ROOT/blender-5.2.0/lib/ios_arm64/python"

rm -rf "$DEST"
mkdir -p "$DEST/scripts" "$DEST/datafiles"
rsync -a --exclude '__pycache__' --exclude '*.pyc' "$SRC_SCRIPTS/" "$DEST/scripts/"
if [[ -d "$SRC_DATA" ]]; then
  rsync -a --exclude '*.blend1' "$SRC_DATA/" "$DEST/datafiles/"
fi
if [[ -d "$PY_LIB/lib/python3.13" ]]; then
  mkdir -p "$DEST/python/lib"
  rsync -a "$PY_LIB/lib/python3.13" "$DEST/python/lib/"
fi
echo "5.2.0-ios-full1" >"$ROOT/ios/BlenderMobile/Runtime/runtime_version.txt"
echo "Packed runtime into $DEST"
