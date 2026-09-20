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

copy_if "$LIBDIR/sdl/lib/libSDL3.dylib"
copy_if "$LIBDIR/python/lib/libpython3.13.dylib"
copy_if "$LIBDIR/tbb/lib/libtbb.dylib"

if [[ -d "$LIBDIR/moltenvk/MoltenVK.xcframework" ]]; then
  rsync -a "$LIBDIR/moltenvk/MoltenVK.xcframework" "$VENDOR/"
elif [[ -d /opt/homebrew/lib/MoltenVK.xcframework ]]; then
  rsync -a /opt/homebrew/lib/MoltenVK.xcframework "$VENDOR/"
elif [[ -d /usr/local/lib/MoltenVK.xcframework ]]; then
  rsync -a /usr/local/lib/MoltenVK.xcframework "$VENDOR/"
fi

if [[ -d "$LIBDIR/python/Python.framework" ]]; then
  rsync -a "$LIBDIR/python/Python.framework" "$VENDOR/"
fi

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
if [[ -d "$VENDOR/MoltenVK.xcframework" ]]; then
  LDFLAGS+=" -framework MoltenVK"
fi
if [[ -d "$VENDOR/Python.framework" ]]; then
  LDFLAGS+=" -framework Python"
fi

cat >"$VENDOR/Native.xcconfig" <<EOF
OTHER_CFLAGS = \$(inherited) -DBLENDER_IOS_HAS_NATIVE
OTHER_CPLUSPLUSFLAGS = \$(inherited) -DBLENDER_IOS_HAS_NATIVE
LIBRARY_SEARCH_PATHS = \$(inherited) \$(PROJECT_DIR)/Vendor
FRAMEWORK_SEARCH_PATHS = \$(inherited) \$(PROJECT_DIR)/Vendor
OTHER_LDFLAGS = \$(inherited) $LDFLAGS
LD_RUNPATH_SEARCH_PATHS = \$(inherited) @executable_path/Frameworks
EOF

echo "Vendor staged in $VENDOR"
cat "$VENDOR/Native.xcconfig"
