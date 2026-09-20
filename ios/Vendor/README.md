This folder is filled on a Mac by the Xcode `libblender` target (`ios/scripts/xcode_build_blender.sh` → `stage_native.sh`).

It receives `libblender.dylib`, SDL3, MoltenVK, Python, and `Native.xcconfig`.
The app target embeds these and launches the full Blender UI.
