# Reviewed corrections of manual receipts

Android and Windows can correct a saved **manually entered** receipt. In
**Kuittihistoria**, open its details and choose **Korjaa käsin syötettyä kuittia**.
This edits the same receipt identity. Saving appends a new immutable version with
the displayed receipt revision as its causal parent; the earlier version stays
in the change log. Version browsing/revert is not exposed yet.

## Review and identity

The editor preloads the branch, full printed date/time precision, total and rows.
Every review checkbox starts unchecked. Compare the complete receipt with the
original paper/image, make the correction, and check branch, date, total and each
row again. Any edit clears all checks. An unchanged receipt cannot be saved as a
new version; merely resolving a pending branch creation to its stored dependency
revision does not count as a content change.

Retained rows keep their durable IDs, raw names, quantities and quantity scales,
rates, product/receipt discount scope, deposit parents/standalone status and
adjustment reasons. Newly added rows get fresh IDs; removed row IDs remain
reserved by the repository. Removing or reclassifying a product clears dependent
parent selections so they must be reviewed again. Changing quantity text supports
up to six decimals; untouched stored quantities retain their original scale.
Branch changes require explicit selection or explicit creation of a new branch;
editing a receipt does not rename a catalog branch in place.

The separate final confirmation is bound to the reviewed snapshot, row IDs,
expected receipt head and a fresh mutation ID. The editor checks the current
snapshot/review again after that dialog. Dates, exact signed cents, quantities,
relationships and reconciliation use the same validation as new manual entry.
Oversized or changed content stays in editable validation instead of writing.
The confirmation title/content scroll together on small screens with large text.

This uses the existing manual policy 1 and schema 2; no payload or migration
change is needed. The stored source remains `manual`. Decoding a stored document
only preloads data; it does not authorize another save.

## Save outcomes

- Cancelling the editor or final confirmation writes nothing.
- A successful correction returns directly to fresh history, avoiding a stale
  details page. History keeps its applied filters and restarts pagination at
  offset zero. A corrected receipt may move or no longer match those filters.
- An uncertain write keeps exactly one immutable command and locks editing/back
  navigation. Retry uses the same mutation, timestamp, expected head and row IDs.
  The explicit **Sulje ja tarkista historia** action also refreshes history,
  because the command may already have committed. Check the saved version there
  before trying to enter another correction. A process restart loses the pending
  in-memory command, so the same history check is necessary afterwards.
- A definite `staleReceipt` or `staleBranch` rejection cannot overwrite newer data.
  Retry is disabled and the screen explains that this attempt was not saved.
  Return to history and start a fresh review from the current receipt/catalog.
  The repository checks heads and branch dependencies in its write transaction;
  failures leave data and the local event sequence unchanged.

## Current boundary

OCR receipts use a separate [fresh-image correction flow](ocr-corrections.md).
The manual factory guard rejects OCR receipts in release builds too. Old stored
assertions cannot authorize a new OCR save and the source must never be relabelled.
[Reviewed deletion/tombstones](receipt-deletion.md) are available separately.
Version browsing/revert, products/aliases, structured backup/restore and
synchronization remain open.

## Verification

The app suite now contains 87 passing unit/widget tests. Ten correction tests cover
no-op/fresh review, retained metadata, removed parents/new IDs, cancellation,
receipt/catalog staleness, identical-command retries and uncertain exits,
source guards, filtered-history refresh and a 320-pixel screen with 2× text and
an exact minimum signed amount. Existing new-manual/OCR/history tests pass too.
The app analyzer is clean.

```powershell
flutter test integration_test/manual_correction_test.dart -d emulator-5554
flutter test integration_test/manual_correction_test.dart -d windows
```

The synthetic native smoke passes on Android in airplane mode and Windows. It
seeds a manual receipt with quantity/discount/deposit/adjustment metadata,
corrects it through the UI, reopens SQLite and checks identities, row data and
causal revision. It also commits a competing reviewed command while the final
dialog is open, verifies the stale attempt is rejected without advancing the
sequence, and checks that history shows the winner. Only its guarded temporary
app-support directory is removed. No private receipt/image or normal application
database is used. Normal Android/Windows debug builds pass afterwards; the normal
APK and prior emulator airplane setting are restored.
