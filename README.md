# Receipt Reader

A local-first receipt and spending tracker for Android and Windows, with a Finnish
UI. Personal testing is the current goal. The signed alpha.5 APK/ZIP draft pipeline
works; full real-phone acceptance and retained-data upgrades remain open.

## What works

- Offline receipt-image import and OCR, review, corrections, deletion and history.
- Android in-app camera capture without gallery or temporary image files.
- Products, aliases, editable categories and explicit cross-store price comparisons.
- Week/month/year/custom dashboards, spending breakdowns and product price trends.
- Password-protected backups and reviewed recovery.

Device synchronization is not implemented. Windows
has a development ZIP; Android release builds require the permanent release key.
The release workflow prepares a draft alpha APK/ZIP; it never publishes automatically.
There is no in-app updater yet.

## Start here

- [Documentation index](docs/README.md)
- [Roadmap and next milestone](docs/plan.md)
- [Windows development setup](docs/windows-development.md)
- [Phone testing](docs/phone-testing.md)
- [Release and update plan](docs/releases.md)

## Development

Use Windows-native Flutter 3.50.0 stable / Dart 3.14.0 and PowerShell:

```powershell
flutter pub get
flutter analyze
flutter test
python tools/windows_ocr/setup.py
flutter run -d windows
```

The OCR setup downloads pinned public dependencies; repeat it after `flutter clean`.
For Android, select a device from `flutter devices`. See [testing](docs/testing.md)
for package checks and native tests that preserve application data.

Keep original receipts in ignored `localreceipts/`; commit only synthetic or
explicitly anonymized fixtures. Keep commits focused with concise one-line messages.

## License

[MIT](LICENSE). Third-party components retain their own licenses and terms; see
[dependency notices](docs/dependency-licenses.md).
