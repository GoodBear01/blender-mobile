#!/usr/bin/env bash
# BeeWare libpython uses install name @rpath/Python.framework/Python. Either
# rewrite load commands to libpython3.13.dylib or ship that framework path.
set -euo pipefail

if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
IOS_ROOT="${IOS_ROOT:-$ROOT/ios}"
LIBDIR="${LIBDIR:-$ROOT/blender-5.2.0/lib/ios_arm64}"
VENDOR="${IOS_VENDOR:-$IOS_ROOT/Vendor}"
BUILD="${BUILD_IOS:-$ROOT/build_ios}"

canonical_staged_name() {
  local base="$1"
  case "$base" in
    *Python.framework*) echo "PYTHON_FW"; return ;;
    libSDL3*.dylib) echo "libSDL3.dylib"; return ;;
    libtbb*.dylib) echo "libtbb.dylib"; return ;;
    libpython3.13*.dylib) echo "libpython3.13.dylib"; return ;;
    libMoltenVK.dylib|MoltenVK) echo "MOLTENVK_STATIC"; return ;;
  esac
  echo "$base"
}

find_ios_dylib_source() {
  local name="$1"
  local cand
  for cand in \
    "$VENDOR/$name" \
    "$LIBDIR/sdl/lib/$name" \
    "$LIBDIR/python/lib/$name" \
    "$LIBDIR/tbb/lib/$name"; do
    if [[ -f "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  while IFS= read -r cand; do
    [[ -f "$cand" ]] || continue
    echo "$cand"
    return 0
  done < <(find "$LIBDIR" "$BUILD" -name "$name" -type f 2>/dev/null | head -n 20)
  return 1
}

stage_named_dylib() {
  local dir="$1" name="$2" src="$3"
  cp -f "$src" "$dir/$name"
  chmod u+w "$dir/$name"
  install_name_tool -id "@rpath/$name" "$dir/$name" || true
}

resolve_rpath_deps() {
  local dir="$1"
  local lib="$dir/libblender.dylib"
  local dep base canonical src
  [[ -f "$lib" ]] || return 0
  chmod u+w "$lib" || true
  while IFS= read -r dep; do
    dep="${dep%% (*}"
    dep="$(printf '%s' "$dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$dep" in
      ""|/usr/lib/*|/System/*|@rpath/libblender.dylib) continue ;;
      @rpath/*) ;;
      *) continue ;;
    esac
    base="${dep#@rpath/}"
    canonical="$(canonical_staged_name "$base")"
    if [[ "$canonical" == "PYTHON_FW" ]]; then
      continue
    fi
    if [[ "$canonical" == "MOLTENVK_STATIC" ]]; then
      install_name_tool -change "$dep" "@rpath/libblender.dylib" "$lib" 2>/dev/null || true
      continue
    fi
    if [[ ! -f "$dir/$canonical" ]]; then
      src="$(find_ios_dylib_source "$canonical" || true)"
      if [[ -z "$src" && "$canonical" == "libSDL3.dylib" ]]; then
        src="$(find_ios_dylib_source "libSDL3.0.dylib" || true)"
      fi
      if [[ -n "$src" ]]; then
        stage_named_dylib "$dir" "$canonical" "$src"
        echo "Blender iOS: staged $canonical from $src"
      fi
    fi
    if [[ -f "$dir/$canonical" && "$dep" != "@rpath/$canonical" ]]; then
      install_name_tool -change "$dep" "@rpath/$canonical" "$lib" 2>/dev/null || true
    fi
  done < <(otool -L "$lib" 2>/dev/null | tail -n +2)
}

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

stage_python_framework() {
  local dir="$1"
  local libpy="$dir/libpython3.13.dylib"
  local fw="$dir/Python.framework"
  local fwbin="$fw/Python"
  [[ -f "$libpy" ]] || return 1
  rm -rf "$fw"
  mkdir -p "$fw"
  cp -f "$libpy" "$fwbin"
  chmod u+w "$fwbin"
  install_name_tool -id "@rpath/Python.framework/Python" "$fwbin"
  cat >"$fw/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Python</string>
  <key>CFBundleIdentifier</key>
  <string>org.python.python</string>
  <key>CFBundleName</key>
  <string>Python</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>3.13</string>
  <key>CFBundleVersion</key>
  <string>3.13</string>
</dict>
</plist>
PLIST
  echo "Blender iOS: staged Python.framework/Python in $dir"
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
    if [[ "$dep" != *Python.framework* ]]; then
      continue
    fi
    if [[ ! -f "$dir/libpython3.13.dylib" ]]; then
      echo "Blender iOS: need libpython in $dir before fixing $(basename "$lib")" >&2
      return 1
    fi
    echo "Blender iOS: install_name_tool -change '$dep' @rpath/libpython3.13.dylib $(basename "$lib")"
    if ! install_name_tool -change "$dep" "@rpath/libpython3.13.dylib" "$lib" 2>/dev/null; then
      echo "Blender iOS: could not change '$dep' in $(basename "$lib") (will use Python.framework stub)" >&2
    fi
  done < <(otool -L "$lib" 2>/dev/null | tail -n +2)
}

audit_rpath_libs() {
  local dir="$1"
  local lib dep base missing=0
  [[ -f "$dir/libblender.dylib" ]] || return 0
  while IFS= read -r dep; do
    dep="${dep%% (*}"
    dep="$(printf '%s' "$dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$dep" in
      ""|/usr/lib/*|/System/*|@rpath/libblender.dylib) continue ;;
      @rpath/*)
        base="${dep#@rpath/}"
        canonical="$(canonical_staged_name "$base")"
        if [[ "$canonical" == "PYTHON_FW" ]]; then
          if [[ ! -f "$dir/Python.framework/Python" ]]; then
            echo "Blender iOS: missing Python.framework/Python in $dir" >&2
            missing=1
          fi
          continue
        fi
        if [[ "$canonical" == "MOLTENVK_STATIC" || "$canonical" == "libblender.dylib" ]]; then
          continue
        fi
        if [[ ! -f "$dir/$canonical" ]]; then
          echo "Blender iOS: libblender needs missing @rpath/$canonical (from $dep) in $dir" >&2
          missing=1
        fi
        ;;
    esac
  done < <(otool -L "$dir/libblender.dylib" | tail -n +2)
  return "$missing"
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
  resolve_rpath_deps "$dir"
  stage_python_framework "$dir" || true
  if ! audit_rpath_libs "$dir"; then
    echo "error: libblender.dylib has unsatisfied @rpath dependencies in $dir" >&2
    otool -L "$dir/libblender.dylib" >&2 || true
    exit 1
  fi
done
