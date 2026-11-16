# receipt_domain

Pure Dart storage-facing receipt values and manual review commands. Experimental;
the Flutter app does not use this package yet. There is no database or save UI.

See [storage foundations](../../docs/storage-foundations.md) for the API boundary,
canonical fixtures, checks performed, and remaining work. The
[storage contract](../../docs/local-storage-contract.md) specifies the intended
Drift repository and eventual recovery/sync behaviour.

```powershell
dart pub get
dart analyze
dart test
```

The package depends on the shared parser's financial and Helsinki date rules,
not Flutter, SQLite, native OCR, or image libraries. Use Windows-native Dart in
this shared checkout; WSL remains suitable for Git.
