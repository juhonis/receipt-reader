# Spending dashboard and home tabs

The home screen has two destinations. **Seuranta** opens the
**Viikko- ja kuukausiseuranta** dashboard by default. **Kuitit** contains image
import, manual entry, receipt history/corrections/deletion, product/alias management
and backups. The existing **Kulutus** full-history summary remains in that
management area. Software information remains available from the app bar.

Both tabs work offline on Android and Windows. Switching tabs preserves the
dashboard's period/branch selection and scroll position; returning to Seuranta
reloads current totals. An unavailable dataset opens receipt recovery instead
and disables analytics until recovery is complete. The no-storage development
harness retains receipt review, with analytics disabled.

## Navigation and charts

- Select **Viikko**, **Kuukausi**, **Vuosi** or **Oma aikaväli**. Weeks run
  Monday–Sunday; months and years follow the Helsinki calendar. The default is
  the current month, independently of the computer's timezone.
- Use the arrows or calendar picker to visit earlier periods. **Nykyinen jakso**
  returns to the current calendar period (or the current month from a custom
  range). Future periods cannot be selected.
- Custom ranges require two valid, inclusive dates in `p.k.vvvv` format. Blank,
  timestamp, reversed and future bounds are rejected. Cancel preserves the
  current selection. The date button reopens the custom-range editor.
- Filter by one branch or all branches. Branches retain their durable identities;
  equally named branches do not merge.
- The period tabs stay at the top. Branch and date navigation share a compact
  row on desktop, or two rows on phones. Click the date itself to edit it;
  the today and refresh icons have tooltips.
- **Jakson nettokulutus** comes first, with the signed euro/percentage change
  and previous comparison total immediately below. Receipt count opens history;
  the average remains in the same compact card. The info button gives exact
  comparison windows, coverage rules and links to both comparison receipt lists.
- **Kulutuksen jakauma** follows immediately. **Tuotteet** is the default;
  **Toimipisteet** switches the same chart to stores. The choice survives filter
  changes. Product slices use only positive linked product nets after item
  discounts: the five largest plus **Muut**. Negative nets and unlinked amounts
  stay separately visible; deposits, receipt-wide discounts and adjustments
  remain in the headline receipt total but do not enter product slices. The
  denominator is labelled, and the info button explains the difference.
  Store mode uses positive whole-receipt branch nets, with eight slices plus
  **Muut**. Slice/legend buttons open the scoped product history or branch receipts;
  Muut asks which member to open. Equal names never merge identities.
- The spending trend and compact signed category bars follow the pie. Exact
  store/product figures, period figures and coverage details are expandable.
  Calculation explanations are available through info buttons instead of long
  inline paragraphs. Zero/negative products remain available in the full list
  and expanded product details even though they cannot form pie slices.
- Charts cover exactly the selected timeframe: one bar per day for weeks/months,
  one per elapsed month for years, and up to 24 consecutive groups of calendar
  days for custom ranges. Group lengths differ by at most one day. No days outside
  the selection enter the chart.
  All buckets together reconcile exactly to the selected total. The last bucket
  is never mistaken for the entire selected range.
- Positive and negative net totals appear above/below the zero line. Amounts,
  dates and counts are available in tooltips, accessibility labels and the
  expandable exact-period list. The chart scrolls horizontally on narrow screens.
- Press a bar, exact-period entry or receipt button to open history with the
  matching inclusive day bounds and branch. History retains its pagination,
  detail, correction and deletion workflows. Returning reloads the dashboard.
- [Store comparisons](store-comparisons.md) add signed net bars, a positive-net
  share donut and per-store receipt counts/averages. Store chart links open that
  store's receipts across the entire selected timeframe. Negative store nets are
  separate from the donut's positive denominator.
- [Product categories](product-categories.md) add signed category bars, exact
  totals, classification coverage and category receipt links for the selected
  range. They use current reviewed product labels, including for earlier links.

An em dash means that no receipts are stored for a period. A stored zero-total
period has a receipt count and a displayed zero amount. Neither establishes
complete coverage of actual spending. Missing periods are not interpolated.

## Fair comparisons

The current week/month/year has a partial-period icon and tooltip, including its last day.
Only receipts through today's printed Helsinki calendar day are included; there
is no extrapolation. The comparison uses equally many days from the beginnings
of the selected and previous periods. Both exact comparison ranges and totals
are available from the summary info button, with separate receipt links.

For example, November 1–18 compares with October 1–18. On March 31, if February
had 28 days, the comparison is March 1–28 versus February 1–28; the selected
March total still includes March 29–31. This distinction is explained on screen.
Completed historical periods compare their full calendar intervals, whose month
lengths can differ. At the supported January 1970 boundary, weeks are clipped
to supported days and unavailable predecessors are omitted.

Year-to-date comparisons also use equal numbers of calendar days, so leap years
can give different month/day endpoints. For example, January 1–March 1, 2024
compares with January 1–March 2, 2023. The ranges remain explicit. Custom ranges
compare with the immediately preceding interval of equal length. If that entire
interval would precede January 1, 1970, comparison is unavailable instead of
silently comparing a clipped predecessor.

