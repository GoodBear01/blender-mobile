#!/usr/bin/env bash
# Copy Blender scripts/datafiles/python into the iOS app bundle resources.
set -euo pipefail

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
export ROOT
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

STDLIB=""
for cand in \
    "$PY_LIB/lib/python3.13" \
    "$PY_LIB/Python.xcframework/lib/python3.13" \
    "$ROOT/ios/.deps/python-apple-support/Python.xcframework/lib/python3.13"; do
  if [[ -f "$cand/encodings/__init__.py" ]]; then
    STDLIB="$cand"
    break
  fi
done
if [[ -z "$STDLIB" ]]; then
  STDLIB="$(find "$PY_LIB" "$ROOT/ios/.deps/python-apple-support" \
    -path '*/python3.13/encodings/__init__.py' -not -path '*simulator*' -print -quit 2>/dev/null || true)"
  if [[ -n "$STDLIB" ]]; then
    STDLIB="$(dirname "$(dirname "$STDLIB")")"
  fi
fi
if [[ -n "$STDLIB" ]]; then
  echo "Blender iOS: Python stdlib from $STDLIB"
  mkdir -p "$DEST/python/lib"
  rsync -a "$STDLIB/" "$DEST/python/lib/python3.13/"
else
  echo "Blender iOS: Python stdlib with encodings was not found" >&2
fi
echo "5.2.0-ios-full2" >"$ROOT/ios/BlenderMobile/Runtime/runtime_version.txt"
echo "Packed runtime into $DEST"
