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
set the SDK path above if needed. Open the repository root as the Flutter
project and run `lib/main.dart` with Windows or the Android emulator selected.

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

## Build loop

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

The environment milestone in `plan.md` is complete. The repository now has its
own Flutter scaffold; use it for ongoing development. The disposable project
remains available for isolated toolchain checks. Emulator IDs can change between sessions,
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

The application-support path plugin also uses Android SDK Platform **35**
(revision 2), installed alongside platform 36 by Gradle on 2026-11-16. Keep both
platforms available; Gradle used the already accepted SDK licenses.

The first Android build downloads Gradle and build dependencies. Subsequent
builds reuse the local caches. Flutter uses Android Studio's bundled JDK 21,
even though invoking plain `java` in this PC's terminal may find Java 8.

## Local application data

The normal app saves reviewed manual and supported OCR receipts in its application-
support directory, outside this checkout. See [manual saving and history](manual-saving.md)
for paths, review/retry behaviour, native smoke commands and backup limitations.
See [OCR saving](ocr-saving.md) for the separate evidence policy and schema-v2
migration. WSL Git commands do not move or back up this database.

## Commit style

Keep commits focused on one coherent change, including its directly related
documentation and verification. Prefer a concise, descriptive one-line commit
message. Avoid mixing unrelated changes or committing generated build outputs,
local SDK paths, and private receipt images.

## Filtered history verification

See [history filters](history-filters.md) for supported bounds, pagination/retry
behavior and current verification results. Run its synthetic native smoke with:

```powershell
flutter test integration_test/history_filter_test.dart -d emulator-5554
flutter test integration_test/history_filter_test.dart -d windows
```

As with the saving smoke tests, restore the prior emulator airplane setting,
rebuild the normal apps and reinstall the normal debug APK afterwards. The test
uses an isolated temporary database; the normal app-support data is preserved.

## Manual correction verification

[Reviewed manual corrections](manual-corrections.md) use the same Windows/Android
toolchain and existing SQLite schema. Run the synthetic correction/reopen and
stale-write smoke with:

```powershell
flutter test integration_test/manual_correction_test.dart -d emulator-5554
flutter test integration_test/manual_correction_test.dart -d windows
```

Restore the normal app entry points and prior emulator airplane setting after
integration tests. The smoke preserves the normal application-support database.

## OCR correction verification

[Fresh-image OCR corrections](ocr-corrections.md) preserve receipt/row identity
and OCR provenance using the existing schema. The synthetic native correction,
reopen and concurrent stale-write test runs on both platforms:

```powershell
flutter test integration_test/ocr_correction_test.dart -d emulator-5554
flutter test integration_test/ocr_correction_test.dart -d windows
```

Restore the normal app builds and prior emulator airplane setting afterwards.
The test uses isolated synthetic data. Windows production OCR recognition and
packaging remain pending; this verifies shared review/storage, not that adapter.

## Receipt deletion verification

[Reviewed receipt deletion](receipt-deletion.md) uses schema 3, with tested
migration from schemas 1 and 2. Run the synthetic deletion/reopen/retry and
stale-screen smoke with:

```powershell
flutter test integration_test/receipt_deletion_test.dart -d emulator-5554
flutter test integration_test/receipt_deletion_test.dart -d windows
```

Use the emulator's current ID from `flutter devices`. Test offline by recording
its current airplane setting, enabling airplane mode for the Android smoke, and
restoring the recorded setting afterwards. The smoke uses only a guarded,
isolated temporary database and preserves normal application data.

Integration tests build their own entry point. Restore normal builds afterwards:

```powershell
flutter build windows --debug
flutter build apk --debug
$receiptAdb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
& $receiptAdb install -r build/app/outputs/flutter-apk/app-debug.apk
& $receiptAdb shell am start -W -n fi.juhonis.receipt_reader/.MainActivity
```

Do not uninstall or clear app data to restore the normal app. Deletion retains
historical financial records; it is not secure erasure and has no undo yet.

## Backup/recovery core verification

The [structured recovery engine](backup-recovery.md) uses the existing SQLite
toolchain and schema 3. Run its private synthetic export/file-read/restore/reopen
smoke with:

```powershell
flutter test integration_test/backup_restore_test.dart -d emulator-5554
flutter test integration_test/backup_restore_test.dart -d windows
```

The Android check runs in airplane mode; restore its prior setting afterwards.
Rebuild and launch the normal Windows app and reinstall the normal debug APK
using the commands above. The smoke preserves normal application data. This
engine stages recovery only; user-facing file encryption, UI and active-dataset
replacement remain pending.

## Password-protected backup workflow

[Encrypted backups](password-backups.md) use the pinned Dart cryptography package,
Android document intents and the existing Windows file selector. No additional
SDK, native crypto runtime or network service is needed. The emulator AVD remains
Receipt_Reader_API_36_1; use its current ID from flutter devices.

Run integration_test/protected_backup_test.dart on Windows and emulator-5554 to
verify UI export, password failures, reviewed activation, previous-data recovery
and explicit recovery from an unreadable receipt database. The tests use guarded
synthetic app-support subdirectories. The interactive backup_picker_test.dart
opens the actual save/open dialogs and expects the same synthetic file back; opt
in with --dart-define=INTERACTIVE_BACKUP_PICKER=true (otherwise it is skipped).

