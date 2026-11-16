# receipt_domain

Pure Dart storage-facing receipt values and source-specific review commands.
The Flutter app uses them for manual and supported OCR saving through the local
repository. See [reviewed OCR saving](../../docs/ocr-saving.md) for policy 2.

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
