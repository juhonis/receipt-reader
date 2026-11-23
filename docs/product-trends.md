# Product prices and spending trends

Implemented November 24, 2026 in **Ostohistoria ja hinnat** on Windows and Android.
From Kuitit, open **Tuotteet ja kuittinimet**, choose a branch and use the chart icon
beside a product. Select inclusive dates with **Valitse aikaväli** or keep all dates.
All statistics cover every matching current linked purchase, across receipt pages.

## Weighted prices and day comparisons

Each existing compatible price group now shows its quantity-weighted average:

    sum(product row cents + attached item discount cents) / sum(purchased quantity)

For example, one unit at EUR 1 and three units at EUR 3 produce EUR 2.50/unit,
not the EUR 2 average of those two row prices. Fixed quantity scales combine
exactly before division. Only comparable purchases contribute: returns, missing
quantities and negative effective prices remain excluded. Free purchases are
valid. Deposits, receipt-wide discounts and adjustments remain unallocated and
excluded, with existing warnings retained.

Pieces, kilograms and litres remain separate. Piece prices additionally retain
the product revision explicitly recorded on each receipt. Equal names do not
merge products, and no cross-branch equivalence or package conversion is inferred.
See [purchase-history price policy](purchase-history.md#price-policy).

The first and latest **purchase days** each combine all that day's comparable
purchases with the same quantity weighting. Arrival order, duplicate rows,
receipt IDs and absent times cannot arbitrarily select a different endpoint.
The displayed percentage compares these two exact daily prices. It is not a
comparison of period spending, an inflation index or a forecast.

At least two distinct comparable days are required. A truly zero first-day price
has no percentage change; a positive baseline followed by a free day gives -100%.
A small positive price that rounds to zero for display remains a valid baseline.
Prices round to four EUR decimals, and percentage changes to tenths of a percent,
half away from zero. No displayed rounded price is reused in the calculation.

The existing min/max interval chart now adds a circular weighted-average marker
for each observed interval. Empty price intervals remain empty; no lines connect
or interpolate missing purchases. Expanded interval details retain exact displayed
min/max values and counts and add the interval's weighted average.

## Product spending over time

**Tuotteen ostomenot ajan mittaan** shows signed product subtotals over the same
selected range. These include all explicitly linked product rows, attached item
discounts, returns, missing quantities and negative effective amounts. They exclude
deposits and unallocated receipt-wide amounts, so they are not whole-receipt totals.
Spending buckets reconcile exactly to the existing effective product subtotal.

The range partitions into at most 24 consecutive calendar-day intervals. These
intervals do not necessarily match calendar weeks or months; every interval's
actual bounds are available in **Jaksojen ostomenot ja ostorivit**. Positive bars
rise above zero and negative bars fall below it. Text lists signed amounts, row
counts and return-row counts. An observed zero subtotal remains distinct from an
interval with no linked purchases.

Choose a populated interval to scope the same product history to its inclusive
dates. This resets receipt pagination and scrolls to the range summary. All totals,
price groups, comparisons and receipts reload together. An empty interval cannot
be opened. Clearing the date filter restores all dates.

## Consistency and compatibility

The existing one-transaction repository scan feeds both old and new statistics;
no sampled page or additional read supplies a competing total. Workspace operations
remain serialized with saves and backup activation. The accumulator retains at
most 64 price groups with 24 price buckets per group, two endpoint-day aggregates
per group, and 24 overall spending buckets. Every matching row contributes, and
the existing group limit still rejects the complete result rather than truncating.
Integer/rational BigInt sums support aggregate quantities and amounts beyond int64;
only scaled chart coordinates use floating point.

The feature does not change receipt bytes, catalog records, schema 8, event/review
formats, inner backup versions or the encrypted envelope. No dependencies or SDKs
were upgraded. Linking, unlinking, correcting or deleting receipts changes the next
read; refreshing after encrypted recovery uses the restored current dataset.

## Verification

Verified November 24: clean Flutter analysis; **113 domain, 222 storage and 201 app
tests** pass. Domain cases cover quantity weights/scales, day ties and input order,
zero baselines, exact percentages before display rounding, signed exclusions,
unit/revision separation, empty/zero periods, calendar partitions and large sums.
Storage tests cover 67 rows across scan batches/pages, unchanged exported bytes,
unlink/deletion, reopen and encrypted recovery. Widget tests cover formatting,
interval drill-down/reset, pagination, free-day notices and 320px enlarged text.

Native Windows and Android airplane-mode checks pass using only guarded
`product-trends-smoke-*` directories with invented data. They exercise both charts,
exact signed spending, interval drill-down, read-only receipt/backup preservation,
refresh after unlinking, protected recovery while the page is open and reopen.
Windows screenshots were visually checked. Notice auditing and its four Python
tests pass. Private receipt images and normal user datasets are not test inputs.

```powershell
flutter analyze
flutter test
flutter test integration_test/product_trends_test.dart -d windows
flutter test integration_test/product_trends_test.dart -d emulator-5554
```

Run Android native tests offline and restore its prior airplane setting. Rebuild
normal Windows Debug/Release and Android Debug entry points afterward. Install
Android updates with `adb install -r`; never uninstall or clear normal app data.
