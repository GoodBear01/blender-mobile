#!/usr/bin/env bash
# Build and install BlenderMobile from the terminal. Does not open the Xcode GUI.
# Still needs Xcode.app installed (for the iOS SDK) and an Apple ID team.
#
# First time on this Mac (one-time):
#   Xcode → Settings → Accounts → add your Apple ID
#   Then copy the 10-character Team ID from that account.
#
# Usage:
#   TEAM=ABCDE12345 ./ios/scripts/install_device.sh
#   TEAM=ABCDE12345 BUNDLE_ID=org.blender.experimental.ios ./ios/scripts/install_device.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ="$ROOT/ios/BlenderMobile.xcodeproj"
DERIVED="$ROOT/ios/build"
BUNDLE_ID="${BUNDLE_ID:-org.blender.experimental.ios}"

if [[ -z "${TEAM:-}" ]]; then
  echo "Set TEAM to your 10-character Apple Team ID, for example:" >&2
  echo "  TEAM=ABCDE12345 $0" >&2
  echo "Find it in Xcode → Settings → Accounts → your Apple ID → Team ID" >&2
  echo "or:  security find-identity -p codesigning -v" >&2
  exit 1
fi

if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "iOS SDK not found. Install Xcode from the App Store, then:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

echo "== devices =="
xcrun devicectl list devices || true
xcrun xctrace list devices 2>/dev/null || true

if [[ ! -f "$ROOT/ios/Vendor/libblender.dylib" ]]; then
  FOUND="$(find "$ROOT/build_ios" -name 'libblender.dylib' -print -quit 2>/dev/null || true)"
  if [[ -n "$FOUND" ]]; then
    "$ROOT/ios/scripts/stage_native.sh"
  fi
fi
if [[ ! -f "$ROOT/ios/Vendor/libblender.dylib" && "${STUB:-}" != "1" ]]; then
  echo "libblender.dylib is missing, so Xcode would install the placeholder screen." >&2
  echo "The full UI is not in GitHub. Compile it on this Mac:" >&2
  echo "  TEAM=$TEAM ./ios/scripts/build_full_app.sh" >&2
  echo "To force the placeholder anyway: STUB=1 TEAM=$TEAM $0" >&2
  exit 1
fi
echo "== building the iOS app with the full editor library =="
xcodebuild \
  -project "$PROJ" \
  -scheme BlenderMobile \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=YES

APP=$(find "$DERIVED/Build/Products" -name "BlenderMobile.app" -print -quit)
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "Build finished but BlenderMobile.app was not found under $DERIVED" >&2
  exit 1
fi
echo "App: $APP"
if [[ ! -f "$APP/Frameworks/libblender.dylib" && -f "$ROOT/ios/Vendor/libblender.dylib" ]]; then
  mkdir -p "$APP/Frameworks"
  cp -f "$ROOT/ios/Vendor/"*.dylib "$APP/Frameworks/" 2>/dev/null || true
fi
if [[ ! -f "$APP/Frameworks/libblender.dylib" && "${STUB:-}" != "1" ]]; then
  echo "The .app still has no libblender.dylib, so the phone would show the placeholder." >&2
  echo "Run: TEAM=$TEAM ./ios/scripts/build_full_app.sh" >&2
  exit 1
fi

DEVICE="${DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/available/ && /iPhone|iPad/ {print $NF; exit}')
fi
if [[ -z "$DEVICE" ]]; then
  echo "Plug in the iPhone, tap Trust, enable Developer Mode, then re-run." >&2
  echo "Or set DEVICE=<udid> from: xcrun devicectl list devices" >&2
  exit 1
fi

echo "== installing onto $DEVICE =="
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "== launching $BUNDLE_ID =="
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || true

echo "If the icon is gray: Settings → General → VPN & Device Management → trust this developer."
echo "Free Apple ID builds expire in 7 days. Re-run this script to refresh."
