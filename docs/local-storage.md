# Transactional local receipt storage

`packages/receipt_storage` implements the first local-only slice of the
[storage contract](local-storage-contract.md), using the checked values and
manual commands from [receipt foundations](storage-foundations.md).

The normal Flutter app still opens no database and offers no save action. Its
dependencies now include the repository so native SQLite packaging is checked
on Android and Windows. The integration test explicitly opens and removes a
temporary database using invented data; real receipt images/exports are unused.

## Supported repository behaviour

`ReceiptRepository.open(File)` explicitly opens a caller-selected private file.
The future app adapter must provide its application-support path; this package
does not choose Downloads, the checkout, or an imported source path. One
repository/connection owns the normal application lifecycle. Queries currently
return futures; reactive history queries and update notifications are later work.

Opening creates dataset/device UUIDs only for a new empty dataset. Normal
close/reopen preserves them. `identity`, `branches`, `read`, `saveManual`, and
`verifyIntegrity` expose the current supported operations. No receiving, pairing,
restore, catalog mutation, receipt deletion, or conflict-resolution API exists.
Product links are explicitly rejected until catalog workflows and constraints
exist. Receipt edits currently apply only to the manual history this repository
can create; OCR/correction provenance is not inferred from existing UI flags.

Each save validates the canonical manual command again and atomically:

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

Schema v1 uses strict SQLite tables, foreign keys on every connection, WAL,
`synchronous = FULL`, and a bounded busy timeout. It stores the dataset identity,
local change log, causal parents/dependencies, heads, stores, live receipts,
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
version marker. Future/unsupported schemas fail without resetting data. This
step has no v1-to-v2 migration yet; every future released change needs one.

On open, a full local-history audit checks SQLite integrity/foreign keys, event
digests, contiguous sequences, ancestry/dependencies, complete mutation groups,
heads, selected projections, original row ownership and retry records. It
rejects inconsistent data instead of regenerating approvals or guessing a winner.
The v1 audit accepts only the installation's local origin; incoming histories,
tombstones, products/aliases, conflicts and peer state require explicit later
schema/API work. The full design contract is not implemented merely because
schema v1 exists. Keep all events; no compaction or restore-by-copy is supported.

Public failures expose error codes, not raw SQL, parameters or receipt text.
SQLite FULL can already roll back the transaction; wrapped background-isolate
and subsequent rollback errors are unwrapped to preserve the original failure
code. A caller keeps its immutable pending command to retry or cancel.

## Verification

- 39 storage tests pass: schema baseline/strictness, constraints, golden event
  bytes/hash, save/reopen/edit/retry, numeric limits, preserved row ownership,
  stale catalog/receipt checks, concurrent writers, corrupted projections/events,
  future-version refusal, DDL rollback, injected failures at every write boundary,
  actual SQLite disk-full rollback/retry, and sanitized failures.
- 18 domain tests, 68 parser tests and 39 Flutter tests pass; analyzers are clean.
- Windows and Android debug builds pass. The Windows build bundles `sqlite3.dll`.
- The Android integration test passes with airplane mode enabled: explicitly
  save synthetic branch/row data, close/reopen, verify identity/content/sequence,
  retry without duplicates, check integrity and remove the temporary directory.
  The prior airplane setting and normal debug app were restored afterward.

This does not certify fresh-install releases, backup/transfer exclusion policy,
power-loss durability on physical hardware, or backup/restore. The test database
is temporary; no real receipt or source image is written by these tests.

## Next integration

Before enabling real saves, configure Android automatic-backup/device-transfer
exclusions for the database, sidecars, identity and temporary captures. Add the
application-support path/lifecycle adapter, explicit branch selection and manual
field/row/relationship controls, then connect the reviewed command to save and
basic history. Keep OCR saves blocked until a separate adapter validates live
image evidence and translates structured decisions. Product/alias management,
deletion, sync conflicts and tested structured backup/restore remain later work.
