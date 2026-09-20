This folder is filled on a Mac by `ios/scripts/stage_native.sh`.

It receives `libblender.dylib`, SDL3, MoltenVK, Python, and `Native.xcconfig`.
Xcode includes `Native.xcconfig` when it exists so the app launches the full Blender UI.
