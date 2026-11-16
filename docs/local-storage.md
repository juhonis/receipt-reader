# Transactional local receipt storage

`packages/receipt_storage` implements the first local-only slice of the
[storage contract](local-storage-contract.md), using the checked values and
source-specific review commands from [receipt foundations](storage-foundations.md).

The normal Flutter app now owns an application-support database and provides
[explicit manual saving and basic history](manual-saving.md) on Android and
Windows. [Reviewed OCR saving](ocr-saving.md) uses a separate command/API and cannot use the manual save path.
Native integration tests create and remove isolated synthetic databases; real
receipt images/exports are unused.

## Supported repository behaviour

`ReceiptRepository.open(File)` explicitly opens a caller-selected private file.
The app adapter provides its application-support path; this package
does not choose Downloads, the checkout, or an imported source path. One
repository/connection owns the normal application lifecycle. Queries currently
return futures; reactive history queries and update notifications are later work.

Opening creates dataset/device UUIDs only for a new empty dataset. Normal
close/reopen preserves them. `identity`, `branches`, `read`, `readDeleted`,
`history`, `saveManual`, `saveOcr`, `deleteReceipt`, and `verifyIntegrity` expose
the current supported operations. No receiving, pairing, restore, catalog
mutation, or conflict-resolution API exists. Product links are explicitly
rejected until catalog workflows and constraints exist. The UI creates,
corrects and explicitly deletes reviewed receipts. The repository supports
reviewed revisions with the same source; provenance is never inferred from UI flags.

Each save validates the canonical source-specific command again and atomically:

1. Checks the mutation UUID for an already committed identical command, then
   validates the receipt's expected head, confirmed branch revision/fields and
   retained row ownership. A pending new branch cannot stand in for an existing
   branch selection. A stale edit fails rather than rebasing silently.
2. Reserves local sequence numbers. A new branch and its first receipt form one
   two-event mutation group; an existing branch needs one receipt event.
3. Appends full structured immutable events with their dataset, per-origin
   identity, canonical envelope/digest, parents, dependencies, audit time and
   mutation-group metadata. Audit clocks never choose a winner.
4. Creates the branch if required, replaces the complete receipt/item/review
   projection, reserves newly introduced row IDs, selects heads and advances the
   committed cursor. Cross-branch correction replaces all affected child fields
   together. Historical row ownership remains after a row is removed.
5. Records the mutation's command digest and original result revision, verifies
   projection agreement, and commits. A failed statement rolls back sequence,
   data, events, heads, cursors and retry metadata together.

Retrying the same mutation returns the original revision without new events,
including after restart or a later successful edit. Reusing it with different
content is an error. Removed IDs cannot be reintroduced or moved to another
receipt. Concurrent connections either observe a stale base or a retriable
SQLite busy error; they do not silently overwrite one another.

## Schema and connection guarantees

Pinned dependencies are Drift 2.35.4 and sqlite3 3.9.1, with Drift's generator
2.35.3. SQLite native assets are bundled by the build hooks. No library/model
download is needed when the installed app opens SQLite. Builds may download
their dependencies/assets on the development PC.

Schema v3 uses strict SQLite tables, foreign keys on every connection, WAL,
`synchronous = FULL`, and a bounded busy timeout. It stores the dataset identity,
local change log, causal parents/dependencies, heads, stores, live/deleted receipts,
items, review documents, historical row identities, committed cursors and
mutation retry results. Triggers prevent ordinary update/deletion of immutable
events, revision links, row identities and retry records.

SQL checks cover integer storage, enums, UUIDs, date/time precision groups,
currency, discount signs/scopes, quantity groups, adjustment reasons and
references. Shared domain/repository checks additionally cover calendar/DST
validity, exact sums and multiplication, parent row types, ownership, causal
history and review freshness; SQL row checks cannot replace those rules.
Financial values stay integer cents. No SQL floating-point aggregation is used.

The committed Drift schema snapshot and generated migration helpers verify the
creation baseline. Creation explicitly wraps DDL and schema-version assignment
in one transaction; a failed creation leaves neither partial tables nor a newer
version marker. Future/unsupported schemas fail without resetting data. Tested
v1/v2-to-v3 migrations preserve existing values and event bytes, including after
injected failures. Version 3 adds receipt-only tombstones and minimal deleted
shells. See [receipt deletion](receipt-deletion.md) for transaction, retry,
retention and migration details.

On open, a full local-history audit checks SQLite integrity/foreign keys, event
digests, contiguous sequences, ancestry/dependencies, complete mutation groups,
heads, selected projections, original row ownership and retry records. It
rejects inconsistent data instead of regenerating approvals or guessing a winner.
The current audit accepts local snapshots and tombstones from the installation's
local origin; incoming histories, products/aliases, conflicts and peer state
require explicit later schema/API work. The full design contract is not implemented merely because
schema v1 exists. Keep all events; no compaction or restore-by-copy is supported.

Public failures expose error codes, not raw SQL, parameters or receipt text.
SQLite FULL can already roll back the transaction; wrapped background-isolate
and subsequent rollback errors are unwrapped to preserve the original failure
code. A caller keeps its immutable pending command to retry or cancel.

## Verification

- 40 storage tests pass: schema baseline/strictness, constraints, golden event
  bytes/hash, save/reopen/edit/retry, numeric limits, preserved row ownership,
  stale catalog/receipt checks, concurrent writers, corrupted projections/events,
  future-version refusal, DDL rollback, injected failures at every write boundary,
  actual SQLite disk-full rollback/retry, sanitized failures, and bounded civil-date
  history pages with exact values and integrity checks.
- 18 domain tests, 68 parser tests and 53 Flutter tests pass; analyzers are clean.
- Windows and Android debug builds pass. The Windows build bundles `sqlite3.dll`.
- The Android integration test passes with airplane mode enabled: explicitly
  save synthetic branch/row data, close/reopen, verify identity/content/sequence,
  retry without duplicates, check integrity and remove the temporary directory.
  The prior airplane setting and normal debug app were restored afterward.

The [manual UI integration](manual-saving.md) additionally passes on native Android
(in airplane mode) and Windows, including save, close/reopen and history details.
Android automatic-backup/transfer exclusion XML is configured and packaged. These
checks do not certify fresh-install releases, manufacturer transfer tools,
power-loss durability on physical hardware, or structured backup/restore. No
real receipt or source image is written by the tests.

## Next integration

[Reviewed OCR saving](ocr-saving.md) now validates live evidence, preserves typed
provenance (introduced in schema 2). [History filters](history-filters.md) now apply
validated branch/civil-date/exact-cent bounds before pagination without a schema
change. [Manual corrections](manual-corrections.md) now use the existing
source-specific reviewed command and expected-head transaction from history.
[OCR corrections](ocr-corrections.md) now add fresh image review and explicit row
matching without changing source policy. [Receipt deletion](receipt-deletion.md)
adds schema-3 tombstones while retaining prior history and row ownership.
Product/alias management, sync conflicts and tested structured backup/restore
remain later work. Existing verification counts above describe the manual-saving
baseline; the deletion guide records the current suites and native checks.
