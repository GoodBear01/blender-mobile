#!/usr/bin/env bash
# One-shot Mac build: lite deps + host tools + libblender + runtime + signed phone install.
# Usage:
#   TEAM=ABCDE12345 ./ios/scripts/build_full_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export HOST_TOOLS_DIR="${HOST_TOOLS_DIR:-$ROOT/build_host_tools_macos}"
export BUILD_IOS="${BUILD_IOS:-$ROOT/build_ios}"

echo "==== 1/6 download + iOS libraries ===="
"$ROOT/ios/scripts/build_deps.sh"

echo "==== 2/6 macOS host codegen tools ===="
"$ROOT/ios/scripts/build_host_tools.sh"

echo "==== 3/6 package Blender scripts/datafiles ===="
"$ROOT/ios/scripts/package_runtime.sh"

echo "==== 4/6 configure + compile libblender ===="
"$ROOT/ios/scripts/configure_blender.sh"
"$ROOT/ios/scripts/build_native.sh"

echo "==== 5/6 stage Vendor for Xcode ===="
"$ROOT/ios/scripts/stage_native.sh"

echo "==== 6/6 sign and install ===="
if [[ -z "${TEAM:-}" ]]; then
  echo "Libraries and libblender are ready."
  echo "Set TEAM=YourTeamID and re-run this script, or:"
  echo "  TEAM=ABCDE12345 ./ios/scripts/install_device.sh"
  echo "Or open ios/BlenderMobile.xcodeproj, pick a Team, and Run."
  exit 0
fi
"$ROOT/ios/scripts/install_device.sh"
