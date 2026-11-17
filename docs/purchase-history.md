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

## Chart scope and accessibility

Charts, counts, minima and maxima cover **only the visible page**, explicitly
labelled in Finnish. Each compatible group has its own range. The horizontal axis
is observation order, oldest first, with equal spacing; it does not represent
elapsed time. Date labels retain available precision. A single observation shows
its value and an explanation that a change cannot yet be assessed. Exact prices
and full observation details remain available as text independently of the drawing.
The layout wraps on a 320 px screen with doubled text size.

**Avaa kuitti** opens the existing saved-receipt view, including correction and
deletion. Returning reloads purchase history. Refresh and retry use a fresh bounded
query and clear obsolete charts while loading. All workspace reads share the queue
used for saves and backup activation, resolving the active repository when executed.
The feature is read-only and introduces no schema, event, backup-format or dependency
changes. The initial small chart uses Flutter painting rather than adding fl_chart;
a future interactive date-range chart can revisit the library choice.

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

Verified on November 17, 2026: clean app/domain/storage analysis; 129 app tests,
51 domain tests and 178 storage tests passed. The native purchase-history workflow
passed on Windows and on the Android emulator in airplane mode.

The native test creates only a guarded `purchase-history-smoke-*` directory under
app support. It seeds synthetic linked purchases, checks the Finnish chart and
read-only backup bytes, corrects a receipt, restores encrypted history while the
page is open, deletes an observation, reopens storage and recovers the previous
dataset. It never opens, clears or replaces the normal application dataset.
Domain tests cover discount/deposit separation, returns, missing quantity, unit and
revision groups, fractional-cent rates and values beyond double precision. Storage
tests cover filtering before pagination, duplicate rows, date precision, exact
financial rows, catalog edits, correction/unlink/deletion and reopen. Widget tests
cover navigation, charts, retry/loading, pagination and narrow enlarged-text layout.

## Remaining work

Add date-range summaries and charts spanning all selected observations, with a
bounded aggregation strategy and clear treatment of missing/comparable observations.
Package-based conversions beyond the rules above need their own explicit policy.
Broader spending analytics, sync conflict exclusions once conflicts exist, and
production Windows OCR packaging remain separate milestones.
