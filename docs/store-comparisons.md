# Store spending comparisons

The **Toimipisteiden vertailu** section in **Seuranta** follows the dashboard's
selected week, month, year or custom range and its branch filter. It uses complete
current reviewed receipt totals, including unlinked products, deposits, discounts,
returns and reviewed adjustments. It requires no product categories or links.

## Charts and receipt links

The horizontal bars share one signed scale: positive store nets extend right
from zero and negative nets extend left. Every selected branch appears, including
branches whose receipts cancel to zero. Cards show exact net cents, receipt count,
rounded average receipt value and negative-final-total receipt counts when present.
Branches sort by descending net, then name and durable ID.

The donut uses **only positive branch net totals** as its denominator. Zero and
negative branch nets are excluded from its slices and the negative branch-net
subtotal is displayed separately. For example, store nets of +8 €, +2 € and −1 €
give a dashboard net of 9 €, a positive denominator of 10 €, and shares of 80% and
20%. Returns within the +8 € store already reduce that store's net. The donut is
not gross purchases, gross refunds, or shares of the overall signed dashboard net.

The eight largest positive nets have separate slices. Remaining positive branches
are grouped as **Muut**, retaining their exact combined amount. Opening Muut
shows the constituent branches and lets the user explicitly choose one, even when
only one branch was grouped. It never invents an Other branch or merges identities.
If there are no positive nets, the donut is replaced by an explanation; signed
bars and statistics remain available. Empty selections have a separate no-data state.

Pressing a bar, donut slice or legend entry opens receipt history for that branch
and the **entire selected dashboard range**, rather than a chart's daily bucket.
History retains pagination, corrections and deletion. Returning refreshes all
dashboard results. Legend buttons provide keyboard/accessibility alternatives to
touching arcs, and exact amounts and percentages remain text. Donut percentages
round to one decimal, halfway away from zero; very small nonzero shares display
`<0,1 %`. Independently rounded percentages need not add to exactly 100%.

## Identity, arithmetic and consistency

Branches group by durable ID. Equal names remain separate. The label/address is
from the newest selected receipt's printed calendar day, with receipt ID breaking
same-day ties. Comparison-period and future receipts never influence store labels
or store totals. Store net totals and receipt counts reconcile exactly to the
selected dashboard totals; positive plus negative branch nets also reconcile.

The dashboard and original full-range spending summary share a branch-fold helper.
Amounts, rankings, averages and percentage arithmetic use `BigInt`; only bounded
relative drawing coordinates use floating point. The chart, store folds, selected
total and period comparisons share the existing verified read transaction and
workspace queue. No second database read or paginated-history sample supplies
these charts. No schema, dependency, backup-format or saved-data change is needed.

At most 128 **selected** branches are retained. Exceeding that bound fails the
entire dashboard with a localized request for a narrower branch/date selection;
no partial monetary output is shown. Comparison-only branches do not consume the
selected-branch bound. The donut draws at most nine segments; all selected branches
remain in the signed-bar/statistics list and Muut keeps its exact membership.

## Verification

Verified on November 23, 2026: 123 parser, 86 domain, 200 storage and 174 app
tests passed, with clean analysis. Native Windows and offline Android dashboard
rehearsals passed; Windows store charts were visually checked using synthetic
data. The dependency-notice audit and its four Python tests also passed.

Run the normal app/package suites and analysis, then:

```powershell
flutter test test/store_spending_test.dart
flutter test integration_test/spending_dashboard_test.dart -d windows
flutter test integration_test/spending_dashboard_test.dart -d emulator-5554 --no-uninstall
```

Synthetic domain/storage tests cover selected-range reconciliation, netting,
same-name identities, deterministic label ties, immutable results, values beyond
double precision, all batches, corrections/deletion/reopen, corrupt projections
and branch-limit refusal/filter recovery. Widget tests exercise signed and zero
nets, slice taps, grouped-store choice (including a single grouped store), empty
selections, failed-load recovery and 320px layouts at doubled text size.

The native rehearsal uses only its guarded `dashboard-smoke-*` dataset. It checks
multiple positive/negative store nets, a share-to-receipt link and the exact store
aggregates after protected restore with a queued read, deletion, reopen and
previous-dataset recovery. Windows chart screenshots use invented receipts only.
Native tests preserve normal user data; normal build entry points and the prior
Android airplane setting are restored afterward.
