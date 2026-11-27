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

Root analysis excludes the historical standalone `tools/ocr_spike` package, whose
experimental dependencies are not part of the app. When working on that harness,
run `flutter pub get` and `flutter analyze` in its own directory. Main-app analysis
must also pass without the harness's ignored `.dart_tool/package_config.json`.

In each affected package (`packages/receipt_domain`, `packages/receipt_parser`,
`packages/receipt_storage`), run `dart pub get`, `dart analyze` and `dart test`.
Run `python -m unittest discover -s tools/licenses -p 'test_*.py'` when changing
license tooling. Release tooling uses
`python -m unittest discover -s tools/releases -p 'test_*.py'` and
`python tools/releases/version.py --check`. CI helpers use
`python -m unittest discover -s tools/ci -p 'test_*.py'` and the checksum-pinned
`python tools/ci/dev_tools.py actionlint`. For artifact/notice checks, follow the
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
| Header branch recommendations and automatic selection | `branch_recommendations_test.dart` (synthetic pixels and fake storage) |
| Android memory-only camera | `camera_capture_test.dart` (opt-in native interaction) |
| Manual/OCR correction | `manual_correction_test.dart`, `ocr_correction_test.dart` |
| Deletion and stale screens | `receipt_deletion_test.dart` |
| Password-protected recovery | `protected_backup_test.dart` |
| Dashboard | `spending_dashboard_test.dart` |
| Categories and regrouping | `category_workflow_test.dart` |
| Explicit product equivalence/prices | `product_comparison_test.dart` |
| Historical-schema migration/recovery | `migration_recovery_test.dart` |

## Restore normal entry points after integration tests

Interactive native-picker checks are opt-in and require selecting synthetic
fixtures in the system dialogs. The backup check saves/reads its synthetic encrypted
bytes. The image check imports `test/fixtures/synthetic_receipt.png`, then cancels
the second prompt. Verify the source hash separately before/after; use only local
synthetic files. Both checks initialize accessibility before recording test handles.

```powershell
flutter test integration_test/backup_picker_test.dart -d windows --dart-define=INTERACTIVE_BACKUP_PICKER=true
flutter test integration_test/image_picker_test.dart -d windows --dart-define=INTERACTIVE_IMAGE_PICKER=true
flutter test integration_test/backup_picker_test.dart -d emulator-5554 --no-uninstall --dart-define=INTERACTIVE_BACKUP_PICKER=true
flutter test integration_test/image_picker_test.dart -d emulator-5554 --no-uninstall --dart-define=INTERACTIVE_IMAGE_PICKER=true
```

Copy the committed synthetic image into the emulator's Downloads first if needed.
These picker harnesses never open normal application databases.

Camera smoke testing uses an emulator with an emulated rear camera, initially
denied CAMERA permission, and recorded airplane/permission state. Run:

```powershell
flutter test integration_test/camera_capture_test.dart -d emulator-5554 --no-uninstall --dart-define=INTERACTIVE_CAMERA=true
```

In order: deny permission; retry, allow and cancel; take two pictures; then press
Home during the final capture and return to the app. The harness checks upright
bounded images, native OCR, cancellation and disposal without opening the application database. Compare
the emulator's gallery image IDs and app-private image paths before/after (never
delete existing photos), then restore its previous permission/airplane state.
For repeat runs, reset CAMERA's `user-set`/`user-fixed` permission flags on the
emulator as well; do not clear app data to reset permission history.

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

Debug-only OCR tests missed ML Kit registrar constructors being removed by R8.
`python tools/ci/android_release_smoke.py` now builds an optimized, emulator-key APK
and inspects its actual public no-argument constructors. It uses only the existing
debug key and creates no versioned assets. The production APK wrapper repeats this
inspection with the permanent certificate and always builds `lib/main.dart`.

Local opt-in `private_ocr_check_test.dart` reads three anonymous `input-N.jpg`
copies staged in app-private `cache/receipt-private-ocr-check/`; enable it with
`--dart-define=PRIVATE_OCR_CHECK=true`. Verify copies byte-for-byte and remove them
afterward. The test and `tools/ocr_device_probe/main.dart` report only status/counts,
never recognized text. The latter can run the same inputs in optimized release mode
using the emulator's existing signing identity; never publish that entry point or
install it over the phone's retained permanent-key app. Restore the normal debug
entry point afterward. Originals and private fixtures never enter source/assets.
