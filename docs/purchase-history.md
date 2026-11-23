# Product purchase history and prices

Open **Tuotteet ja kuittinimet**, select a branch, and use the chart icon beside a
product. Tapping the product name still opens its reviewed catalog editor.
**Ostohistoria ja hinnat** lists explicitly linked product rows from that branch's
current, nondeleted receipts. Equal-name products remain independent identities.
Aliases suggest links during receipt review; they never add historical links.

Each page contains up to 30 product rows, including separate duplicate rows on the
same receipt. Filtering happens in SQLite before pagination. Ordering uses the
printed Helsinki civil date/time, receipt ID and original row position. A date-only
receipt does not acquire an invented time or UTC instant. Corrections replace the
current observation; unlinking or deleting removes it from this view. Earlier
snapshots remain in immutable storage and encrypted backups.

## Price policy

- Preserve the saved row amount, original/raw name, purchased quantity, reviewed
  unit price, and exact saved product revision. Show these beside the interpretation.
- Effective product cents equal the row amount plus its explicitly attached item
  discounts. An already-net row must not have the same discount recorded again as
  a financial line; the existing receipt review rules still apply.
- Show attached deposits separately and exclude them from product prices. A
  standalone deposit has no product attribution and remains visible on the receipt.
- Never allocate receipt-wide discounts or adjustments to products. Show a warning
  on affected observations and chart groups. Their prices are before these amounts,
  rather than claims about final checkout cost. Open the receipt for full context.
- Require a positive reviewed purchased quantity for a normalized price. Package
  metadata never supplies a missing quantity. Preserve missing-quantity rows in
  history without a normalized chart point.
- Returns (negative amount or quantity) remain visible but do not enter positive
  purchase comparisons. A negative effective amount is also excluded. A zero
  effective amount after item discounts is a valid free purchase.
- Keep kilograms, litres and pieces in separate comparison groups. Kilogram and
  litre prices compare the same explicitly linked product identity by purchased
  unit; no package-size conversion is inferred. Piece prices are additionally
  separated by the product revision saved with the receipt link. This conservative
  rule prevents a later package edit from silently changing an earlier basis, but
  also splits groups after a name-only edit. No cross-branch comparison is inferred.

Unit prices are exact rational cents per purchased unit. Comparisons and extrema
use BigInt cross multiplication, with no intermediate rounding or binary floating
point. Display rounds EUR/unit to four decimal places, half away from zero. The
saved reviewed rate remains separate: dividing the rounded line amount by quantity
may differ from that rate. Only relative chart coordinates use floating point,
computed after exact comparison and scaling.

## Date ranges, summary and charts

Use **Valitse aikaväli** to enter inclusive Finnish calendar days (1970–2099).
Either bound can be blank. Times, invalid calendar dates and reversed ranges are
rejected. Cancel keeps the existing selection; **Tyhjennä suodattimet** restores
all dates. Changing the range resets the receipt page and scrolls to the beginning.

The summary and charts cover **every matching product row across all pages**.
Detail rows remain paginated in groups of 30. Total rows partition exactly into
comparable rows, returns, missing-quantity rows and negative-effective-price rows,
in that priority order. A return without quantity counts as a return once.
Receipt-discount and adjustment warnings have separate, potentially overlapping
row counts. Product row subtotals include returns and linked item discounts where
labelled, but exclude deposits and unallocated receipt-wide amounts; these are
not whole-receipt spending totals. Unlinked rows never enter this product summary.

Each compatible group shows its exact count, minimum/maximum and quantity-weighted
average over the entire selected range. [Product trends](product-trends.md) add
first/latest-day comparisons and signed product-spending charts with interval
drill-down. The chart has at most 24 calendar intervals of approximately equal
length. Each nonempty interval shows its minimum and maximum as a vertical bar.
A circle marks the quantity-weighted average of actual purchases in each observed
interval. Empty intervals stay empty; there is no interpolation or inferred data. The
horizontal axis represents calendar days. Explicit date bounds set its extent;
an open bound uses the earliest/latest matching row, including excluded rows.
Expand **Jaksojen tarkat hinnat ja havaintomäärät** for accessible text containing
each nonempty interval's dates, displayed range, weighted average and observation
count.
The layout wraps on a 320 px screen with doubled text size.

