# Windows development setup

This app targets native Android and Windows with one Flutter codebase. Use
PowerShell and Windows-native tools for this checkout. Its current location,
`C:\Users\juhoe\StudioProjects\receipt-reader`, is suitable.

## Tools and locations on this PC

- Setup date: 2026-11-14. Flutter stable **3.50.0**, Dart **3.14.0**,
  Visual Studio Build Tools 2022 **17.14.45**, Windows SDK **10.0.26100.0**,
  Android SDK platform **36**, build tools **36.0.0**, command-line tools
  **23.0**, and Android NDK **28.2.13676358**.
- Flutter SDK: `C:\Users\juhoe\Flutter\flutter_windows_3.35.6-stable\flutter`.
  The folder name records the original download, not necessarily the current
  version. Run `flutter --version` to check. Dart is included with Flutter.
- Android SDK: `C:\Users\juhoe\AppData\Local\Android\Sdk`.
- Android Studio: `C:\Program Files\Android\Android Studio`.
  Its bundled Java runtime is used by Flutter; do not use the old Java 8 on
  the system PATH for Android builds.
- Windows builds need Visual Studio 2022 Build Tools with the C++ desktop
  workload, recommended components, CMake, and a Windows SDK. This is separate
  from VS Code; the full Visual Studio editor is optional.
- Android Studio's Flutter and Dart plugins are already installed.

The setup added Flutter's `bin`, Android `platform-tools`, and the user's
WindowsApps directory to the user PATH, and set `ANDROID_HOME` to the SDK
directory. Existing PATH entries and older installed toolchains were retained.

After environment changes, restart Android Studio and your terminal (and any
coding application that launches terminals) to inherit the new PATH.

## Verify the tools

Run in a fresh PowerShell terminal:

```powershell
Get-Command flutter, dart, adb
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter devices
flutter emulators
```

Review and accept any outstanding Android SDK licenses interactively.
The Flutter, Android toolchain, and Visual Studio checks should pass.
Web-browser checks are not required for this project's two target platforms.

In Android Studio, check **Settings > Languages & Frameworks > Flutter** and
set the SDK path above if needed. The project currently contains planning
documents; there is no Flutter app or runnable `lib/main.dart` yet.

## Android testing

For an emulator, open **Tools > Device Manager**, create a phone device, select
an installed x86_64 Android image, and start it. Windows Hypervisor Platform
acceleration is already available on this PC. An emulator avoids needing a
phone during initial development.

The setup created **Receipt_Reader_API_36_1** using the Pixel 7 device profile
and the installed Android 36.1 Google Play x86_64 image. Start this existing
device from Device Manager, or run:

```powershell
flutter emulators --launch Receipt_Reader_API_36_1
```

For a physical phone, enable Developer options and USB debugging on the phone,
connect with a data-capable USB cable, and approve this computer's debugging
prompt. Check `adb devices` and `flutter devices`. Some manufacturers require
a Windows USB driver. A physical phone is useful for receipt-camera tests.

## Build loop once the Flutter app exists

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter devices
flutter run -d <android-device-id>
```

Use the actual Android device ID from `flutter devices`. In `flutter run`,
press `r` for hot reload, `R` for hot restart, and `q` to stop the app.

For reproducible build verification:

```powershell
flutter build windows --debug
flutter build apk --debug
```

Windows Developer Mode is already enabled; Flutter plugins can need it for
symlinks. Android Studio may remain your main editor for both build targets.
There is no need to install Node.js, Docker, a database server, or standalone
Dart for this project. OCR engines and model assets will be chosen during the
platform spike, not installed globally in advance.

## Windows versus WSL

Using WSL Git to inspect or manage this checkout is fine. The repository's
`.gitattributes` keeps text files on LF line endings, with CRLF for Windows
command scripts, so Windows and WSL Git agree. Avoid simultaneous Git writes
from both environments. Local Android Studio settings in `.idea/` are ignored.

Do not run Linux Flutter against this Windows checkout or share generated
`build/` and `.dart_tool/` directories across Windows and WSL. Use a separate
WSL checkout if Linux-side auxiliary work is needed. Run these commands in
PowerShell, not a WSL terminal. Keep SDK paths and local configuration out of
version control; Flutter's generated project supplies the usual ignore rules.

## Verification results (2026-11-14)

- `flutter doctor -v`: no issues; Visual Studio 2022 and the Android emulator
  are detected.
- A disposable Flutter project was created at
  `C:\dev\receipt-environment-check`, outside this repository.
- `flutter build windows --debug`: passed.
- `flutter run -d windows --no-resident`: passed; the native app launched and
  responded, then was closed after verification.
- `flutter run -d emulator-5554 --no-resident`: passed; the debug APK built,
  installed, and launched on the Android emulator.

The environment milestone in `plan.md` is complete. The receipt app itself has
not been scaffolded. The disposable project remains available for repeating
these checks; it does not contain receipt-app implementation. The emulator
remains running for development. Emulator IDs can change between sessions,
so use `flutter devices` to find the current ID.

## First-build troubleshooting

Flutter 3.50.0 requests Android NDK `28.2.13676358`. The newly released Android
command-line tools use Android CLI behind the legacy `sdkmanager` command.
During setup, Gradle's automatic NDK installation failed with `Package ndk
not found`. Installing the exact NDK with the new CLI resolves that download
step without changing the app's NDK requirement:

```powershell
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\android.exe" --sdk "$env:ANDROID_HOME" sdk install ndk/28.2.13676358
```

The first Android build downloads Gradle and build dependencies. Subsequent
builds reuse the local caches. Flutter uses Android Studio's bundled JDK 21,
even though invoking plain `java` in this PC's terminal may find Java 8.

## Commit style

Keep commits focused on one coherent change, including its directly related
documentation and verification. Prefer a concise, descriptive one-line commit
message. Avoid mixing unrelated changes or committing generated build outputs,
local SDK paths, and private receipt images.
