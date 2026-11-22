# Weekly and monthly spending dashboard

Open **Viikko- ja kuukausiseuranta** on the home screen. The dashboard works
offline on Android and Windows using current reviewed receipt totals. The
existing **Kulutus** screen remains available for all-history branch/month totals.

## Navigation and charts

- Switch between Monday–Sunday weeks and calendar months. The default is the
  current month in Helsinki, independently of the computer's timezone.
- Use the arrows or calendar picker to visit earlier periods. **Nykyinen jakso**
  returns to the current week/month. Future periods cannot be selected.
- Filter by one branch or all branches. Branches retain their durable identities;
  equally named branches do not merge.
- See net spending, receipt count and average receipt value for the selected
  period, plus up to 12 consecutive calendar periods in the chart.
- Positive and negative net totals appear above/below the zero line. Amounts,
  dates and counts are available in tooltips, accessibility labels and the
  expandable exact-period list. The chart scrolls horizontally on narrow screens.
- Press a bar, exact-period entry or receipt button to open history with the
  matching inclusive day bounds and branch. History retains its pagination,
  detail, correction and deletion workflows. Returning reloads the dashboard.

An em dash means that no receipts are stored for a period. A stored zero-total
period has a receipt count and a displayed zero amount. Neither establishes
complete coverage of actual spending. Missing periods are not interpolated.

## Fair comparisons

The current week/month is marked **Keskeneräinen jakso**, including its last day.
Only receipts through today's printed Helsinki calendar day are included; there
is no extrapolation. The comparison uses equally many days from the beginnings
of the selected and previous periods. Both exact comparison ranges and totals
are shown, with separate receipt links.

For example, November 1–18 compares with October 1–18. On March 31, if February
had 28 days, the comparison is March 1–28 versus February 1–28; the selected
March total still includes March 29–31. This distinction is explained on screen.
Completed historical periods compare their full calendar intervals, whose month
lengths can differ. At the supported January 1970 boundary, weeks are clipped
to supported days and unavailable predecessors are omitted.

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
aggregate or full-history receipt list. At most 12 period folds and two comparison
folds are retained, regardless of branch count. Runtime grows with matching data.

Workspace reads use the same queue as saves and backup activation, resolving the
active repository when the queued call executes. Refresh, period/branch changes,
return from history and app resume reload data. Older results cannot replace a
new selection; loading/failure clears stale monetary output and failures offer
retry without partial results. Following the current period also follows a
Helsinki day/month rollover on refresh or resume.

No database schema, saved receipt/event bytes, backup format, dependency or
review-policy change is introduced. No private receipts or normal app databases
are used by tests.

## Verification

Verified on November 22, 2026: all 123 parser, 76 domain, 199 storage and 165
app tests passed, with clean analysis. Both native dashboard rehearsals passed,
including Android airplane mode. The four license-audit tests and dependency
notice audit also passed.

From Windows PowerShell:

```powershell
flutter analyze
flutter test
# Run dart analyze and dart test in each packages/receipt_* package as well.
flutter test integration_test/spending_dashboard_test.dart -d windows
flutter test integration_test/spending_dashboard_test.dart -d emulator-5554
```

The focused tests cover calendar/year/DST/leap boundaries, clipped 1970 dates,
partial and short-month comparisons, exact amounts beyond double precision,
negative/zero/missing periods, same-name branch separation, pagination-independent
totals, read-only export bytes, corrections/deletion/reopen and corruption refusal.
Widget checks cover chart and history navigation, branch selection, stale-request
rejection, failure/retry, Helsinki rollover and a 320px screen at doubled text size.

The native rehearsal creates only a guarded `dashboard-smoke-*` support directory
with invented receipts. It exercises actual home navigation, both period modes,
branch selection, chart-to-history pagination, corrections, encrypted recovery
with a queued read, deletion, reopen and retained previous-dataset recovery.
Windows screenshots use only those synthetic values. Normal build entry points
and the prior Android airplane setting are restored after native verification;
the normal app is never uninstalled or cleared.

Store-share charts, product categories, cross-store product matching and richer
price comparisons remain separate analytics milestones. Release privacy/picker
checks and synchronization remain open.
