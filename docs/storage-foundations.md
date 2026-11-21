# Durable receipt foundations

Implemented in `packages/receipt_domain`, following the
[local storage contract](local-storage-contract.md). This is a standalone Dart
package with no Flutter, SQLite, image, or network integration of its own. The app
now uses it for [manual saving and history](manual-saving.md) and separate
[live OCR review commands](ocr-saving.md).

## Values and receipt validation

- `DurableId` generates cryptographically random UUIDv4 identifiers and accepts
  only canonical lowercase UUIDv4 text. `RevisionId` contains an origin UUID and
  an exact per-origin sequence, reserving the maximum sequence as exhaustion.
- `ReviewRowIds` maps review objects by identity to durable row IDs. Reordering
  keeps the mapping; equal-but-distinct objects get distinct IDs. Existing row IDs
  can be retained for edits. A mapping cannot reassign or recycle a known ID.
  Cross-receipt ownership and historical non-reuse still need repository checks.
- `ReceiptSnapshot` and its nested models are immutable. They require trimmed
  names, valid printed civil dates, integer storage ranges, at least one row,
  unique row IDs, valid product parents and branch ownership, supported discount
  scopes/signs, adjustment reasons, and exact reconciliation.
- Quantities/rates must be absent together or complete with a known unit and
  matching arithmetic. Values remain `BigInt`; intermediate sums/multiplication
  cannot overflow SQLite/Dart integers. Never convert posted amounts to doubles
  or silently alter them to match quantities.
- `StoredReceiptDate` delegates to the pinned parser rules. Date-only has no UTC
  instant; timed receipts require one unambiguous Helsinki instant. Invalid
  dates, DST gaps/folds, and unsupported timezone ranges stay blocked. The review
  record identifies `timezone-0.11.2/latest_all` as the bundled rules version.

Name normalizer v1 trims ends, collapses Dart Unicode whitespace to one space,
and applies Dart lowercase. It preserves diacritics, punctuation, sizes and
variants. It performs no Unicode composition, fuzzy matching or product merging.
Tests cover Finnish names and package-size distinctions. A later alias workflow
must still handle collisions explicitly; this helper is not automatic matching.

## Manual confirmation and local commands

The intended adapter sequence is:

1. Build a validated snapshot with stable receipt/row IDs and an explicitly
   confirmed branch selection. An existing branch/product includes its reviewed
   revision; a new branch includes its proposed structured catalog fields.
2. Create `ManualReviewChecks` for those exact values, expected receipt heads,
   pending mutation UUID, branch/date/total checks, and the exact set of reviewed
   row IDs. The adapter must reset checks after edits and display relationships,
   quantity/rate fields and adjustment reasons as part of row review.
3. On a separate explicit final user action, call `confirm` with audit time and
   app version. Missing checks, missing/foreign rows, and invalid metadata fail.
4. Build `ReviewedReceipt.manual` with the current snapshot and expected heads.
   It rejects changed content or bases, even if totals still match. Branch IDs,
   catalog revisions, raw/corrected names, row IDs/order, quantities, and parent
   targets all participate in the comparison. Equal reconstructed immutable
   values are permitted; object identity is not the durable content contract.

The command retains the pending mutation UUID for future transactional retry
deduplication. It contains a structured `ReceiptDocument` and content digest.
A repository must recheck actual current heads, catalog dependencies, durable
row ownership, and all SQL/domain constraints inside its write transaction.
This package does not claim to have performed those database checks.

There is deliberately no OCR command constructor or OCR review decoder yet.
An OCR-origin review must not be relabelled as manual to use this path. Its
future adapter must independently run the live evidence audit and translate
all occurrence decisions and stable row targets before final confirmation.
The existing prototype's `reviewed` checkbox does not satisfy this new workflow.
Stored-receipt correction provenance also remains separate work.

## Canonical content and decoded assertions

`ReceiptSnapshotCodec` handles the structured receipt. `ReceiptDocumentCodec`
adds manual review policy/source, app/timezone versions, UTC review time, expected
heads and explicit field/row confirmation results. Initial payload and review
policy versions are 1; no released database schema or sync envelope exists yet.

Canonical JSON uses fixed field order, explicit nulls, stable enum text, decimal
strings for every integer, receipt order for rows, and sorted revision heads.
Positions are generated from row order. Names' normalized values are checked
against normalizer v1. No images, source paths, full OCR, geometry, or evidence
notes have serialization fields. Unknown fields/versions/types, duplicate keys,
noncanonical integers/order/whitespace, malformed Unicode text, oversized
documents, and invalid domain data are rejected. The current encoded/decoded
content limit is 2 MiB; future event/batch limits must include envelope overhead.

SHA-256 covers the UTF-8 canonical receipt plus review document, excluding the
event envelope and the digest itself. Synthetic golden JSON fixtures pin the
bytes, with an independently computed hash. A digest detects inconsistent
content; it is not a signature or proof of human review.

Decoding returns a `ReceiptDocument`, never a `ReviewedReceipt` or final local
confirmation. Restored/received assertions still need repository/event/history
validation. They cannot be used directly as an authorization to create a local
mutation. Supported historical codecs/policies must remain explicit as versions
evolve; a future migration must not fabricate a new review of old data.

## Verification and next implementation

The original 18 domain tests cover numeric boundaries and overflow-prone sums, quantities and
signed rounding, row identity retention, relationship/branch constraints, date
precision and DST, immutable inputs, golden serialization/hashes, malformed
payloads, unsupported OCR assertions, and stale manual confirmation. All pass,
as did 68 parser tests, 40 storage tests and 53 Flutter tests at the manual-saving baseline. All package/app
analyzers are clean. Native save/reopen verification on Android and Windows is
documented in [manual saving](manual-saving.md).

The [local receipt repository](local-storage.md) now uses Drift schema v2
and transactional writes, with constraint/migration/failure tests. The app has
private database ownership, Android backup/transfer exclusions, explicit manual
field/row/relationship checks, saving and basic read-only history. The separate
OCR evidence adapter is now implemented through the same storage boundary;
see [OCR saving](ocr-saving.md) for historical policy 2, current policy 3 and verification.
[Manual corrections](manual-corrections.md) and [OCR corrections](ocr-corrections.md)
now use that boundary. Deletion, backup/restore and networking remain later steps.