No-data and no-comparable-data states are distinct. A single observation retains
its price and an explanation that a change cannot yet be assessed. Pagination
never narrows the summary or chart scope. **Avaa kuitti** opens the saved receipt,
including correction and deletion. Returning reloads the summary and detail page.
Refresh/retry/range changes clear obsolete results while loading.

## Consistency and resource bounds

The repository computes the full summary and detail page in **one read
transaction**. It scans matching current receipts by durable-ID keyset in batches
of 16, verifies canonical receipts through the existing read path, and feeds their
linked rows into an exact streaming accumulator. It does not collect the complete
receipt history in Dart or use a limited sample for counts and extrema. Pagination
and summary share the same branch/product/date predicates. Workspace calls use the
same queue as saves and backup activation, resolving the active database at execution.

The accumulator retains at most 64 comparison groups with 24 calendar buckets
each, first/latest-day aggregates per group and 24 overall signed spending buckets,
plus exact counts and BigInt subtotals. Details keep their existing
bounded page. More than 64 unit/revision groups fails the complete operation with
`purchaseGroupLimit`; the UI asks for a narrower date range and displays no partial
summary. Runtime still grows with matching history, so long ranges can take longer
to load. Every page/refresh recomputes the summary against its own consistent
snapshot instead of reusing a potentially stale total.

The feature remains read-only and adds no schema, event, backup-format or package
dependency changes. Flutter painting renders the small range chart. Only chart
coordinates use floating point; prices, extrema, bucket boundaries and counts use
integer/rational arithmetic.

## Verification

Run from Windows PowerShell with the configured Flutter/Dart SDK:

```powershell
flutter analyze
flutter test
Push-Location packages/receipt_domain
dart analyze
dart test
Pop-Location
Push-Location packages/receipt_storage
dart analyze
dart test
Pop-Location
flutter test integration_test/purchase_history_test.dart -d windows
flutter test integration_test/purchase_history_test.dart -d emulator-5554
```

If another Windows Debug build is running, use a temporary Flutter build directory
for the native test, then restore the previous configuration. Do not stop an existing
user session to unlock its executable. Android smoke testing can run in airplane
mode; restore the previous airplane setting and upgrade-install a normal debug APK
afterward. A normal Windows release build avoids locking an open Debug session.

Verified on November 17, 2026: clean app/domain/storage analysis; 132 app tests,
57 domain tests and 181 storage tests passed. The native workflow passed on
Windows and on the Android emulator in airplane mode, including date selection,
correction, encrypted restore, deletion and previous-dataset recovery.

The native test creates only a guarded `purchase-history-smoke-*` directory under
app support. It seeds synthetic linked purchases, checks the Finnish chart, inclusive date selection, complete summary and
read-only backup bytes, corrects a receipt, restores encrypted history while the
page is open, deletes an observation, reopens storage and recovers the previous
dataset. It never opens, clears or replaces the normal application dataset.
Domain tests cover discount/deposit separation, returns, missing quantity, unit and
revision groups, fractional-cent rates and values beyond double precision. Storage
tests cover filtering before pagination, duplicate rows, date precision, exact
financial rows, catalog edits, correction/unlink/deletion and reopen. Widget tests
cover navigation, charts, retry/loading, date validation/cancel/reset, full-range
pagination, exclusions, bucket text and narrow enlarged-text layout. Additional
summary tests cover 67 receipts across scan batches/pages, the 64-group guard,
calendar/leap/DST boundaries and aggregate cents beyond SQLite int64.

## Remaining work

[Receipt-level spending](spending-summary.md) now has a separate screen using full
receipt totals. Sync conflict exclusions once conflicts exist and production Windows
OCR packaging remain separate milestones. Package
conversions beyond the conservative price policy need their own explicit rules.
