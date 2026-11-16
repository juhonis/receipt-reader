# Receipt Reader

A local-first receipt tracker for Android and Windows, with a Finnish UI.

## Current state

The app imports receipt images on Android and Windows, recognizes text on
Android, and supports evidence-backed review with explicit saving to local
SQLite. [Manual saving](docs/manual-saving.md),
[reviewed OCR saving](docs/ocr-saving.md),
[history filters](docs/history-filters.md) and
[reviewed manual corrections](docs/manual-corrections.md) have synthetic native
integration checks on both platforms. The Windows OCR adapter/packaging,
saved OCR correction, deletion, structured backup/restore and sync remain open.

See [the project plan](docs/plan.md) for the next milestone and
[OCR spike findings](docs/ocr-spike.md) for engine evidence and remaining
selection decisions. The separate [development harness](tools/ocr_spike/README.md)
can reproduce the baseline.

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
native OCR and storage adapters, with tests in the corresponding packages.

Keep original test receipts in the ignored `localreceipts/` directory.
Only explicitly anonymized fixtures should enter version control.
Commit `pubspec.lock` to keep application dependencies reproducible.

Use focused commits with concise one-line messages.
