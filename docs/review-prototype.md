# Temporary manual receipt review

The home screen now opens **Kokeile kuitin tarkistusta**, a Finnish manual
review prototype shared by Android and Windows. Enter branch, printed date/time,
printed total, and signed financial rows. Add/remove rows and select product,
discount, deposit/return, or explicitly identified adjustment. All amounts use
the pure Dart parser's integer-cent rules.

This screen has **no image import, OCR population, database save, or history**.
It starts empty and holds input only in widget/controller memory. Returning to
the home screen discards it. The screen explains this before data entry and its
completion message explicitly says nothing was saved. It is not a backup or
durable draft. Process termination also loses the session.

## Independent checks

- A nonempty branch and explicit branch confirmation are required. Editing the
  branch clears that confirmation. This is manual branch identification, not
  catalog resolution.
- The printed date/time must be valid under the parser's Helsinki rules. DST
  ambiguity, clock gaps, and unsupported timezone ranges remain unresolved.
  The prototype does not yet offer selection of a repeated-hour UTC candidate.
- At least one named row is required. Every row amount and the printed total
  need two decimal digits. Negative purchases/returns and deposits are preserved.
  Discount rows must be negative; already-net discounts must not be added twice.
- All rows must parse before a matching sum can be displayed. A matching partial
  sum cannot conceal a malformed row. Differences have no tolerance.
- A separate review checkbox is required. Editing any field, changing a row
  type, adding/removing a row, or changing branch confirmation clears it.

`ReviewValidation.complete` means only that this manual prototype's checks pass.
It is not permission for a persistence layer to save. The validator can also
block on unresolved parser issues, but this screen currently takes manual input
only. Quantity/rate editing, wrapped-name proposal acceptance, discount-parent
relationships, OCR-side evidence, and full persistence invariants remain open.

Widget tests exercise correction resetting review, ephemeral route lifecycle,
row addition/removal, and a 320-pixel layout with doubled text size. Pure Dart
tests cover partial-sum failures, review/branch requirements, ambiguous dates,
signed returns, discount signs, and amount formatting.

Verified on 2026-11-15: 28 pure Dart tests and four Flutter widget tests pass;
package/app analysis is clean. The debug app built, installed, and launched on
the restarted API 36 Android emulator, where the manual review screen was
visually inspected. The Windows debug build also succeeds; this turn did not
repeat an interactive Windows desktop smoke test.

## Private OCR evaluation

Run from the repository root with Windows Dart:

```powershell
dart run packages/receipt_parser/bin/evaluate_private.dart localreceipts/ocr
```

The command requires existing baseline engine outputs, private `expected.json`,
and private `parser-hints.json`. Hints are keyed by anonymous sample ID and contain
`inputSha256`, `itemTop`, and `priceColumnLeft` in prepared-image pixels. This run
used the previously annotated first price region for both boundaries (item top
minus ten pixels); the hints were held constant across engines. The runner checks
the recorded input hash against each hint and excludes transformed variants.
It does not rehash image files or claim that layout hints are automatically found.

The local report is `localreceipts/ocr/parser-report.json`. It records ordered
posted amounts, printed total/date comparisons, parsed rows, notes and warnings.
These checks do not verify product identity or all quantity/discount semantics.
No receipt text, financial values, image, hint file, or report is committed.

The initial run evaluated fifteen baseline outputs from three private photos.
No case reproduced the complete expected posted-row sequence. The photos expose
skew between description and price columns that exceeds the current horizontal
band heuristic; OCR also splits decimal tokens and misreads total-label diacritics.
Consequently some totals remain missing and footer material can reach unclassified
notes. A manually supplied price boundary can also split long descriptions.
The current synthetic fixture success does not demonstrate real-photo readiness.

Do not wire these drafts directly into an approved save workflow. Next work is
geometry-aware skew handling with synthetic regressions, guarded total candidates,
and better section detection, followed by local reevaluation using unchanged
expectations. Retain uncertainty instead of choosing rows merely to match a total.
