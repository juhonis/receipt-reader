# Windows development setup

Use PowerShell and Windows-native tools for this Android/Windows Flutter checkout.
WSL Git is fine; do not run Linux Flutter against the same generated directories.
See [testing](testing.md), [phone testing](phone-testing.md) and [releases](releases.md)
for checks and distribution, rather than appending feature verification here.

## Toolchain

| Tool | Configured baseline |
| --- | --- |
| Flutter / Dart | Flutter stable 3.50.0 / bundled Dart 3.14.0 |
| Android Studio | Installed with Flutter/Dart plugins; use its bundled JDK 21 |
| Android SDK | Platforms 35 and 36, build tools 36.0.0, NDK 28.2.13676358 |
| Emulator | `Receipt_Reader_API_36_1`, Pixel 7 profile, Android 36.1 Google Play x86_64 |
| Windows C++ | Visual Studio 2022 Build Tools 17.14.45, C++ desktop workload, CMake, Windows SDK 10.0.26100.0 |
| Windows OCR setup | Python 3.12+; builds pinned bundled Tesseract/models using the C++ tools |

Default Android SDK location: `$env:LOCALAPPDATA\Android\Sdk`. Android Studio is
normally under `C:\Program Files\Android\Android Studio`; its `jbr` provides Java.
The Flutter SDK directory name on this PC reflects an older download; use
`(Get-Command flutter).Source` and `flutter --version` to identify the actual SDK.
Set that SDK in Android Studio's Flutter settings.

Keep Flutter `bin` and Android `platform-tools` on the Windows user PATH, and set
`ANDROID_HOME` to the Android SDK. Restart terminals/editors after environment
changes. Windows Developer Mode supports plugin symlinks; the C++ build tools are
separate from VS Code. No Node.js, Docker, database server or separate Dart install
is required. End-user builds need neither Flutter nor a global Tesseract install.

## Verify and start the environment

```powershell
Get-Command flutter, dart, adb, python
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter devices
flutter emulators
flutter emulators --launch Receipt_Reader_API_36_1
```

Accept SDK licenses interactively. Flutter, Android and Visual Studio checks should
pass; web-browser checks are not required. Start the emulator through Android
Studio Device Manager instead if preferred. Emulator IDs can change; use the current
one from `flutter devices`. A physical phone needs a data USB cable, approved USB
debugging and sometimes a manufacturer Windows driver for developer access.

## Everyday build loop

```powershell
flutter pub get
flutter analyze
flutter test
python tools/windows_ocr/setup.py
flutter run -d windows
flutter devices
flutter run -d emulator-5554
```

Run each app session separately. OCR setup downloads pinned public sources/models;
repeat after `flutter clean`. In `flutter run`, `r` reloads, `R` restarts and `q`
ends the session. Open the repo root in Android Studio and use `lib/main.dart`.
Use the emulator for debug/integration work and the signed release channel for
retained phone data. [Native tests](testing.md) require `--no-uninstall` on Android.

Build/package Windows with:

```powershell
flutter build windows --release
python tools/licenses/audit.py --windows build/windows/x64/runner/Release
python tools/windows_ocr/package.py
```

The development ZIP and evidence are in `build/distribution/`; it includes the OCR
worker/models and Microsoft runtime. It is not yet a signed public release. Follow
[the OCR guide](windows-ocr.md) and [clean-machine checklist](windows-ocr-clean-machine.md).
For Android, `flutter build apk --debug` builds the emulator APK. Release builds
require permanent signing; use the [verified APK wrapper](releases.md#local-apk-build)
for versioned artifacts and certificate/notice checks.

## First-build troubleshooting

The initial Android build downloads Gradle/native dependencies. Keep SDK platforms
35 and 36 available. Flutter uses Android Studio's JDK; plain `java` may still find
an unrelated Java 8 installation. Set `JAVA_HOME` to the Studio `jbr` when running
Gradle tooling directly.

If Gradle cannot download the pinned NDK with the newer Android command-line tools:

```powershell
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\android.exe" --sdk "$env:ANDROID_HOME" sdk install ndk/28.2.13676358
```

Do not change dependency/tool versions just to mask a missing component. Use the
[dependency audit instructions](dependency-licenses.md#reproduce-and-update) after
intentional toolchain/dependency changes.

## Git, local data and fixtures

WSL and Windows Git can manage this checkout; avoid simultaneous writes. The root
`.gitattributes` keeps LF text with CRLF command scripts. `.idea/`, generated build
outputs and private `localreceipts/` are ignored. Do not commit SDK paths, signing
credentials, databases/backups or private receipt images.

Use a separate checkout for Linux tooling; never share Windows/Linux `.dart_tool/`
and `build/`. WSL Git access does not move or back up application data.

The normal database lives in application-support storage outside the repo/program
folder. Preserve it across builds; use password-protected backups rather than
relying on Git or sync. See [recovery](password-backups.md). To explore the charts,
use the explicitly opted-in [synthetic demo loader](sample-receipts.md).

Keep commits focused on a coherent change with a concise one-line message. Update
existing docs where possible; keep routine test outcomes in commits/release notes.
