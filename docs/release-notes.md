# v0.2.0-alpha.8

Improves receipt recognition and review. Split price tokens now help automatic
layout detection and preserve printed amounts. Known header notices and payment
details no longer create unrelated product warnings; uncertain receipt content
still needs review.

Header text now recommends a Toimipiste and selects an existing branch only when
there is one exact normalized-name match. Ambiguous matches require a choice;
manual choices are preserved, and recognition never creates a branch by itself.

Product rows offer **Ehdota nimeä tai tuotetta** from the selected branch's catalog.
Use a suggested name or link a product explicitly. Name corrections retain original
OCR evidence and financial values. Unknown names still need manual correction;
suggestions never create aliases or merge products automatically.

Includes alpha.7's release-mode OCR startup fix. This is Android build **9** with
the same permanent signing certificate. Install over the existing release alpha
to retain receipts and catalog data. No database or backup format changes from
alpha.7. Before updating, keep an independent encrypted backup.

Includes **Ota kuva** on Android: photograph receipts inside the app without creating
gallery or temporary image files. The picture stays in memory during OCR/review
and is released on save/cancel. Camera access is requested only when capturing;
storage and internet permissions are not added. Keep the paper receipt if you may
need to re-scan it. Existing gallery import remains available.

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

Known limits: PC/phone synchronization, PDF/multi-image import and
in-app update checking are not implemented. Capture one complete receipt at a time.
OCR can miss or misread receipt content: review it even when totals match. Receipt
deletion retains historical data; it is not secure erasure. Real-phone acceptance,
manufacturer backup/transfer behavior and broader receipt layouts remain under test.

This workflow creates a draft pre-release. Publish only after the exact APK/ZIP
has completed the appropriate acceptance checks. Source is MIT; bundled third-party
components retain their own terms and notices.
