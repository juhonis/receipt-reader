# Receipt history filters

## Text search

**Hae kuitteja** searches saved branch names and receipt row names, including
unlinked rows. Type part of a name; searches ignore letter case and require every
space-separated word somewhere in the receipt. For example, `market leipä` can
match a branch name and a product row. Finnish letters and punctuation remain
distinct: `ä` does not match `a`, and `%`/`_` are literal characters.

Search combines with branch, date, amount and category filters. It covers the
whole matching history before pagination, preserves the usual date/time order,
and restarts at the first result when changed. The clear icon removes only text;
**Tyhjennä suodattimet** clears all criteria. Refresh and returning from receipt
details keep the active search. Each result can be opened as usual.

Typing waits briefly before querying; the keyboard search action applies at once.
An older pending result cannot replace results for a newer query. Failed searches
offer the normal retry path. Search lasts for this screen and never writes data.

The repository accepts `HistoryFilter(query: '...')`; `withQuery` preserves the
other criteria. Text matching uses Dart Unicode lowercasing over saved branch and
row names, rather than SQLite's ASCII-only default case conversion. Search and
category filtering scan bounded batches in one read transaction and paginate
after matching. `spendingSummary` respects the same query when supplied one.
No schema, canonical document, event or backup format changes are needed.
Large-history performance remains a release check; there is no full-text index.

## Date, branch and amount filters

The Android and Windows history screens support read-only filters for saved
manual and OCR receipts. Open **Kuittihistoria → Suodata kuitteja**. Select a
stored branch and/or enter date and total-amount bounds, then choose
**Käytä suodattimia**. Unused fields stay blank; **Kaikki toimipisteet** includes
all branches. The applied bounds appear above the results.

- Dates use Finnish `d.m.yyyy` syntax (1970–2099), without a time. Both boundary
  days are included according to the printed Helsinki calendar date. Date-only
  receipts and receipts with known times are included on the same basis;
  no UTC midnight or invented time is used.
- Amounts require two decimals, with comma or dot, for example `-12,50` or
  `12.50`. Bounds include equality and support negative returns, zero and the
  complete SQLite signed 64-bit cent range. No floating-point amounts are used.
- Bounds combine with AND. Branch selection uses the durable branch ID, so
  branches with the same display name stay distinct.
- Invalid dates, times in date fields, out-of-range amounts and inverted ranges
  stay in the dialog for correction. They do not change the applied query.
- Cancel discards draft edits. **Tyhjennä suodattimet** returns to all receipts.
  Applying or clearing filters starts at offset zero; refresh retains the applied
  filters and also starts at zero. Empty filtered results have a separate message.
- **Näytä lisää kuitteja** reads another 30 matching receipts. A failed read keeps
  already loaded matching rows; retry uses the same filter object and offset.
  Applying a different filter clears the prior results before the request, so a
  failed first page cannot show rows from the previous query. Filter-dialog and
  refresh controls are disabled during a read; a new text query may supersede it.
- Filters last for the current history screen only. Closing and reopening history
  starts unfiltered. [Reviewed manual corrections](manual-corrections.md) and
  [fresh-image OCR corrections](ocr-corrections.md) are available from receipt
  details; completing either refreshes the active filtered result.

## Repository contract

`ReceiptRepository.history(filter: HistoryFilter(...), limit: 30, offset: 0)`
accepts an immutable filter with optional `branchId`, day-precision `fromDate` and
`throughDate`, and exact `minTotalCents`/`maxTotalCents`. Construction validates day
precision, inclusive range order and signed integer bounds before SQL execution.
Existing calls without a filter keep their prior behavior.

Values are bound query parameters. SQL applies branch/date/amount predicates;
text and category matching run before result pagination. History retains
printed-date/time descending order with durable ID ties.
Date-only receipts follow known times on the same day. Each page is read in a
consistent transaction and returned documents are checked against their
canonical data and projections. The existing branch/date index is reused. There
are no writes, new events or changes to canonical
receipt bytes, review provenance, identities or mutation retry records.

After a local manual correction, history keeps the applied filter and restarts
pagination from zero. A future concurrent writer/sync workflow must revisit
pagination when records can move or disappear between page requests. Large-history performance remains a
release check; an amount-only query has no dedicated amount index today.

## Verification

- `flutter test`: 73 app unit/widget tests passed after adding manual corrections.
- `dart test` in `packages/receipt_storage`: 49 storage tests passed.
- App and storage analyzers are clean.
- New repository tests cover individual/combined bounds, identical branch names
  with distinct IDs, exact signed limits, calendar boundaries, daylight-saving
  transition days, filtering before pagination, read-only identity/event
  preservation and canonical/projection checks.
- Widget tests cover apply/reset/cancel/refresh, validation and branch-read
  failures, initial/page-read retries, empty matches, in-flight controls and a
  320-pixel screen with 2× text and full-range amounts.
- The synthetic native smoke passes on Windows and Android in airplane mode. It
  seeds 34 invented receipts in an isolated temporary app-support directory,
  reopens SQLite, combines filters through the UI, loads 30 + 1 matching receipts,
  opens details, refreshes/resets and checks unchanged content/identity/sequence.
  It removes only its own temporary directory. No private receipt/image or the
  normal app database is used.
- Normal Android and Windows debug builds pass after native integration; the
  normal APK and prior emulator airplane setting are restored.

Run the native checks with:

```powershell
flutter test integration_test/history_filter_test.dart -d emulator-5554 --no-uninstall
flutter test integration_test/history_filter_test.dart -d windows
```

Native checks install a test entry point. Rebuild the normal Android/Windows app
when done and reinstall the normal debug APK on the emulator. See
[Windows environment setup](windows-development.md) for the SDK and emulator
commands. Deletion, structured backup/restore, products/aliases, sync and
Windows OCR packaging remain open.
