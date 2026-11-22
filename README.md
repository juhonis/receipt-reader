# Receipt Reader

A local-first receipt tracker for Android and Windows, with a Finnish UI.

## Current state

The app imports and recognizes receipt images offline on Android and Windows,
using bundled ML Kit and [app-bundled Tesseract](docs/windows-ocr.md). It supports
evidence-backed review with explicit saving to local
SQLite. [Manual saving](docs/manual-saving.md),
[reviewed OCR saving](docs/ocr-saving.md),
[history filters](docs/history-filters.md),
[reviewed manual corrections](docs/manual-corrections.md),
[fresh-image OCR corrections](docs/ocr-corrections.md) and
[reviewed receipt deletion](docs/receipt-deletion.md) have synthetic native
integration checks on both platforms. SQLite schema 6 migrates existing data
from schemas 1–5 without changing prior event bytes. The
[structured backup/recovery core](docs/backup-recovery.md) and
[password-protected backup UI](docs/password-backups.md) include reviewed recovery
and retained previous datasets, with native checks on both platforms.
[Product/alias management](docs/product-catalog.md) provides Finnish catalog
screens and explicit reviewed receipt links, preserved through encrypted recovery.
[Product purchase history](docs/purchase-history.md) adds linked purchase rows and
full date-range summaries and calendar price-range charts, preserving raw amounts
and separating discounts, deposits, returns and unit/revision groups.
[Receipt spending](docs/spending-summary.md) adds full signed totals by branch and
calendar month with inclusive branch/date filters and explicit coverage notices.
[Migration/recovery rehearsals](docs/migration-recovery.md) verify supported-schema
upgrades, retained history and analytics through encrypted restore and reopen.
A Windows development ZIP includes OCR assets and a synthetic clean-machine test.
The user reports successful laptop recognition, review/save and reopening saved
history after moving the program folder, following the earlier offline test.
[Quick or optional guided review](docs/receipt-review.md) now uses one final
approval for ordinary receipts, with highlighted validation problems and no
mandatory checklist note. The [dependency notice audit](docs/dependency-licenses.md)
adds an offline license screen, full SDK/native notices and artifact validation.
The [Finnish OCR corpus](docs/finnish-ocr-corpus.md) covers 23 synthetic receipt
cases and three actual-engine cases on each platform, with review warnings for
uncertain sign/decimal recovery. Photograph evaluation, application licensing/distribution decisions, signing
and sync remain open.

See [the project plan](docs/plan.md) for the next milestone and
[OCR spike findings](docs/ocr-spike.md) and [approved OCR direction](docs/windows-ocr.md)
for engine evidence and remaining release checks. The separate [development harness](tools/ocr_spike/README.md)
can reproduce the baseline.

## Development

Use Flutter 3.50.0 stable (Dart 3.14.0) from Windows PowerShell. See
[Windows setup](docs/windows-development.md) for toolchain and emulator details.

```powershell
flutter pub get
flutter analyze
flutter test
# Prepare Windows OCR; repeat after flutter clean (downloads public dependencies):
python tools/windows_ocr/setup.py
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
Only synthetic or explicitly anonymized fixtures should enter version control.
Commit `pubspec.lock` to keep application dependencies reproducible.

Use focused commits with concise one-line messages.
