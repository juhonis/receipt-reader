# Cross-store product prices

Implemented November 24, 2026 for identical products explicitly grouped by the
user. Different pack sizes can share a group when their contents are equivalent.
There is no automatic match based on product names or categories.

## Using the comparison

1. Open **Kuitit → Tuotteet ja kuittinimet**, select a branch and edit a product.
2. Set **Sama tuote · vertailuryhmä** to a descriptive group name. Give the same
   exact group name to the identical product in other branches. Review and save.
   For pack-count purchases, also review the package contents (kg, l or kpl).
3. Open a product's chart icon (**Ostohistoria ja hinnat**) and select
   **Hintavertailu toimipisteittäin**. Its selected date range carries over.

The comparison has a date filter, quantity-weighted average price bars ordered
from lowest to highest, and price trends with store colors. Kg, litres and pieces
remain separate. Select a chart interval or use its previous/next buttons to read
exact prices. It initially selects the latest interval with a comparable purchase.
Open a store bar to choose a member product's purchase history with the same dates.
The group's products and excluded-row counts are expandable; calculation rules
are behind the info button.

Group labels trim/collapse whitespace, are case-sensitive and allow at most 80
Unicode code points. Renaming or clearing a group changes only that product's
membership. It does not rename other products' groups. Membership uses current
reviewed product metadata, including for older explicitly linked purchases;
clearing the field removes that product from comparisons. Group edits require
catalog review and retain the existing retry/stale-save safeguards.

## Price policy

The average is the exact sum of effective purchased cents divided by the exact
sum of normalized purchased quantities. Item discounts follow their parent row.
For example, two 500 g packs at EUR 3 each and one 1 kg pack at EUR 5 contribute
EUR 11 over 2 kg, giving EUR 5.50/kg, rather than averaging pack prices.

- Purchases already recorded in kg or litres use that reviewed quantity directly.
- A purchased pack count is multiplied by package contents from the **exact
  product revision linked on that receipt**. A 500 g pack remains 500 g even if
  the current catalog package is later edited to 1 kg. Kpl package contents
  normalize multipacks to a reviewed per-item price.
- Missing purchased quantities are never filled from package metadata. Pack
  purchases without reviewed package contents are excluded from comparison.
  They remain visible in product history; explicitly reviewing a saved product
  link to a corrected product revision is a separate existing workflow.
- Returns and negative effective prices are excluded. Free purchases are valid.
- Deposits, receipt discounts and adjustments are not allocated to product
  prices. The coverage section retains receipt-discount/adjustment warnings.

Bars use a shared zero-based scale within each unit. Trend points show weighted
prices in at most 24 shared calendar intervals, with exact inclusive dates. Lines
only connect adjacent observed intervals; missing intervals remain empty. Prices
round to four euro decimals only for display. Amount/quantity accumulation,
sorting and conversions use BigInt/rational arithmetic, including up to twelve
quantity decimal places when purchased and package quantities multiply.

These are observed prices from recorded purchases, potentially on different days
at different stores. They do not establish current shop offers or complete price
coverage. Product identities, receipt amounts and original approvals stay separate.

## Storage and compatibility

Product payload v3 adds the optional explicit comparison key and preserves v1/v2
canonical bytes. SQLite schema 9 broadens the product-event version constraint;
existing receipt/catalog projections and events retain their values. Migration
from every released version 1–8 is atomic, including DDL/version rollback on
failure. Future schema versions are refused without resetting history.

Inner backup format 6 is required when history contains a product-v3 event, even
if its current group is later cleared. Older datasets retain their existing inner
format; formats 1–5 remain readable. Password-protected envelope v1 is unchanged.
Older app builds cannot open schema 9 or restore format 6: use this version or
newer on both computers after assigning comparison groups.

A single repository transaction reads current membership, verifies original
product revisions and scans every matching current receipt, independent of UI
pagination. Workspace operations share the existing save/restore queue. Catalog
and receipt scans use bounded keyset batches; package revisions use a 128-entry
LRU. A group supports at most 64 products and 64 store/unit series, with 24 trend
buckets each. Overflow rejects the complete result rather than showing partial
comparisons. No new packages, network permissions or SDK upgrades are required.

## Verification

Full regressions passed: 232 app, 136 domain and 238 storage tests. Final focused
checks also cover the added bounds tests and interval controls: seven domain,
three storage and five widget cases. Flutter analysis is clean. Checks include
exact package conversions, historical package edits, discounts/returns/missing
quantities, free prices, shared buckets with gaps, full scans across batches,
read-only exports, group edit/clear, backup round trips, range-scoped history,
retry, and 320px layouts with doubled text.

Native Windows and offline Android rehearsals passed, and their screenshots
were visually checked. The native rehearsal uses only a guarded `product-comparison-smoke-*` temporary
workspace. It exercises actual home/catalog/history navigation, price bars/trends,
date filtering, source history, encrypted backup activation while the page is
open, unchanged recovered export bytes, and reopen. The existing user dataset and
private receipt images are never test inputs.

```powershell
flutter analyze
flutter test
flutter test integration_test/product_comparison_test.dart -d windows
# Run Android offline and restore its previous airplane setting afterward:
flutter test integration_test/product_comparison_test.dart -d emulator-5554 --no-uninstall
```

After native tests rebuild the normal Windows Debug/Release and Android Debug
entry points. Android upgrades use `adb install -r`, never uninstall or data clear.
Both normal apps were rebuilt and reopened with existing sample data retained.
Windows and Android debug/release builds passed, as did release notice/provenance
audits, Android offline-permission checks and the four notice-tooling tests.
