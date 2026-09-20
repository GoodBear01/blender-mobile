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

Open **only** `ios/BlenderMobile.xcodeproj`. Opening `blender-5.2.0/` in Xcode compiles the desktop editor and will dump a wall of missing-library errors.

```bash
git clone https://github.com/GoodBear01/blender-mobile.git
cd blender-mobile
chmod +x ios/scripts/*.sh
TEAM=YOUR_TEAM_ID ./ios/scripts/install_device.sh
```

## Trademark

Blender and the Blender logo are trademarks of the Blender Foundation. This port does not claim official status or endorsement.
