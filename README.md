# Blender Mobile (unofficial)

Experimental **Android** and **iOS** builds of [Blender 5.2](https://www.blender.org). This is a community port, not an official Blender Foundation product.

The desktop editor runs in a single Vulkan window (MoltenVK on iPhone). Touch is mapped as a mouse. Phone layout, files, and install steps live in this repo.

## License

Blender as a whole is licensed under the **GNU General Public License, Version 3**. This repository is the same: see [LICENSE](LICENSE).

You may copy, change, and share this project under the GPL. If you distribute a build (APK, IPA, or binary), you must also provide the corresponding source.

Official license notes: [blender.org/about/license](https://www.blender.org/about/license)

## What is in this repo

| Path | What it is |
| --- | --- |
| [blender-5.2.0/](blender-5.2.0/) | Blender 5.2 sources used by both phones |
| [android/](android/) | Android APK host, Gradle, and Windows build scripts |
| [ios/](ios/) | Separate Xcode app for Developer Mode install |

Rebuildable caches are **not** on GitHub (`build_android/`, `android/.tools/`, `blender-5.2.0/lib/`, APKs). Build them locally.

## Android (Windows)

See [android/README.md](android/README.md).

```powershell
cd android
Set-ExecutionPolicy -Scope Process Bypass
.\build_apk.ps1
```

## iOS (Mac + Developer Mode)

See [ios/README.md](ios/README.md). Compile and sign on a Mac. Developer Mode does not replace signing.

The iOS app is the **full Blender editor** (SDL3 + MoltenVK). On a Mac open `ios/BlenderMobile.xcodeproj`, pick a Team, and Product → Run. That compiles the `libblender` target first, then installs the app. See [ios/README.md](ios/README.md).

## Trademark

Blender and the Blender logo are trademarks of the Blender Foundation. This port does not claim official status or endorsement.
