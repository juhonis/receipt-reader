# Finnish OCR regression corpus

## Scope and provenance

The November 22, 2026 milestone adds 23 invented Finnish receipt cases in
[`finnish_receipts.dart`](../packages/receipt_parser/test/fixtures/finnish_receipts.dart).
Source text, signed cents, quantities, rates, expected findings and unsupported
outcomes are hand-annotated. No receipt photographs, private OCR exports or
ignored `localreceipts/` files were read or copied for this milestone.

The parser suite runs each case in normal and reversed word order: 46 checks.
It checks ordered rows (including duplicates), amounts, kinds, quantities,
rounding, totals, exact findings/scopes, source coverage, layout proposals and
evidence readiness. Matching sums alone never approve a receipt. Deposit
relationships and final human approval remain separate prerequisites.

The corpus covers euro suffixes, annotated totals, card/cash/VAT boundaries,
weighed and counted multiplication, negative returns, deposit charges/refunds,
posted discounts and price explanations. It also checks ambiguous wrapping,
missing/corrupt prices, orphan quantities, quantity mismatches, competing totals,
decimal whitespace, independent digit runs, unknown footer text, unsupported
package units/currencies and an ambiguous Helsinki autumn clock time.

## Supported notation and review gates

- Posted amounts may end in an explicit `€` or `EUR`. A final standalone currency
  token may have a wider gap; this exemption never joins separate numeric runs.
- Exact total labels may have a colon or euro annotation, including
  `YHTEENSÄ:`, `YHTEENSÄ EUR` and `YHTEENSÄ (EUR)`. Existing limited diacritic
  aliases still require review. Parser and layout proposals share the same
  payment/VAT/footer vocabulary.
- Quantity/rate lines accept optional `x` or `×`, explicit matching `kg`, `kpl`
  or `l` units, and Unicode minus on returned quantities. Attachment is only to
  the immediately preceding product. Printed cents remain authoritative;
  quantity arithmetic is an independent check.
- A leading OCR en/em dash in a posted amount can propose a negative value,
  with `normalizedOcrAmount` attached to the original source evidence.
- Decimal-adjacent OCR whitespace in a complete quantity/rate line can be
  recovered with the same warning. Separate word fragments must be no farther
  apart than the smaller word height. Independent digit runs and distant decimal
  fragments remain unparsed and review-blocked.

Manual `parseCents`/`parseFixed` grammar is unchanged. Product names are never
rewritten. No missing digits, letters, unknown units, foreign currencies, competing
totals or financial adjustments are guessed. No schema, codec, dependency or
review-policy change was needed; the development parser compatibility tag remains
`receipt_parser/0.1.0`.

Nine new widget checks exercise the shared review flow. Three clean receipts save
the exact typed values through policy-3 quick review. Matching totals cannot
bypass quantity mismatches, unknown footer evidence, discounts or normalization
warnings. Deposits require explicit parent/standalone choices before saving.

## Actual engine checks

[`finnish_ocr_corpus_test.dart`](../integration_test/finnish_ocr_corpus_test.dart)
renders three source fixtures to in-memory PNGs, runs the installed native engine
and checks names, signed cents, quantities/rates/units, date, total, coverage and
unchanged source bytes. The renderer uses platform monospace fonts, so Windows
and Android receive platform-rendered versions of the source, not identical
pixels. These are recognition/parser tests; the new save checks use widget
fixtures, not a new native save/reopen test for every corpus case.

| Case | Expected financial result | Windows Tesseract | Android ML Kit |
| --- | --- | --- | --- |
| Repeated euro-priced products | MAITO 1.29 twice + LEIPÄ 2.49 = 5.07 | Pass, no findings | Pass, no findings |
| Weighed purchase | 0.750 kg × 1.89 = 1.42; receipt total 2.81 | Pass, no findings | Pass, no findings |
| Weighed return | −0.500 kg × 2.00 = −1.00; receipt total 1.40 | Pass with dash-normalization warning | Pass with split-decimal warning |

The real Windows output exposed a wider currency-symbol gap and a posted minus
read as `—1,00`. Android read the return's rate as the separate words `2,` and
`00`. The recovered values retain warnings and cannot take the clean quick-save
path until the evidence findings are explicitly reviewed. Expected financial
values were not changed to fit these outputs.

Six actual normalized word/geometry captures are retained in
[`native_tesseract.json`](../packages/receipt_parser/test/fixtures/native_tesseract.json)
and [`native_mlkit.json`](../packages/receipt_parser/test/fixtures/native_mlkit.json).
They contain only invented source words, geometry, backend and source PNG hashes;
they do not store parser-generated expected financial results. Eight captured-input
checks compare them with the hand annotations, verify the exact warning scopes,
reject a deliberately widened decimal gap and preserve strict manual parsing.
The native test logs `SYNTHETIC_CORPUS` records only for these invented inputs.

## Verification and reproduction

On November 22, 2026, all 122 parser, 67 domain, 196 storage and 159 app tests
passed. App/parser analysis and the four license-audit tests passed. All three
native cases passed on Windows and on the Android emulator in airplane mode.
Normal Windows Debug/Release and Android Debug builds were restored afterward;
the normal Android app was upgrade-installed without clearing data and the prior
airplane setting was restored. Windows Release notices and SQLite provenance
also passed the existing artifact audit.

From Windows PowerShell, with the configured emulator running:

```powershell
Push-Location packages/receipt_parser
dart analyze
dart test
Pop-Location
flutter analyze
flutter test
flutter test integration_test/finnish_ocr_corpus_test.dart -d windows
flutter test integration_test/finnish_ocr_corpus_test.dart -d emulator-5554 --no-uninstall
# Restore normal entry points after integration builds:
flutter build windows --debug
flutter build windows --release
flutter build apk --debug
```

Upgrade-install the normal Android APK with `adb install -r`, launch the ordinary
app and restore the emulator's previous airplane setting. Do not uninstall the
app or clear its data. The Windows development packager is described in
[Windows OCR](windows-ocr.md); build from a clean committed tree so its build
information identifies the exact source.

## Remaining evaluation

This corpus does not establish accuracy on real photographs, lighting, folds,
perspective, long/incomplete receipts, arbitrary store formats or other devices.
Unsupported units, complex offers and ambiguous source material remain review
work. Store/branch identity is still explicitly selected or created by the user.
Further representative photograph evaluation must remain local or use explicitly
anonymized inputs. Clean-machine acceptance, privacy/permission audits, native
picker verification and signing/distribution decisions remain open before release.
