# Shared by the Xcode libblender compile. Safe to source. bash 3.2 compatible.

if [ -z "${ROOT:-}" ]; then
  if [ -n "${SRCROOT:-}" ]; then
    ROOT="$(cd "${SRCROOT}/.." && pwd)"
  else
    ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  fi
fi
export ROOT

if [ -z "${IOS_SCRIPTS:-}" ]; then
  IOS_SCRIPTS="$ROOT/ios/scripts"
fi
export IOS_SCRIPTS

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/homebrew/opt/cmake/bin:/opt/homebrew/opt/ninja/bin:/Applications/CMake.app/Contents/bin:/opt/local/bin:/usr/bin:/bin:${PATH:-}"

# Xcode may mark some of these; never abort on unset.
unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET 2>/dev/null || true
unset WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET 2>/dev/null || true
unset CFLAGS CXXFLAGS CC CXX LD LDFLAGS CPPFLAGS CPATH LIBRARY_PATH 2>/dev/null || true
unset CMAKE_OSX_SYSROOT CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET 2>/dev/null || true
unset CMAKE_C_COMPILER CMAKE_CXX_COMPILER CMAKE_C_FLAGS CMAKE_CXX_FLAGS 2>/dev/null || true
unset ARCHS VALID_ARCHS EFFECTIVE_PLATFORM_NAME PLATFORM_NAME 2>/dev/null || true
unset SUPPORTED_PLATFORMS TARGETED_DEVICE_FAMILY CURRENT_ARCH 2>/dev/null || true
unset OTHER_CFLAGS OTHER_CPLUSPLUSFLAGS OTHER_LDFLAGS OTHER_C_FLAGS 2>/dev/null || true
unset GCC_PREPROCESSOR_DEFINITIONS IPHONEOS_DEPLOYMENT_TARGET_FOR_CC 2>/dev/null || true

ios_tools_dir() {
  if [ -n "${BLENDER_IOS_TOOLS:-}" ]; then
    echo "$BLENDER_IOS_TOOLS"
    return
  fi
  if mkdir -p "$ROOT/ios/.tools" 2>/dev/null && : > "$ROOT/ios/.tools/.writable" 2>/dev/null; then
    echo "$ROOT/ios/.tools"
    return
  fi
  mkdir -p "$HOME/Library/Caches/blender-ios-tools" 2>/dev/null || true
  echo "$HOME/Library/Caches/blender-ios-tools"
}

ensure_cmake_ninja() {
  TOOLS="$(ios_tools_dir)"
  mkdir -p "$TOOLS/bin"
  export PATH="$TOOLS/bin:$PATH"

  if command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    echo "note: Installing cmake and ninja with Homebrew"
    brew install cmake ninja </dev/null || true
  fi

  if command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    return 0
  fi

  CMAKE_VER="3.31.6"
  CMAKE_APP="$TOOLS/cmake-${CMAKE_VER}-macos-universal/CMake.app/Contents/bin/cmake"
  if [ ! -x "$CMAKE_APP" ] && ! command -v cmake >/dev/null 2>&1; then
    echo "note: Downloading CMake ${CMAKE_VER} (not in PATH)"
    curl -L --fail --retry 3 -o "$TOOLS/cmake.tar.gz" \
      "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-macos-universal.tar.gz"
    tar -xzf "$TOOLS/cmake.tar.gz" -C "$TOOLS"
  fi
  if [ -x "$CMAKE_APP" ]; then
    ln -sf "$CMAKE_APP" "$TOOLS/bin/cmake"
  fi

  if [ ! -x "$TOOLS/bin/ninja" ] && ! command -v ninja >/dev/null 2>&1; then
    echo "note: Downloading Ninja"
    curl -L --fail --retry 3 -o "$TOOLS/ninja-mac.zip" \
      "https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-mac.zip"
    mkdir -p "$TOOLS/ninja-extract"
    /usr/bin/unzip -o "$TOOLS/ninja-mac.zip" -d "$TOOLS/ninja-extract"
    if [ -f "$TOOLS/ninja-extract/ninja" ]; then
      chmod +x "$TOOLS/ninja-extract/ninja"
      ln -sf "$TOOLS/ninja-extract/ninja" "$TOOLS/bin/ninja"
    fi
  fi

  export PATH="$TOOLS/bin:$PATH"

  if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
    echo "error: cmake or ninja still missing after download." >&2
    echo "error: cmake=$(command -v cmake) ninja=$(command -v ninja)" >&2
    echo "error: In Terminal: brew install cmake ninja" >&2
    return 1
  fi
}
