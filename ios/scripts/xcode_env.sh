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

unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET
unset WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET
unset CFLAGS CXXFLAGS CC CXX LD LDFLAGS CPPFLAGS CPATH LIBRARY_PATH
unset CMAKE_OSX_SYSROOT CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET
unset CMAKE_C_COMPILER CMAKE_CXX_COMPILER CMAKE_C_FLAGS CMAKE_CXX_FLAGS
unset ARCHS VALID_ARCHS EFFECTIVE_PLATFORM_NAME PLATFORM_NAME
unset SUPPORTED_PLATFORMS TARGETED_DEVICE_FAMILY CURRENT_ARCH
unset OTHER_CFLAGS OTHER_CPLUSPLUSFLAGS OTHER_LDFLAGS OTHER_C_FLAGS
unset GCC_PREPROCESSOR_DEFINITIONS
unset IPHONEOS_DEPLOYMENT_TARGET_FOR_CC

ensure_cmake_ninja() {
  if command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    echo "note: Installing cmake and ninja with Homebrew"
    brew install cmake ninja </dev/null || true
  fi
  if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
    echo "error: cmake and ninja are missing." >&2
    echo "error: In Terminal: brew install cmake ninja" >&2
    return 1
  fi
}
