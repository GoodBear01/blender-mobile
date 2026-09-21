#!/usr/bin/env bash
# Rewrite BeeWare Python.framework load commands to @rpath/libpython3.13.dylib.
set -euo pipefail

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
LIBDIR="${LIBDIR:-$ROOT/blender-5.2.0/lib/ios_arm64}"
VENDOR="$ROOT/ios/Vendor"

ensure_libpython_in() {
  local dir="$1"
  local dst="$dir/libpython3.13.dylib"
  if [[ -f "$dst" ]]; then
    return 0
  fi
  local src=""
  if [[ -f "$VENDOR/libpython3.13.dylib" ]]; then
    src="$VENDOR/libpython3.13.dylib"
  elif [[ -f "$LIBDIR/python/lib/libpython3.13.dylib" ]]; then
    src="$LIBDIR/python/lib/libpython3.13.dylib"
  fi
  if [[ -z "$src" ]]; then
    echo "Blender iOS: libpython3.13.dylib not found for $dir" >&2
    return 1
  fi
  cp -f "$src" "$dst"
  chmod u+w "$dst"
  install_name_tool -id "@rpath/libpython3.13.dylib" "$dst"
  echo "Blender iOS: staged libpython3.13.dylib into $dir"
}

fix_dylib_python_refs() {
  local lib="$1"
  local dir="$2"
  local dep

  [[ -f "$lib" ]] || return 0
  chmod u+w "$lib" || true
  if [[ "$(basename "$lib")" == "libpython3.13.dylib" ]]; then
    install_name_tool -id "@rpath/libpython3.13.dylib" "$lib" || true
  fi
  while IFS= read -r dep; do
    dep="${dep%% (*}"
    dep="$(printf '%s' "$dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$dep" ]] && continue
    case "$dep" in
      /usr/lib/*|/System/*) continue ;;
    esac
    if [[ "$dep" != *Python.framework* && "$dep" != *Python.framework/Python* ]]; then
      continue
    fi
    if [[ ! -f "$dir/libpython3.13.dylib" ]]; then
      echo "Blender iOS: need libpython in $dir before fixing $(basename "$lib")" >&2
      return 1
    fi
    echo "Blender iOS: install_name_tool -change '$dep' @rpath/libpython3.13.dylib $(basename "$lib")"
    install_name_tool -change "$dep" "@rpath/libpython3.13.dylib" "$lib"
  done < <(otool -L "$lib" 2>/dev/null | tail -n +2)
}

if [[ "$#" -lt 1 ]]; then
  echo "usage: $0 DIR [DIR...]" >&2
  exit 1
fi

for dir in "$@"; do
  [[ -d "$dir" ]] || continue
  ensure_libpython_in "$dir" || true
  shopt -s nullglob
  for lib in "$dir"/*.dylib; do
    fix_dylib_python_refs "$lib" "$dir"
  done
  shopt -u nullglob
  if [[ -f "$dir/libblender.dylib" ]] && otool -L "$dir/libblender.dylib" | grep -q 'Python.framework'; then
    echo "error: libblender.dylib in $dir still loads Python.framework/Python" >&2
    otool -L "$dir/libblender.dylib" >&2
    exit 1
  fi
done
