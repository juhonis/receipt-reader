# Receipt Reader

A local-first receipt tracker for Android and Windows, with a Finnish UI.

## Current state

The Flutter scaffold builds on both targets and contains a localized starter
screen. Receipt import, OCR, storage, and sync are not implemented yet.
The next milestone is the offline OCR platform spike described in
[the project plan](docs/plan.md).
The first baseline and remaining decisions are documented in
[OCR spike findings](docs/ocr-spike.md); the separate
[development harness](tools/ocr_spike/README.md) can reproduce it.

## Development

Use Flutter 3.50.0 stable (Dart 3.14.0) from Windows PowerShell. See
[Windows setup](docs/windows-development.md) for toolchain and emulator details.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
# Start Receipt_Reader_API_36_1 in Android Studio, then find its ID:
flutter devices
flutter run -d emulator-5554
```

`flutter pub get` generates localization code from `lib/l10n/app_fi.arb`.
Keep app strings in that ARB file. `lib/app.dart` holds the app shell;
`lib/main.dart` is the entry point. Add shared domain logic independently of
native OCR and storage adapters as the platform spike establishes their needs.

Keep original test receipts in the ignored `localreceipts/` directory.
Only explicitly anonymized fixtures should enter version control.
Commit `pubspec.lock` to keep application dependencies reproducible.

Use focused commits with concise one-line messages.
