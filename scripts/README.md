# Local Flutter Release Build Guide (`build_release.ps1`)

A reusable PowerShell script that replicates the entire GitHub Actions release workflow locally on Windows machines. It automates building, signing, packaging, and verifying Flutter releases for Android and Windows.

---

## 📋 Table of Contents

- [Local Flutter Release Build Guide (`build_release.ps1`)](#local-flutter-release-build-guide-build_releaseps1)
  - [📋 Table of Contents](#-table-of-contents)
  - [Overview](#overview)
  - [Key Features](#key-features)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
  - [Usage Examples](#usage-examples)
    - [1. Full Release Build (Android + Windows)](#1-full-release-build-android--windows)
    - [2. Build from Repository Root](#2-build-from-repository-root)
    - [3. Build from inside any project directory](#3-build-from-inside-any-project-directory)
    - [4. Android-Only Build](#4-android-only-build)
    - [5. Windows-Only Build](#5-windows-only-build)
    - [6. Fast Iteration / Skip Steps](#6-fast-iteration--skip-steps)
  - [Parameter Reference](#parameter-reference)
  - [Generated Output Artifacts](#generated-output-artifacts)
  - [How Auto-Detection Works](#how-auto-detection-works)
    - [1. App Name \& Version](#1-app-name--version)
    - [2. Android Package Name](#2-android-package-name)
    - [3. Windows Binary Name](#3-windows-binary-name)
    - [4. Windows AppId (GUID)](#4-windows-appid-guid)
  - [Troubleshooting \& FAQ](#troubleshooting--faq)
    - [1. `File build_release.ps1 cannot be loaded because running scripts is disabled`](#1-file-build_releaseps1-cannot-be-loaded-because-running-scripts-is-disabled)
    - [2. `ISCC.exe not found`](#2-isccexe-not-found)
    - [3. Android signing failed / `keystore not found`](#3-android-signing-failed--keystore-not-found)
    - [4. Where is the script located?](#4-where-is-the-script-located)

---

## Overview

The script [`build_release.ps1`](file:///D:/GitHub/.github/build_release.ps1) produces the exact same set of release deliverables as `flutter_release.yaml`:

- **Universal Android APK** (`<app>-android.apk`)
- **Split-per-ABI APKs** (`armeabi-v7a`, `arm64-v8a`, `x86_64`)
- **Google Play App Bundle** (`<app>-android.aab`)
- **Native Debug Symbols** (`debug_symbols.zip`)
- **Windows Portable ZIP** (`<app>-windows.zip`)
- **Windows Inno Setup Installer** (`<app>-windows-installer.exe`)
- **Release Notes Markdown** (`release_body.md`)

---

## Key Features

- **Automatic Directory Discovery**: Pass either a repository root (e.g., `D:\GitHub\HisnElmoslem_App`) or the nested Flutter app directory (`hisnelmoslem`). The script automatically resolves `pubspec.yaml`.
- **FVM Detection**: Automatically uses `fvm flutter` when `.fvmrc` or `.fvm` is present. Falls back to system `flutter` otherwise.
- **JDK Auto-Detection**: Finds Android Studio's bundled JBR or local JDKs and configures `JAVA_HOME` automatically.
- **Inno Setup Auto-Install**: Locates `ISCC.exe`, or installs Inno Setup 6 via `winget`/`choco` if missing.
- **Installer Smoke Test**: Runs a silent install (`/VERYSILENT`) into a temporary folder, verifies binary existence, and tests the uninstaller.
- **Metadata Extraction**: Auto-reads version from `pubspec.yaml`, package name from `build.gradle`, and Windows binary name from `CMakeLists.txt`.

---

## Prerequisites

1. **Windows 10 / 11** with PowerShell 5.1 or PowerShell Core 7+.
2. **Flutter SDK** (managed via `fvm` or standard Flutter in PATH).
3. **Android SDK & Keystore**:
   - Ensure `android/key.properties` exists with valid signing configuration.
4. **Visual Studio C++ Desktop Development**: Required for building Windows applications.
5. **PowerShell Execution Policy**:
   If you encounter script execution errors, allow locally created scripts:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
   ```

---

## Quick Start

Run the script directly from PowerShell by providing the project directory and desired output folder:

```powershell
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\quran-bloc\quran" `
  -OutputDir "C:\Users\usr\Desktop\quran_output"
```

---

## Usage Examples

### 1. Full Release Build (Android + Windows)
Builds both Android APKs/AAB and Windows ZIP/Installer:

```powershell
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\quran-bloc\quran" `
  -OutputDir "C:\Users\usr\Desktop\quran_output"
```

### 2. Build from Repository Root
You don't need to specify the inner subfolder; pointing to the parent repo works automatically:

```powershell
# For Hisn El Moslem
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\HisnElmoslem_App" `
  -OutputDir "C:\Users\usr\Desktop\hisnelmoslem_output"

# For Qadaa
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\Qadaa" `
  -OutputDir "C:\Users\usr\Desktop\qadaa_output"
```

### 3. Build from inside any project directory
Navigate directly to your project and run:

```powershell
cd D:\GitHub\quran-bloc\quran
D:\GitHub\.github\build_release.ps1 -OutputDir "C:\Users\usr\Desktop\quran_output"
```

### 4. Android-Only Build
Skips Windows compilation and Inno Setup:

```powershell
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\HisnElmoslem_App" `
  -Platform Android `
  -OutputDir "C:\Users\usr\Desktop\hisnelmoslem_output"
```

### 5. Windows-Only Build
Skips all Android APK and AAB compilation:

```powershell
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\quran-bloc\quran" `
  -Platform Windows `
  -OutputDir "C:\Users\usr\Desktop\quran_output"
```

### 6. Fast Iteration / Skip Steps
You can skip specific steps to speed up build time:

```powershell
# Skip pub get and split APKs, build universal APK only
D:\GitHub\.github\build_release.ps1 `
  -ProjectPath "D:\GitHub\quran-bloc\quran" `
  -Platform Android `
  -SkipPubGet `
  -SkipSplitApk `
  -SkipAppBundle
```

---

## Parameter Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ProjectPath` | String | `"."` | Path to Flutter project directory or parent repository root |
| `-OutputDir` | String | `<ProjectPath>\dist` | Destination folder for all generated artifacts |
| `-Platform` | Set (`All`, `Android`, `Windows`) | `"All"` | Platforms to build |
| `-Flavor` | String | `"prod"` | Android product flavor (set to `""` if project has no flavors) |
| `-PackageName` | String | *(Auto-detected)* | Android package name override (e.g. `com.hassaneltantawy.quran`) |
| `-AppDisplayName` | String | *(Auto-detected)* | Application display name in Windows installer and Start menu |
| `-AppPublisher` | String | `"Hassan Eltantawy"` | Windows installer publisher name |
| `-NoFvm` | Switch | `False` | Force using system `flutter` even if FVM configuration is found |
| `-SkipPubGet` | Switch | `False` | Skip running `flutter pub get` |
| `-SkipWindows` | Switch | `False` | Skip all Windows build and packaging tasks |
| `-SkipAndroid` | Switch | `False` | Skip all Android build and packaging tasks |
| `-SkipUniversalApk` | Switch | `False` | Skip building the universal Android APK |
| `-SkipSplitApk` | Switch | `False` | Skip building split-per-ABI APKs |
| `-SkipAppBundle` | Switch | `False` | Skip building the `.aab` app bundle |
| `-SkipWindowsZip` | Switch | `False` | Skip packaging the standalone `.zip` archive |
| `-SkipWindowsInstaller` | Switch | `False` | Skip compiling the Inno Setup installer |
| `-SkipTestInstaller` | Switch | `False` | Skip the silent install/uninstall smoke test |
| `-SkipDebugSymbols` | Switch | `False` | Skip zipping native debug symbols |

---

## Generated Output Artifacts

When `-Platform All` is run, the output directory will contain:

| File Name | Description | Purpose |
|---|---|---|
| `<app>-android.apk` | Universal Android APK | Sideloading on any Android device |
| `<app>-android-arm64-v8a.apk` | ARM64 Split APK | Modern phones and tablets |
| `<app>-android-armeabi-v7a.apk` | ARMv7 Split APK | Legacy 32-bit Android devices |
| `<app>-android-x86_64.apk` | x86-64 Split APK | Android emulators & Chromebooks |
| `<app>-android.aab` | Android App Bundle | Google Play Store console upload (omitted from public GitHub Releases) |
| `<app>-windows.zip` | Standalone ZIP | Portable Windows version without install |
| `<app>-windows-installer.exe` | Inno Setup Setup EXE | Clean Windows installer with desktop & start menu shortcuts |
| `debug_symbols.zip` | Native Debug Symbols | Crash symbolication on Google Play / Bugsnag |
| `release_body.md` | Release Body Markdown | Ready-to-copy GitHub Release notes with downloads table |

---

## How Auto-Detection Works

### 1. App Name & Version
- Reads `name` from `pubspec.yaml` (e.g., `name: quran` → `$appName = "quran"`).
- Reads `version` regex `(?m)^version:\s*(\d+(?:\.\d+)*)` (e.g., `0.6.01+11` → `$version = "0.6.01"`).

### 2. Android Package Name
If `-PackageName` is not provided:
- Checks `android/app/build.gradle` for `namespace` or `applicationId`.
- Checks `android/app/src/main/AndroidManifest.xml` for `package="..."`.
- Falls back to `com.hassaneltantawy.<appName>`.

### 3. Windows Binary Name
- Checks `windows/CMakeLists.txt` for `set(BINARY_NAME "...")`.
- Falls back to `<appName>.exe`.

### 4. Windows AppId (GUID)
- Generates a stable GUID from the MD5 hash of `PackageName`.
- Ensures future installer updates cleanly replace the previous installation rather than duplicating it.

---

## Troubleshooting & FAQ

### 1. `File build_release.ps1 cannot be loaded because running scripts is disabled`
Open PowerShell and run:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

### 2. `ISCC.exe not found`
The script attempts to install Inno Setup 6 automatically via `winget`. If your environment blocks package installation, install it manually from [jrsoftware.org/isdl.php](https://jrsoftware.org/isdl.php) or run:
```powershell
winget install JRSoftware.InnoSetup
```

### 3. Android signing failed / `keystore not found`
Ensure your local `android/key.properties` has the correct paths:
```properties
storePassword=your_password
keyPassword=your_password
keyAlias=upload
storeFile=C:/path/to/upload-keystore.jks
```

### 4. Where is the script located?
The script is located in:
- `D:\GitHub\.github\build_release.ps1`
- `D:\GitHub\.github\scripts\build_release.ps1`
