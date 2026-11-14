# receipt_parser

Pure Dart receipt parsing and exact financial validation. Experimental;
the Flutter app does not depend on it yet.

See [scope, numeric rules, and limitations](../../docs/parser-foundations.md).

```powershell
dart pub get
dart analyze
dart test
```

Read normalized OCR using `OcrPage.fromJson`, then call `parseReceipt` with
explicit `itemTop` and `priceColumnLeft` pixel hints. Inspect both `draft.totals`
and `draft.issues`, plus the independent `draft.date` state and optional
`draft.wrappedNames` proposals. Helsinki timezone rules are bundled locally.
Every draft still requires user review; arithmetic matching
does not establish transcription accuracy or permission to save.
