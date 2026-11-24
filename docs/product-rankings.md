# Product spending rankings on the dashboard

Implemented November 24, 2026 for offline Windows and Android use.

## Find products from Seuranta

The **Mihin tuotteisiin rahaa kuluu?** section uses the dashboard's week, month,
year or custom range and selected branch. It shows up to ten products by descending
signed net euros, followed by the exact net remainder for all other linked products.
Choose **Näytä kaikki tuotteet** for the full list in pages of 30. Pagination only
limits visible rows; totals and ranking cover the complete selected range.

Every product shows its current reviewed catalog name, branch/location, a short
identity suffix, net amount, product-row count, distinct receipt count and return-row
count. Return-row net amounts remain explicit. Bars share one scale, with negative
nets extending left of zero. Zero and refund-only products remain in the full list.
Ties use the current name, branch identity and product identity deterministically.

Choose any product to open **Ostohistoria ja hinnat** with its exact branch/product
identity and the displayed dashboard's inclusive dates. This works from both the
top ten and the full list. Product history starts on its first receipt page; its
existing date controls can deliberately expand or change that scope. Returning
reloads the rankings after linking, unlinking, corrections or deletion.

## Money and coverage rules

A product's net equals all its explicitly linked product-row amounts plus attached
item discounts. Returns and rows without quantities contribute, as do negative nets
caused by item discounts. A negative net does not by itself invent a return. Duplicate
rows count separately, while one receipt contributes only once to that product's
receipt count. Different products can legitimately share a receipt.

Amounts from different recorded revisions of the same product identity combine for
spending. This does not infer quantity or price equivalence: the price-history view
retains its existing unit/revision comparison rules. Equal names never merge product
identities or branches. There is no automatic cross-store matching, alias acceptance,
package conversion or new historical linking.

Coverage shows linked product rows against all selected product rows. Linked and
unlinked product nets are separate, including their attached discounts. Deposits,
receipt-wide discounts and adjustments remain separately labelled and unallocated.
These components reconcile exactly to the dashboard's full receipt total; the top-ten
remainder is a subset of linked product spending, not a whole-receipt residual.
Current catalog names affect labels/tie order without rewriting receipt documents.

## Snapshot, limits and navigation

The existing complete dashboard scan supplies rankings, categories and financial
statistics within one verified read transaction. Current product metadata is resolved
in that transaction through a bounded 128-entry cache. The streaming ranking keeps
at most **2048** branch/product groups with counts, BigInt amounts and label metadata;
it never retains a complete receipt collection per group.

Above 2048 groups the complete ranking is withheld and its partial groups discarded.
Coverage and all financial totals continue consuming every selected row. The rest of
the dashboard stays available; narrow the branch/range to recover a complete ranking.
Existing separate branch/category guards retain their prior behavior. No sample or
silently truncated product list is shown. Aggregate arithmetic can exceed SQLite
int64 without overflowing; only scaled bar coordinates use floating point.

The full list initially reuses the dashboard snapshot. Refresh and returning from a
product read a fresh complete snapshot with the list's original inclusive dates and
branch. Product history reads current receipts and fresh product metadata; it is not
an immutable historical view. Opening validates both product and branch identity,
ignores late metadata after scope changes, tab/route changes or disposal, and reports load failures without
navigating to a different product. Failed list refreshes clear stale entries and allow
retry. All workflows use the existing workspace queue with backup activation.

The feature is read-only. Schema 8, receipt/event/review formats, structured backups
and the password-protected envelope are unchanged. No dependencies or SDKs changed.

## Verification

Verified November 24: **125 domain, 228 storage and 216 app tests** pass with clean
Flutter analysis. Notice auditing and its four Python tests pass. Domain checks cover
all row kinds, reconciliation, identities, revision grouping, ties, returns/zero nets,
large sums, 2048-group overflow and every dashboard date mode. Storage checks cover
67 receipts across scan batches, branch isolation, metadata cache eviction, current
catalog names, read-only export bytes, unlink/deletion, reopen and encrypted restore.

Widget tests cover all four date modes and exact product navigation, top ten/remainder,
full-list paging, equal names at different branches, metadata failure/mismatch, delayed
obsolete navigation, refresh/retry, limit handling and 320px enlarged text.

Native Windows and Android airplane-mode tests use only a guarded
`product-rankings-smoke-*` dataset with invented receipts. They check 33 ranked products,
full-list paging, inherited dates and price summaries, duplicate rows/returns, branch
selection, a refund-only custom day, unlink/refresh, protected recovery while the
screen is open, unchanged receipt/backup bytes and reopen. Windows screenshots were
visually checked. Normal user data and private receipt images are not test inputs.

```powershell
flutter analyze
flutter test
flutter test integration_test/product_rankings_test.dart -d windows
flutter test integration_test/product_rankings_test.dart -d emulator-5554
```

Run Android native checks offline and restore its prior airplane setting. Rebuild
normal Windows Debug/Release and Android Debug afterward, then upgrade-install with
`adb install -r` and launch the normal Android app. Never uninstall or clear user data.
