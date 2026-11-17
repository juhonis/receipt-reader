# Receipt Reader

A local-first receipt tracker for Android and Windows, with a Finnish UI.

## Current state

The app imports receipt images on Android and Windows, recognizes text on
Android, and supports evidence-backed review with explicit saving to local
SQLite. [Manual saving](docs/manual-saving.md),
[reviewed OCR saving](docs/ocr-saving.md),
[history filters](docs/history-filters.md),
[reviewed manual corrections](docs/manual-corrections.md),
[fresh-image OCR corrections](docs/ocr-corrections.md) and
[reviewed receipt deletion](docs/receipt-deletion.md) have synthetic native
integration checks on both platforms. SQLite schema 5 migrates existing data
from schemas 1–4 without changing prior event bytes. The
[structured backup/recovery core](docs/backup-recovery.md) and
[password-protected backup UI](docs/password-backups.md) include reviewed recovery
and retained previous datasets, with native checks on both platforms.
[Product/alias management](docs/product-catalog.md) provides Finnish catalog
screens and explicit reviewed receipt links, preserved through encrypted recovery.
[Product purchase history](docs/purchase-history.md) adds linked purchase rows and
page-scoped comparable price charts, preserving raw amounts and separating discounts,
deposits, returns and unit/revision groups. Full date-range analytics, Windows OCR
packaging and sync remain open.

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
