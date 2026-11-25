# Development checks

Run from Windows PowerShell using the [configured toolchain](windows-development.md).
Serialize Flutter commands. Use checks appropriate to the changed behavior rather
than repeating every historical milestone workflow.

## Shared checks

```powershell
flutter pub get
flutter analyze
flutter test
```

In each affected package (`packages/receipt_domain`, `packages/receipt_parser`,
`packages/receipt_storage`), run `dart pub get`, `dart analyze` and `dart test`.
Run `python -m unittest discover -s tools/licenses -p 'test_*.py'` when changing
license tooling. Release tooling uses
`python -m unittest discover -s tools/releases -p 'test_*.py'` and
`python tools/releases/version.py --check`. For artifact/notice checks, follow the
[dependency audit](dependency-licenses.md#reproduce-and-update).

## Native integration workflows

Use the emulator, not a phone retaining real release data. Pick a focused workflow
under `integration_test/` and the current device ID from `flutter devices`:

```powershell
flutter test integration_test/product_comparison_test.dart -d windows
flutter test integration_test/product_comparison_test.dart -d emulator-5554 --no-uninstall
```

**Every Android integration command must include `--no-uninstall`.** Flutter 3.50
otherwise uninstalls the package afterward and deletes its normal application data,
even when the test itself uses a temporary database. Do not use uninstall or data
clearing to recover from a build/install/signature failure.

Tests use guarded synthetic temporary workspaces except the explicitly opted-in
[demo loader](sample-receipts.md), which adds records to normal application storage.
Inspect the selected test's setup before running it. For offline workflows, record
the emulator's airplane setting, test offline, then restore that prior setting.
Keep normal Windows executables closed if a build needs to replace them, or use
an isolated build directory and restore its configuration afterward.

| Changed area | Relevant integration entry point |
| --- | --- |
| Bundled OCR/import/save | `receipt_ocr_engine_test.dart` |
| Manual/OCR correction | `manual_correction_test.dart`, `ocr_correction_test.dart` |
| Deletion and stale screens | `receipt_deletion_test.dart` |
| Password-protected recovery | `protected_backup_test.dart` |
| Dashboard | `spending_dashboard_test.dart` |
| Categories and regrouping | `category_workflow_test.dart` |
| Explicit product equivalence/prices | `product_comparison_test.dart` |
| Historical-schema migration/recovery | `migration_recovery_test.dart` |

## Restore normal entry points after integration tests

```powershell
flutter build windows --debug
flutter build apk --debug
$receiptAdb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
& $receiptAdb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
& $receiptAdb -s emulator-5554 shell am start -W -n fi.juhonis.receipt_reader/.MainActivity
```

Replace the emulator ID when needed and target it explicitly when a phone is also
connected. Restore a normal Windows Release build too if it was used for acceptance.
Debug builds/keys are for the emulator; phone release upgrades follow
[phone testing](phone-testing.md), not this restoration command.

## Release acceptance

Unit and native tests are necessary evidence, not the full release gate. Test the
actual packaged APK/ZIP, native file pickers, offline startup, retained-data upgrade,
encrypted recovery and [Windows clean-machine behavior](windows-ocr-clean-machine.md).
See [releases](releases.md) for the draft/publication sequence.
