# Blender iOS (Developer Mode)

Separate iPhone/iPad app. The Android APK is unchanged and is still built from `android/` on Windows.

You **cannot** compile or sign this on Windows. Copy this repo to a Mac with Xcode, then install over USB after enabling Developer Mode.

This first Xcode target is a landscape stub so you can prove the install path the same day. Full Blender loads only after you build `lib/ios_arm64` and `libblender` on that Mac.

## If Xcode shows a wall of errors

Open **only** this project:

`ios/BlenderMobile.xcodeproj`

Do **not** open `blender-5.2.0/` in Xcode and do **not** run `configure_blender.sh` yet. Those paths compile the full editor and need iOS libraries that are not in the GitHub clone. CMake then prints dozens of `Could NOT find ...` errors.

In the stub project:

1. Select the **BlenderMobile** target (not the blender-5.2.0 folder)
2. Signing & Capabilities → **Team** → your Apple ID
3. Product → Destination → your iPhone
4. Product → Run

A signing error about Team is one red issue, not a compile flood. Pick a Team and it goes away.

After `git pull`, if Xcode still shows old errors or the icon immediately closes: Product → Clean Build Folder, delete the app from the iPhone, then Run again.

## Install the stub today

Developer Mode only lets the phone accept a **signed** build. It is not Android `adb install`. You still need Xcode’s iOS SDK on a Mac to compile. You do not have to open the Xcode window.

On the iPhone (iOS 16+):

1. Settings → Privacy & Security → Developer Mode → On
2. Reboot when asked
3. Plug in USB and tap Trust

### Without opening the Xcode window (Mac Terminal)

Do this **once** so the Mac has a signing identity: Xcode → Settings → Accounts → add your Apple ID. Copy the 10-character **Team ID**. After that, close Xcode.

```bash
git pull
chmod +x ios/scripts/*.sh
TEAM=ABCDE12345 ./ios/scripts/install_device.sh
```

That runs `xcodebuild` and `devicectl` (no GUI). First launch: Settings → General → VPN & Device Management → trust this developer.

### From Windows

You cannot compile this project on Windows. Options:

1. Copy the repo to a Mac and run the command above.
2. If you already have a signed `.ipa` from that Mac, Sideloadly (Windows) can push it over USB with the same Apple ID. There is no `.ipa` in this repo until you build one.

### Xcode GUI (optional)

1. Open `ios/BlenderMobile.xcodeproj`
2. Signing & Capabilities → **Team**
3. Product → Run onto the iPhone

The stub shows the Blender name, an **Import .blend** button (Files / document picker), and writes into On My iPhone → Blender. If the icon opens then immediately closes, pull this repo again — an earlier stub overwrote `HOME` and only allowed landscape, which makes iOS kill the process on launch.

Free Apple ID builds expire in **7 days**. Re-run from Xcode to refresh. Paid Apple Developer lasts a year. App Store is out of scope.

## After the stub runs: libraries and Blender

Android `lib/android_arm64` binaries will not link on iOS.

On the Mac, from the repo root:

```bash
chmod +x ios/scripts/*.sh
./ios/scripts/build_deps.sh
./ios/scripts/package_runtime.sh
./ios/scripts/configure_blender.sh
./ios/scripts/build_native.sh
```

`build_deps.sh` uses the same lite set as Android (SDL3, zlib, png, Vulkan headers, MoltenVK, Python, …) and installs into `blender-5.2.0/lib/ios_arm64`.

Then add `libblender`, SDL3, and MoltenVK to the app target (Embed & Sign), add `-DBLENDER_IOS_HAS_NATIVE` to Other C Flags, copy `ios/BlenderMobile/Runtime` into the bundle, and run `TEAM=... ./ios/scripts/install_device.sh` again.

`main` stays in the app. When `BLENDER_IOS_HAS_NATIVE` is set, the process starts Blender (SDL + MoltenVK) instead of the stub screen.

## Graphics and files

- Vulkan via **MoltenVK** (not Android `libvulkan.so`, not macOS Cocoa Metal)
- Phone UI is shared: set `BLENDER_IOS=1` and `BLENDER_MOBILE=1` (the host does this)
- Files live in the app Documents folder; use **Import .blend** or Files. There is no `MANAGE_EXTERNAL_STORAGE`

## What stays on Windows

`android/package_apk.ps1` and the Samsung/Pixel APK path are unchanged.
