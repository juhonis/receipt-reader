# Temporary manual receipt review

The home screen now opens **Kokeile kuitin tarkistusta**, a Finnish manual
review prototype shared by Android and Windows. Enter branch, printed date/time,
printed total, and signed financial rows. Add/remove rows and select product,
discount, deposit/return, or explicitly identified adjustment. All amounts use
the pure Dart parser's integer-cent rules.

The home-screen workflow has **no image import, database save, or history**.
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
block on unresolved parser issues. Quantity/rate editing, discount-parent
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
That initial synthetic fixture success did not demonstrate real-photo readiness.

### Skew and total-label follow-up

A subsequent run uses median local text-line slope to group words in projected
baseline coordinates, without modifying source boxes. It also accepts a limited
set of total-label diacritic variants and decimal-adjacent OCR whitespace, always
with review issues. Bonus/member/payment footer boundaries stop item parsing.
See [the algorithm and thresholds](parser-foundations.md).

With the same expectations and layout hints, the follow-up recognizes the printed
total in every existing baseline case. Some complete posted-amount sequences now
match, while other cases retain missing/corrupted rows and fail reconciliation.
Product names, quantities, and discount associations are still not fully verified.
A global slope cannot handle all folds or local perspective variation, and the
three-photo corpus is not grounds for a final engine choice.

Synthetic regressions cover skew in both directions, missing prices, sparse and
inconsistent slope evidence, total aliases versus product names, competing totals,
footer exclusion, and unsafe token merging. The report retains slope diagnostics;
all real inputs, reports, and expectations remain private.

Do not wire these drafts directly into an approved save workflow. Next work is
better section/column detection and local geometric ambiguity handling, followed
by review controls for OCR proposals. Retain uncertainty instead of choosing rows
merely to match a total. More varied receipt photos will be useful before engine
selection, but are not required to implement these deterministic safeguards.

### Layout proposals and OCR-seeded review

The private evaluator now records `automaticLayout` separately from the existing
manual-hint results. The conservative detector can propose boundaries when its
anchors agree, but abstains on most current baseline outputs due to split totals,
insufficient aligned amount words, or ambiguous geometry. Expectations are unchanged.
This is optional assistance, not general automatic receipt segmentation.

`ReviewPage(draft: ...)` now seeds names, signed amounts, row types, date and total
from an immutable parser draft. It shows original notes and Finnish issue messages.
Wrapped-name proposals have explicit accept/keep controls. Acceptance changes
only the name, preserves the amount, and resets review confirmation. Proposals
refer to original row objects so deleting another row cannot redirect acceptance.
Source quantities/rates remain in the original draft and cannot yet be edited.
The current suite passes 38 Dart tests and five widget tests, including draft
initialization, explicit name acceptance, and the OCR completion gate.

Every OCR-seeded session remains blocked from completion, including drafts whose
arithmetic matches. This intentional gate remains until image evidence, complete
issue resolution, and quantity/rate editing exist. There is no blanket “accept all
issues” action. Manual sessions still work as before. The home screen still opens
only manual entry; the draft constructor is an integration point exercised with
synthetic widget tests, not a new image import feature or embedded private sample.

Next work is temporary image import with receipt evidence beside editable rows,
followed by explicit correction and issue-resolution controls. Production OCR
engine packaging, clean-machine verification, and persistence remain open.
