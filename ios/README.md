# Blender iOS (Developer Mode)

This is the **full Blender editor** on iPhone/iPad: the same desktop UI as the Android port (areas, 3D viewport, outliner, file browser, Cycles CPU), hosted with SDL3 + MoltenVK.

You **cannot** compile this on Windows. Use a Mac with Xcode.

## Build the full UI (Mac)

```bash
git clone https://github.com/GoodBear01/blender-mobile.git
cd blender-mobile
chmod +x ios/scripts/*.sh
# One-time: Xcode → Settings → Accounts → add your Apple ID, copy Team ID
TEAM=ABCDE12345 ./ios/scripts/build_full_app.sh
```

That script:

1. Downloads lite libraries (SDL3, Python, MoltenVK, zlib, OpenImageIO, …)
2. Builds macOS host tools (`makesrna`, …)
3. Packs `scripts/` and `datafiles/` into the app
4. Cross-compiles `libblender.dylib` for iphoneos arm64
5. Signs and installs over USB

The first run takes a long time (hours) and several GB. Later runs skip finished libraries.

On the iPhone: Settings → Privacy & Security → Developer Mode → On, then trust the developer under VPN & Device Management.

After install you should see the **real Blender UI**, not the “Developer Mode install is working” stub.

## Do not use Product → Run for the editor

Xcode → Product → Run, without `build_full_app.sh` first, is why the phone says it is a stub. The host app cannot invent the Blender UI.

Wait until `build_full_app.sh` finishes, then install. To force the old placeholder: `STUB=1 TEAM=... ./ios/scripts/install_device.sh`.

## Phone use

Same as Android:

- Landscape, single Vulkan window
- Touch mapped as a mouse (pinch orbit, two-finger pan)
- **Import .blend** / Files → On My iPhone → Blender
- UI scale and file browser from the mobile startup scripts

## What stays on Windows

`android/package_apk.ps1` and the Samsung/Pixel APK path are unchanged.
