# receipt_storage

Drift/SQLite repository for reviewed local manual receipts. The Flutter app
depends on the package for native packaging checks but does not open a database
or offer saving yet. See [storage implementation](../../docs/local-storage.md)
and the [contract](../../docs/local-storage-contract.md).

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
