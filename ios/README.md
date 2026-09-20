# Blender iOS (Developer Mode)

Xcode builds the **full Blender editor** (3D view, areas, outliner, file browser, Cycles CPU) with SDL3 + MoltenVK. The app target is the signed iPhone process; the `libblender` target inside the same project compiles the editor.

You **cannot** compile this on Windows.

## Product → Run (Mac)

```bash
git clone https://github.com/GoodBear01/blender-mobile.git
cd blender-mobile
```

1. Open `ios/BlenderMobile.xcodeproj`
2. Signing & Capabilities → **Team**
3. Product → Destination → your iPhone
4. Product → Run

Xcode first runs **Compile libblender** (libraries + `libblender.dylib` + scripts), then signs the app and installs it. The first Run can take **hours**. Watch the Report navigator for that phase. Later Runs only rebuild what changed.

If the build says **failed with nonzero exit code**, open the Report navigator → BlenderMobile → Compile libblender. The real error is in that log (often missing `cmake`/`ninja`, or a library download). Then Product → Run again.

Install cmake and ninja on the Mac first (`brew install cmake ninja`). Also: `brew install molten-vk` if the MoltenVK download fails.

On the iPhone: Settings → Privacy & Security → Developer Mode → On, then trust the developer.

When it finishes you should get the real Blender UI, not a placeholder screen.

## Terminal (same build)

```bash
chmod +x ios/scripts/*.sh
TEAM=ABCDE12345 ./ios/scripts/build_full_app.sh
```

## Phone use

Same as Android: landscape, touch as mouse, Files → On My iPhone → Blender, mobile UI scale.

## What stays on Windows

`android/package_apk.ps1` and the Samsung/Pixel APK path are unchanged.
