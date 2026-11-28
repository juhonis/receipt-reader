# Reviewed receipt deletion

Manual and OCR receipt detail pages now offer a separate Finnish deletion
confirmation on Android and Windows. The confirmation shows the saved branch,
printed date and total, explains retention, and requires an explicit checkbox
before enabling deletion. Cancel leaves the receipt unchanged. Successful
deletion returns to refreshed history with the same applied filters at offset
zero. Deleted receipts are excluded before filtering, pagination and limits.

Deletion removes the current receipt from normal history. It retains the prior
structured snapshots and an immutable tombstone in the local change log. It is
**not secure erasure**. There is no undo or receipt restoration workflow yet.
The app does not delete imported original images or separately exported files.

## Duplicate replacement

The [new-receipt duplicate comparison](receipt-review.md#possible-duplicate-receipts)
can explicitly keep the incoming receipt and remove one selected old receipt.
`ReceiptRepository.replaceReceipt(incoming, deletion)` wraps the existing reviewed
save and reviewed deletion in one outer SQLite transaction. It requires a new,
distinct receipt ID, no correction heads, separate mutation IDs and a plausible
date/time match with the exact current old document/head. Manual and OCR provenance
remain independent; replacing one with the other never relabels its prior history.

Both mutations must be new together or exact replays together. A separately saved
incoming mutation cannot be repurposed to delete another receipt, and a separately
committed deletion cannot admit an otherwise fresh incoming save. Any validation
or statement failure rolls back both changes, sequence/cursor updates and retry
records. Later retries cannot resurrect either receipt after subsequent deletion.

The app adapters serialize the whole replacement with workspace/backup operations.
Pending retries freeze both commands. Existing tombstone/event formats, schema,
backup versions, catalog entries and original receipt files remain unchanged.
Backups retain both prior history and the one current replacement; spending counts
only live receipts. Native tests verify rollback, reopen, retry, backup restore and
single-counted spending with a real temporary SQLite dataset.

## Reviewed command and causal identity

`ReceiptDeletionChecks` captures the exact displayed document and expected
revision. Confirming produces a privately constructed
`ReviewedReceiptDeletion` with one mutation UUID. The strict canonical version-1
tombstone contains the receipt ID, expected revision, reviewed document SHA-256,
manual/OCR source, deletion policy version, explicit review assertion, UTC audit
time and app version. It contains no receipt names, amounts, pixels, paths or
OCR notes. Decoding historical tombstone bytes cannot authorize a local write.

The repository revalidates the displayed document digest, source and current
head. A stale screen cannot delete a newer revision. One transaction reserves
one sequence, appends a one-event tombstone mutation with the prior receipt head
as parent, removes current item/review children, writes a minimal deleted shell,
selects the tombstone head, advances the cursor and records the retry result.
The shell retains only receipt identity, deletion state, revision and audit
fields. Prior receipt events, row identities and branch catalog entries remain.
A statement failure rolls the entire transaction back.

An uncertain result locks editing and dismissal, offering the identical command
for retry or explicit close to refreshed history. A stale result disables retry
and returns to history for a fresh review. A matching committed mutation returns
its original revision, even after reopening. Reusing its ID with different
content fails. A historical committed save retry can return its original result
but cannot recreate the deleted projection; every new save targeting that receipt
ID fails with `receiptDeleted`. Retired row IDs remain reserved.

`read(id)` returns null for a validated deleted receipt; `readDeleted(id)`
returns the tombstone and selected revision. The startup integrity replay checks
tombstone ancestry, reviewed-document hash/source, audit time, mutation grouping,
minimal shell and empty current children, and rejects later snapshot resurrection.
It still supports only the local origin; sync remains a separate milestone.

## Schema migration

Schema 3 adds receipt deletion state, nullable snapshot fields constrained by
live/deleted state, and receipt-only tombstone operations. Versions 1 and 2
migrate atomically to version 3. Table rebuilds temporarily disable foreign keys
outside the DDL transaction, verify all references before commit, and restore
foreign-key enforcement. Existing event bytes, dataset/device identities and
retry records stay unchanged. Failed migration retains the old schema/version;
future schema versions fail without resetting data.

## Verification

As of 2026-11-16, 98 app tests, 30 domain tests and 66 storage tests pass; app,
domain and storage analysis is clean. The existing parser suite has 68 tests.
Nine deletion widget tests cover both sources, filtered-history refresh,
cancellation, stale screens, uncertain failures before/after commit, explicit
uncertain exit, duplicate/back prevention during a pending write, and a
320-pixel screen with 2× text. Correction tests also treat a deleted receipt as
a stale save target.

Storage tests cover canonical tombstone bytes, reopen/retry, immutable prior
events, reserved row ownership, rejection of resurrection and mutation-ID reuse,
filtered pagination, invalid deleted projections, and rollback at eight deletion
write boundaries. Migration tests exercise populated released schemas 1 and 2,
compare existing persisted values/event bytes, inject DDL failure, and retry
migration and committed commands after reopening.

Run the native synthetic smoke with:

```powershell
flutter test integration_test/receipt_deletion_test.dart -d emulator-5554 --no-uninstall
flutter test integration_test/receipt_deletion_test.dart -d windows
```

It passes on Windows and Android in airplane mode. It cancels and confirms a
manual deletion through the UI, reopens SQLite, verifies integrity and retries,
then commits an OCR correction while deletion confirmation is open. The stale
deletion is rejected; a fresh confirmation deletes the corrected receipt.
Reopening preserves both tombstones, and old save retries cannot restore them.
The smoke uses synthetic data in a guarded temporary application-support
subdirectory and removes only that directory. It never opens the normal app
database or private receipt files. This tests shared OCR receipt storage, not
production Windows recognition.

After native tests, restore the prior emulator airplane setting, rebuild the
normal Windows/Android entry points, reinstall the normal APK without clearing
app data, and launch the normal app. See [Windows setup](windows-development.md).

## Next milestone

The [structured backup/recovery core](backup-recovery.md) now preserves tombstones,
event identities and row ownership with a fresh device identity on restore.
Complete the encryption decision, user-facing export/import and safe activation
before relying on this app as the only copy of financial history. Receipt
undo, incoming sync/conflict resolution, and whole-dataset erasure are separate
workflows; this deletion API does not implement them.
