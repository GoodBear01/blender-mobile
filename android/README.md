# Blender 5.2 experimental Android APK

Unofficial `arm64-v8a` port of this tree. It is the desktop UI on a Vulkan window (touch mapped as a mouse), not an official Blender Foundation product.

## What you need

- Windows PC (this workspace)
- A 64-bit Samsung phone with Vulkan 1.2 and Android 10+ (Galaxy S20-class or newer is the safe assumption)
- USB cable
- Several tens of GB free disk and a few hours for the first native compile

The helper scripts download a JDK, Android NDK r27, CMake, and Gradle into `android/.tools` and your existing SDK at `%LOCALAPPDATA%\Android\Sdk`.

## Build and sideload

From PowerShell:

```powershell
cd android
Set-ExecutionPolicy -Scope Process Bypass
.\build_apk.ps1
```

That will:

1. Install NDK / CMake / JDK if missing
2. Cross-compile lite Android libraries into `blender-5.2.0/lib/android_arm64`
3. Configure and build `libblender.so` with SDL3 + Vulkan
4. Pack scripts, datafiles, and CPython into the APK
5. Produce `app/build/outputs/apk/debug/app-debug.apk`
6. Run `adb install -r` if a device is connected

If `libblender.so` is already built, package only:

```powershell
.\package_apk.ps1
```

The debug APK is written to:

`android/app/build/outputs/apk/debug/app-debug.apk`

To build the APK without installing:

```powershell
.\build_apk.ps1 -SkipInstall
```

If dependencies are already built:

```powershell
.\build_apk.ps1 -SkipDeps
```

## Phone setup (Samsung)

1. Settings → About phone → Software information → tap **Build number** seven times
2. Settings → Developer options → enable **USB debugging**
3. Plug in the USB cable and allow this computer
4. Settings → allow install from this computer / unknown apps if prompted
5. After install, launch **Blender 5.2**

First launch unpacks scripts into the app sandbox and can take a minute.

## Layout on the device

| Env var | Location |
| --- | --- |
| `BLENDER_SYSTEM` | `files/blender` (contains `5.2/scripts`, `5.2/datafiles`, `5.2/python`) |
| `HOME` | `files/home` |
| `BLENDER_USER_CONFIG` | `files/config/blender/5.2` |

Open/save uses the app sandbox. Downloads is exposed as `/sdcard/Download` when storage permission is granted.

## Known limits of this first APK

- Desktop-sized UI on a phone screen (an S Pen helps)
- No Cycles GPU, USD, OpenVDB, or FFmpeg
- Requires Android 10 (API 29) or newer
- Debug / sideload only — not a Play Store release

GPL-3 still applies if you redistribute the APK.