Restore the prior airplane setting, rebuild normal entry points and reinstall
the normal debug APK after testing. Do not uninstall or clear app data. The normal
app now creates workspace.sqlite beside the original receipts.sqlite, with an
exclusive workspace.lock and retained receipt-restore-* directories after restores.
WSL Git does not move or back up these private application-support files.

## Product and alias storage verification

[The catalog foundation](product-catalog.md) uses the existing Dart/SQLite toolchain;
no additional SDK, service or native dependency is required. Schema 4 migrates
released schemas 1/2/3; schema 5 adds reviewed receipt product links and also
migrates schema 4. No additional setup is required. Run the native workflows with:

```powershell
flutter test integration_test/product_catalog_test.dart -d windows
flutter test integration_test/product_catalog_test.dart -d emulator-5554
```

This checks catalog writes, exact suggestions, encrypted activation, fresh-origin
edits, reopen and previous-data recovery in guarded temporary app-support storage.
The `integration_test/catalog_review_test.dart` workflow additionally checks the
Finnish catalog screens, explicit selection, receipt correction and encrypted
linked-history recovery. Run it with the same device arguments. Run Android in
airplane mode and
restore its prior setting. Serialize Flutter commands and restore normal app builds
using the receipt-deletion commands above; never uninstall or clear normal data.

## Spending summary verification

[Receipt spending](spending-summary.md) uses the existing Flutter/Dart and SQLite
toolchain without a schema migration or additional dependency. Run the isolated
native workflow with:

    flutter test integration_test/spending_test.dart -d windows
    flutter test integration_test/spending_test.dart -d emulator-5554

This covers complete mixed-row receipt totals, more than one history page,
branch/day filtering, correction, encrypted activation while the page remains open,
queued reads, deletion, reopen and previous-dataset recovery. Only guarded synthetic
spending-smoke-* app-support directories are created and removed. Use a temporary
build-dir when normal Windows Debug sessions hold the executable open, and restore
the prior build-dir and emulator airplane setting afterward. Rebuild the normal
Windows release/Android debug entry points and upgrade-install the APK without
uninstalling or clearing app data.

## Native migration and recovery rehearsal

[The upgrade rehearsal](migration-recovery.md) exercises populated schemas 1–6,
transaction rollback/retry, exact retained history, catalog links, both analytics
screens and repeated encrypted recovery. Run:

    flutter test integration_test/migration_recovery_test.dart -d windows
    flutter test integration_test/migration_recovery_test.dart -d emulator-5554

The test uses generated historical schemas and guarded synthetic app-support
directories. Keep normal Windows sessions running by choosing a temporary
build-dir for its Debug executable; restore the previous configuration afterward.
Run Android in airplane mode and restore its prior setting, then rebuild and
upgrade-install the normal Android app without uninstalling or clearing data.
The package version runs in packages/receipt_storage/test/upgrade_recovery_test.dart.

The [category workflow](product-categories.md) separately verifies existing
product links through a schema-6→7 upgrade, reviewed classification, dashboard
receipt links and encrypted backup recovery:

    flutter test integration_test/category_workflow_test.dart -d windows
    flutter test integration_test/category_workflow_test.dart -d emulator-5554

The same offline, isolated-data and normal-build restoration rules apply.

## App-owned Windows OCR setup

The approved [OCR bundle](windows-ocr.md) adds a source/model preparation
step for Windows builds (repeat after flutter clean). Use Windows Python 3.12+ and the existing Visual Studio
2022 C++/CMake tools (no pip packages needed):

    python tools/windows_ocr/setup.py
    flutter build windows --release
    python tools/windows_ocr/package.py

Setup downloads only pinned public source archives and Finnish/English models.
Build outputs stay under build/windows-ocr. The normal Windows app requires no
installed Tesseract, Python or model download. Native recognition and saving use:

    flutter test integration_test/receipt_ocr_engine_test.dart -d windows
    flutter test integration_test/receipt_ocr_engine_test.dart -d emulator-5554

The ZIP and checksum/evidence file are under build/distribution. The included
synthetic_receipt.png and [clean-machine checklist](windows-ocr-clean-machine.md)
are for the second Windows PC. Keep it offline from before first launch; do not
install development dependencies to mask a missing runtime. Restore normal app
entry points and the prior emulator airplane setting after native tests.

## Dependency notice verification

The committed supplemental notices are included automatically by Flutter builds.
The ZIP packager checks the reviewed input hashes, the full generated notice
asset and Windows SQLite provenance, then includes readable notices and the
component inventory. No Android dependency resolution is needed for an unchanged
Windows-only checkout. After changing dependencies, SDK or Android build inputs,
follow the [audit/update procedure](dependency-licenses.md#reproduce-and-update)
before packaging. Keep upstream notice text formatting; do not hand-edit generated
notice files to make a verification failure disappear.

The native license-page check is independent of receipt storage:

    flutter test integration_test/software_licenses_test.dart -d windows
    flutter test integration_test/software_licenses_test.dart -d emulator-5554

Run Android offline, restore its previous airplane setting, and rebuild/install
normal app entry points afterward. The test binding disables automatic license
registration, so this test registers the real packaged asset explicitly; ordinary
app startup uses Flutter's standard ServicesBinding registry.
