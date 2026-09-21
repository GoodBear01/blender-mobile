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
search_stdlib() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  local hit
  hit="$(find "$root" -path '*/python3.13/encodings/__init__.py' -not -path '*simulator*' -print -quit 2>/dev/null || true)"
  if [[ -n "$hit" ]]; then
    dirname "$(dirname "$hit")"
  fi
}
for cand in \
    "$PY_LIB/lib/python3.13" \
    "$PY_LIB/Python.xcframework/lib/python3.13" \
    "$PY_LIB/Python.xcframework/ios-arm64/lib/python3.13" \
    "$ROOT/ios/.deps/python-apple-support/Python.xcframework/lib/python3.13" \
    "$ROOT/ios/.deps/python-apple-support/Python.xcframework/ios-arm64/lib/python3.13"; do
  if [[ -f "$cand/encodings/__init__.py" ]]; then
    STDLIB="$cand"
    break
  fi
done
if [[ -z "$STDLIB" ]]; then
  STDLIB="$(search_stdlib "$PY_LIB")"
fi
if [[ -z "$STDLIB" ]]; then
  STDLIB="$(search_stdlib "$ROOT/ios/.deps")"
fi
if [[ -n "$STDLIB" ]]; then
  echo "Blender iOS: Python stdlib from $STDLIB"
  mkdir -p "$DEST/python/lib"
  rsync -a "$STDLIB/" "$DEST/python/lib/python3.13/"
else
  echo "error: Python stdlib encodings/__init__.py was not found under $PY_LIB or ios/.deps" >&2
  exit 1
fi
echo "5.2.0-ios-full3" >"$ROOT/ios/BlenderMobile/Runtime/runtime_version.txt"
echo "Packed runtime into $DEST"
