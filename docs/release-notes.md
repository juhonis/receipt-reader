# v0.2.0-alpha.2

First GitHub alpha candidate for Android and Windows, with a Finnish UI. The earlier
local alpha build remains separate; this APK uses a greater Android build number.

- Offline JPEG/PNG receipt recognition, reviewed saving/corrections and history.
- Week/month/year/custom spending charts, categories and product price comparisons.
- Password-protected backups and reviewed dataset recovery.

Android: download the universal APK; Android 7/API 24 or newer, including Android 14.
Approve the system installer. USB and developer mode are not required. Future updates
must retain the same signing certificate and use an increasing build number.

Windows: extract the entire x64 ZIP, close any older running copy, then run
`receipt_reader.exe`. OCR models and runtime dependencies are bundled. The Windows
executable is unsigned; this is an alpha evaluation package, not a certified release.

Keep independent encrypted backups. The app stores structured data outside the
program folder; an older executable may not open a migrated database or newer backup.
SQLite schema 9 and inner backups up to 6 require a compatible reader.

Known limits: camera capture, PC/phone synchronization, PDF/multi-image import and
in-app update checking are not implemented. Import a phone-camera JPEG/PNG instead.
OCR can miss or misread receipt content: review it even when totals match. Receipt
deletion retains historical data; it is not secure erasure. Real-phone acceptance,
manufacturer backup/transfer behavior and broader receipt layouts remain under test.

This workflow creates a draft pre-release. Publish only after the exact APK/ZIP
has completed the appropriate acceptance checks. Source is MIT; bundled third-party
components retain their own terms and notices.
