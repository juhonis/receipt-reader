# receipt_storage

Drift/SQLite repository for reviewed local manual and supported OCR receipts.
The Flutter app owns an application-support database and provides explicit saving
and read-only history. Schema 2 migrates released manual data without rewriting
its event history. See [storage implementation](../../docs/local-storage.md),
[OCR saving](../../docs/ocr-saving.md) and the [contract](../../docs/local-storage-contract.md).

Run with Windows-native Dart:

```powershell
dart pub get
dart test
dart analyze
```

After changing the schema, regenerate and check the migration baseline:

```powershell
dart run build_runner build
dart run drift_dev make-migrations
dart run drift_dev schema generate schema/receipt_database test/generated
```

Commit schema source, generated database code, versioned schema snapshots and
migration helpers together. Future changes require a new schema version and a
tested transactional migration; never replace a released baseline to hide drift.
