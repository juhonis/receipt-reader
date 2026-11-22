# Receipt spending summaries

For weekly/monthly charts, period comparisons and receipt drill-down, use the
separate [spending dashboard](spending-dashboard.md). This page describes the
original full-range summary screen and its existing rules.

The Finnish **Kulutus** action opens receipt-level totals from the **Kuitit** tab on
Android and Windows. This is separate from the catalog's product purchase prices.
Use **Toimipiste ja aikaväli** to select a branch and optional first/last day;
**Tyhjennä suodattimet** restores all stored reviewed receipts. Refresh reloads the
current dataset, including after corrections, deletion or backup activation.

## What the amounts mean

Every current, nondeleted reviewed receipt contributes its reconciled
totalCents exactly once. Product links and purchased quantities are not required.
The receipt total already includes product rows, deposits, item/receipt discounts,
returns and reviewed adjustments. The summary never adds those rows again and
never sums the linked product-price observations.

Amounts use signed integer cents throughout, with BigInt accumulation even when
the sum exceeds SQLite int64. Negative receipts reduce the net total; zero receipts
remain in the count. A negative-receipt count describes whole receipts with negative
final totals, not the number or gross value of individual returns. Mixed receipts
can contain return rows while retaining a positive final total.

The screen gives the selected total and receipt count, then expandable branch and
calendar-month breakdowns with exact amounts and the same receipt-level counts:

- Receipts with a negative final total.
- Receipts containing at least one reviewed adjustment.
- Receipts containing at least one product row without a catalog link. Those rows
  are fully included in spending; this count describes catalog coverage.

Counts can overlap. They are not additional financial amounts or exclusions.
Only receipts stored in this dataset are known: totals do not establish all actual
spending. Missing calendar months are absent rather than claimed as zero spending.
There is no average, interpolation, currency conversion or product-unit comparison.
Unresolved sync conflicts are not implemented yet; conflict exclusions will be
needed when that feature exists.

## Dates and branch identity

Bounds are inclusive printed Helsinki calendar days with day precision. A receipt
at 23:59:59 on the last selected day is included, and date-only receipts do not gain
an invented UTC instant. Blank bounds remain open. Month groups follow the printed
year/month and appear newest first; branch selection also filters these groups.

Branches group by durable ID, so equally named branches never merge. The displayed
branch label comes from the newest selected receipt day, with receipt ID breaking
same-day ties deterministically. Historical snapshot labels can therefore differ
from current catalog labels. Branches sort by label and then ID.

## Read consistency and bounds

ReceiptSpending.spendingSummary reads all matching current receipt IDs in keyset
batches of 16 inside one database transaction. Each receipt goes through the same
canonical-document, event and projection integrity checks as receipt detail.
There is no 30-row history limit or SQLite integer SUM. HistoryFilter is reused;
the spending screen exposes only branch/day bounds, while the service also honors
any exact receipt-amount bounds provided by another caller.

The fold retains totals for at most 128 branches and 1560 months (the supported
1970–2099 civil-date span), plus branch labels, not receipt rows. Exceeding a bound
fails the entire summary. The UI asks for a narrower selection for the branch
limit and never shows partial results. Database/integrity failures also hide all
totals and offer retry. A pending refresh clears the previous total.

RepositoryStore and WorkspaceStore expose a separate SpendingService. Workspace
reads use the existing serialization queue and resolve the active repository
inside the queued closure, so an encrypted dataset replacement cannot leave a
queued spending read pointing at the previous database. No migration, dependency,
network request, stored aggregate or financial-data rewrite is introduced.

## Verification

Run from the repository root, using the Windows Flutter toolchain:

    flutter analyze
    flutter test
    flutter test integration_test/spending_test.dart -d windows
    flutter test integration_test/spending_test.dart -d emulator-5554

Run dart test and dart analyze separately in packages/receipt_domain and
packages/receipt_storage. When normal Windows Debug apps are already running,
use a temporary Flutter build-dir for the native test and restore its prior
configuration afterward; see [Windows development](windows-development.md).

The native test uses only a guarded spending-smoke-* application-support directory
and synthetic receipts. It checks more than one history page, complete mixed-row
amounts, branch/inclusive-day filtering, read-only export bytes, correction,
encrypted activation with a queued read while the page remains open, deletion,
reopen and previous-dataset recovery. It never opens or clears the normal dataset.
Android verification runs in airplane mode and restores the previous setting.

Domain/storage/widget coverage includes leap-day month boundaries, empty and
immutable output, signed zero/negative receipts, equal-name branch separation,
sums beyond int64, mixed deposits/discounts/returns/adjustments, corrections and
tombstones after reopen, corruption rejection, the branch group guard, stale-total
clearing, retry, invalid date ranges and a 320px layout at doubled text size.

Verified on November 17, 2026: 136 app tests, 59 domain tests and 186 storage tests,
with clean analysis in all three packages. The synthetic native spending workflow
passed on Windows and on the Android emulator in airplane mode.
