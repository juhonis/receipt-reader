# receipt_storage

Drift/SQLite repository for reviewed local manual and supported OCR receipts.
The Flutter app owns an application-support database and provides explicit saving
and read-only history with validated branch/date/exact-cent filters. See the
[filter contract and native checks](../../docs/history-filters.md). Schema 4 migrates released schemas 1/2/3 without rewriting
event history. [Store-scoped products and aliases](../../docs/product-catalog.md)
provide catalog revisions, exact suggestions and encrypted recovery; receipt-link
review UI remains pending. See [storage implementation](../../docs/local-storage.md),
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