Euro change is selected comparison net minus previous comparison net. Percentage
change uses the positive previous net as denominator, rounded to one decimal
place, halfway away from zero. Zero/negative previous nets do not produce a
percentage. If either interval has no stored receipts, the UI reports missing
comparison data rather than treating missing receipts as a measured zero.

## Financial rules and consistency

Each current, nondeleted reviewed receipt contributes its full signed total once.
Deposits, discounts, returns, unlinked products and reviewed adjustments are
already included. Product links and quantities are not required. This dashboard
does not combine normalized product prices or allocate receipt-wide discounts.

Totals, deltas and percentage arithmetic use `BigInt`. The average divides net
cents by all selected receipts, including zero and negative totals, and rounds
once to cents, halfway away from zero. An empty period has no average. Only
bounded relative chart coordinates use floating point after exact scaling.

`SpendingDashboardQuery` defines immutable civil-day intervals. The repository
selects matching current receipts in keyset batches of 16, verifies their canonical
documents/projections and folds all chart/comparison results inside one read
transaction. There is no history-page limit, SQLite integer `SUM`, persisted
aggregate or full-history receipt list. There are at most 31 chart buckets,
one selected-total fold, two comparison folds and 128 selected branch folds/labels.
Exceeding the branch bound fails the entire result and asks for a narrower filter.
The read covers the selection
and its comparison, rather than an unrelated rolling history. Runtime grows with
matching data; a long custom range can take longer.

Workspace reads use the same queue as saves and backup activation, resolving the
active repository when the queued call executes. Refresh, period/branch changes,
return from history and app resume reload data. Older results cannot replace a
new selection; loading/failure clears stale monetary output and failures offer
retry without partial results. Following the current period also follows a
Helsinki day/month rollover on refresh or resume.

No database schema, saved receipt/event bytes, backup format, dependency or
review-policy change is introduced. No private receipts or normal app databases
are used by tests.

## Compact layout verification

The November 24, 2026 layout adds no persistence or financial calculation changes.
Focused widget checks cover primary chart order, product/store switching across
period changes, exact positive-only shares, grouped-product choices, ring taps,
scoped navigation, comparison help links and 320px layouts with doubled text.
The native compact-dashboard rehearsal loads invented receipts in a temporary
workspace and verifies unchanged export bytes after chart navigation.
Validation passed: all 221 app tests, clean Flutter analysis, compact-dashboard
rehearsals on Windows and offline Android, and Windows product-ranking and
dashboard/recovery regressions. Dependency notices and their four tooling tests
also passed. Normal apps are restored with upgrade installs to retain sample data.

```powershell
flutter test test/compact_dashboard_test.dart test/spending_dashboard_test.dart test/store_spending_test.dart test/product_rankings_test.dart
flutter test integration_test/compact_dashboard_test.dart -d windows
flutter test integration_test/compact_dashboard_test.dart -d emulator-5554 --no-uninstall
```

## Earlier verification

Verified on November 22, 2026: all 123 parser, 82 domain, 199 storage and 167 app
tests passed, with clean analysis. Native Windows and offline Android rehearsals
passed, including year/custom ranges and tab switching. Checks include yearly
aggregation, leap-year comparisons, bounded full-span custom charts, strict range
validation and tab preservation/refresh. The dependency-notice audit and its four
Python tests also passed.

From Windows PowerShell:

```powershell
flutter analyze
flutter test
# Run dart analyze and dart test in each packages/receipt_* package as well.
flutter test integration_test/spending_dashboard_test.dart -d windows
flutter test integration_test/spending_dashboard_test.dart -d emulator-5554 --no-uninstall
```

The focused tests cover calendar/year/DST/leap boundaries, clipped 1970 dates,
partial and short-month comparisons, exact amounts beyond double precision,
negative/zero/missing periods, same-name branch separation, pagination-independent
totals, read-only export bytes, corrections/deletion/reopen and corruption refusal.
Widget checks cover chart and history navigation, branch selection, stale-request
rejection, failure/retry, Helsinki rollover and a 320px screen at doubled text size.

The native rehearsal creates only a guarded `dashboard-smoke-*` support directory
with invented receipts. It exercises actual home navigation, both period modes,
branch selection, year/custom ranges, chart-to-history pagination, corrections, encrypted recovery
with a queued read, deletion, reopen and retained previous-dataset recovery.
Windows screenshots use only those synthetic values. Normal build entry points
and the prior Android airplane setting are restored after native verification;
the normal app is never uninstalled or cleared.

[Product categories](product-categories.md), [product trends](product-trends.md)
and [product spending rankings](product-rankings.md) are now available. Rankings
use the selected dashboard range and branch, and open product history with the
same dates. Cross-store product matching still needs explicit comparison rules.
Release privacy/picker checks and synchronization remain open.
