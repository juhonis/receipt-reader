# receipt_parser

Pure Dart receipt parsing and exact financial validation. The Flutter app uses
its numeric/date rules and geometry-backed drafts in reviewed manual/OCR workflows.
Native recognition and persistence live outside this package. Broader real-photo
recognition coverage remains open; every receipt still requires review.

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
