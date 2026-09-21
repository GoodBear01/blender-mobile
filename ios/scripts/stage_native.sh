#!/usr/bin/env bash
# Copy libblender + SDL/MoltenVK/Python into ios/Vendor and write Native.xcconfig.
set -euo pipefail

if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi
export ROOT
BUILD="${BUILD_IOS:-$ROOT/build_ios}"
LIBDIR="$ROOT/blender-5.2.0/lib/ios_arm64"
VENDOR="$ROOT/ios/Vendor"
mkdir -p "$VENDOR"

copy_if() {
  local src="$1"
  if [[ -e "$src" ]]; then
    rsync -a "$src" "$VENDOR/"
    echo "staged $(basename "$src")"
  fi
}

LIBBLENDER=""
for cand in "$BUILD/bin/libblender.dylib" "$BUILD/lib/libblender.dylib" \
            "$BUILD/source/creator/libblender.dylib"; do
  if [[ -f "$cand" ]]; then
    LIBBLENDER="$cand"
    break
  fi
done
if [[ -z "$LIBBLENDER" ]]; then
  LIBBLENDER="$(find "$BUILD" -name 'libblender.dylib' -print -quit || true)"
fi
if [[ -z "$LIBBLENDER" || ! -f "$LIBBLENDER" ]]; then
  echo "libblender.dylib not found under $BUILD. Run ios/scripts/build_native.sh" >&2
  exit 1
fi
rsync -a "$LIBBLENDER" "$VENDOR/libblender.dylib"
install_name_tool -id "@rpath/libblender.dylib" "$VENDOR/libblender.dylib" || true

stage_dylib() {
  local name="$1"
  shift
  local src="" cand
  if [[ -f "$VENDOR/$name" ]]; then
    return 0
  fi
  for cand in "$@"; do
    if [[ -f "$cand" ]]; then
      src="$cand"
      break
    fi
  done
  if [[ -z "$src" ]]; then
    src="$(find "$LIBDIR" -name "$name" -o -name "${name%.dylib}.*.dylib" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "$src" && -f "$src" ]]; then
    cp -f "$src" "$VENDOR/$name"
    chmod u+w "$VENDOR/$name" || true
    install_name_tool -id "@rpath/$name" "$VENDOR/$name" || true
    echo "staged $name from $src"
  else
    echo "Blender iOS: $name was not found under $LIBDIR" >&2
  fi
}

stage_dylib libSDL3.dylib \
  "$LIBDIR/sdl/lib/libSDL3.dylib" \
  "$LIBDIR/sdl/lib/libSDL3.0.dylib"
stage_dylib libpython3.13.dylib \
  "$LIBDIR/python/lib/libpython3.13.dylib"
stage_dylib libtbb.dylib \
  "$LIBDIR/tbb/lib/libtbb.dylib" \
  "$LIBDIR/tbb/lib/libtbb.12.dylib"

# Do not ship MoltenVK.framework. dyld abort_with_payloads on that bundle.
rm -rf "$VENDOR/MoltenVK.framework" "$VENDOR/MoltenVK.xcframework"

rewrite_load_commands() {
  local lib="$1"
  local dep base src
  [[ -f "$lib" ]] || return 0
  chmod u+w "$lib" || true
  install_name_tool -id "@rpath/$(basename "$lib")" "$lib" || true
  while IFS= read -r dep; do
    dep="${dep%% (*}"
    dep="$(printf '%s' "$dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$dep" in
      ""|/usr/lib/*|/System/*) continue ;;
    esac
    base="$(basename "$dep")"
    if [[ "$base" == "MoltenVK" || "$dep" == *MoltenVK.framework* ]]; then
      base="libMoltenVK.dylib"
    fi
    src=""
    if [[ -f "$dep" ]]; then
      src="$dep"
    elif [[ -f "$LIBDIR/moltenvk/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK" ]]; then
      src="$LIBDIR/moltenvk/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK"
    fi
    # Only ship Mach-O dylibs. A static archive copied as a .dylib makes dyld abort.
    if [[ -n "$src" ]] && ! otool -hv "$src" 2>/dev/null | grep -q MH_DYLIB; then
      src=""
    fi
    if [[ -n "$src" && ! -f "$VENDOR/$base" ]]; then
      cp -f "$src" "$VENDOR/$base"
      chmod u+w "$VENDOR/$base" || true
      install_name_tool -id "@rpath/$base" "$VENDOR/$base" || true
      echo "staged $base"
    fi
    if [[ -f "$VENDOR/$base" ]]; then
      install_name_tool -change "$dep" "@rpath/$base" "$lib" || true
    fi
  done < <(otool -L "$lib" | tail -n +2)
}

rewrite_load_commands "$VENDOR/libblender.dylib"
for staged in "$VENDOR"/*.dylib; do
  [[ -f "$staged" ]] || continue
  rewrite_load_commands "$staged"
done

if [[ -d "$ROOT/ios/BlenderMobile/Runtime/blender" ]]; then
  rsync -a "$ROOT/ios/BlenderMobile/Runtime" "$VENDOR/Runtime"
fi

LDFLAGS="-lblender -framework Metal -framework QuartzCore -framework CoreGraphics -framework UIKit -framework Foundation -framework GameController -framework AudioToolbox -framework AVFoundation -framework CoreHaptics -framework CoreMotion -framework OpenGLES"
if [[ -f "$VENDOR/libSDL3.dylib" ]]; then
  LDFLAGS+=" -lSDL3"
fi
if [[ -f "$VENDOR/libpython3.13.dylib" ]]; then
  LDFLAGS+=" -lpython3.13"
fi
if [[ -f "$VENDOR/libtbb.dylib" ]]; then
  LDFLAGS+=" -ltbb"
fi
# MoltenVK stays inside libblender or is loaded via @rpath from Frameworks.
# Do not add it to the app link line. A direct -framework/-lMoltenVK is what
# dyld abort_with_payload is tripping on.

echo "Blender iOS: libblender load commands:"
otool -L "$VENDOR/libblender.dylib" || true

# Do not put linker flags here. Xcode reads this file before the script runs,
# so a stale -framework MoltenVK survives into the app and dyld aborts.
rm -f "$VENDOR/Native.xcconfig"
cat >"$VENDOR/Native.xcconfig" <<EOF
// Linker flags live in the Xcode target. This file must not add frameworks.
EOF

echo "Vendor staged in $VENDOR"
cat "$VENDOR/Native.xcconfig"
