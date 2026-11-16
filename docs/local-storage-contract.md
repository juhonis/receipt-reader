# Local storage contract

Status: design baseline, 2026-11-16. This specifies the first Drift/SQLite
implementation; it does not introduce a database, migrations, or a save button.
The app still performs temporary reviews and saves nothing.

This document makes the [plan's data and sync rules](plan.md#3-data-architecture--financial-rules)
concrete. Implement local persistence first on Android and Windows. Network
transport, pairing, backup UI, and product matching remain separate work.

## 1. Ownership and database lifecycle

- One private, application-owned database per installation contains one dataset.
  Use the platform application-support directory, never the checkout, gallery,
  Downloads directory, or a shared/network folder. Android and Windows have
  independent files even after pairing.
- Drift owns the connection and all writes through a repository. Enable and
  verify `PRAGMA foreign_keys = ON` on every connection before use. Use WAL and
  `synchronous = FULL`; fail initialization if required settings cannot be set.
  Transactions serialize repository mutations. No UI or plugin writes SQL.
- SQLite schema version starts at 1. Event payload version, review-policy
  version, and future wire-protocol version are independent integers, initially
  1. A schema migration must not rewrite historical event payloads or identities.
- Opening a newer, unsupported schema is a visible error, never a reset. A
  failed migration rolls back; keep the original database recoverable and never
  delete it to make startup succeed. Do not offer destructive downgrade.
- Ordinary SQLite is not application-level encryption. Rely initially on OS
  application storage protection. Exclude the live database, WAL/SHM files,
  installation identity, and temporary captures from Android automatic backup
  and device transfer before enabling real saves. Restoration uses the explicit
  validated restore path in section 9, not a copied live database.

## 2. Primitive representations and limits

| Value | Storage and validation |
| :--- | :--- |
| Dataset, device, entity, and row IDs | Canonical lowercase UUIDv4 text from a cryptographically secure generator. No timestamps, names, file paths, or Dart object identities as IDs. |
| Money | Signed SQLite 64-bit `INTEGER` cents, range -9223372036854775808 through 9223372036854775807. Currency is exactly `EUR`. |
| Quantity | Nullable signed 64-bit `quantity_value`, integer decimal `quantity_scale` in 0..6, and `quantity_unit` enum. Actual quantity is value / 10^scale. Never infer quantity 1. |
| Unit rate | Nullable nonnegative signed-64-bit `rate_micros`, millionths of EUR/unit. |
| Audit time | Nonnegative signed-64-bit UTC milliseconds. Context only: clock changes must not determine revisions, cursors, or winners. |
| Event sequence | Positive signed-64-bit integer below 9223372036854775807; the maximum value is the exhausted `next_local_seq` sentinel. Exhaustion blocks mutation rather than wrapping. |
| Enums and booleans | Explicit stable text codes and integer 0/1 with `CHECK` constraints; never Dart enum ordinals. Unknown codes/versions fail validation. |
| Names | Nonblank trimmed display names. Keep the necessary printed row name separately from the corrected name; do not retain surrounding OCR text. |

Use `BigInt` for parsing, summing, multiplication, and rounding, including before
converting to SQLite integers. Reject an out-of-range value with a field error;
never clamp, truncate, wrap, convert to `REAL`, or store it as numeric text. Check
`typeof(column) = 'integer'` for stored numeric columns in addition to range checks.
SQLite integer `SUM` can overflow for valid individual rows: reconciliation and
spending aggregation must use exact Dart accumulation rather than an unchecked
SQL sum. Any future optimized aggregate must demonstrate equivalent behaviour.

For the first save implementation, quantity/rate fields must be either all
absent (including scale/unit), or complete: nonzero quantity, known unit
`piece`/`kg`/`litre`, nonnegative rate, and matching extended cents. The parser's
`unknown` unit is uncertainty, not permission to invent a unit. Partial or
unknown-unit source quantities remain blocked until explicitly reviewed with a
supported representation. Preserve return signs. Calculate with the parser's
single half-away-from-zero rounding rule; never change the posted row amount.

## 3. Printed receipt date and time

Store integer `printed_year`, `printed_month`, `printed_day`, nullable
`printed_hour`, `printed_minute`, `printed_second`, `date_precision`,
`timezone_id = Europe/Helsinki`, and nullable `utc_instant_ms`.

| Precision | Nullability and instant |
| :--- | :--- |
| `day` | All time fields and UTC are null. Never synthesize midnight. |
| `minute` | Hour/minute required, second null; derive UTC using second zero, retaining minute precision. |
| `second` | All time fields required; derive UTC at the printed second. |

SQL checks enforce year 1970..2099, month/day/hour/minute/second bounds and each
nullability pattern. The shared date validator additionally rejects impossible
calendar dates, Helsinki DST gaps/folds, and unsupported timezone-data ranges.
For accepted timed receipts UTC must equal the unique derived instant. Persist
the timezone-data version with the review result; migrations must not silently
reinterpret previously approved civil times. Date-only receipts do not require
an instant. Explicit DST-fold selection remains deferred and blocks timed saves.

## 4. Projection tables and constraints

Projection tables represent selected current values, not independent editable
copies of event history. Every mutable aggregate references its selected event
through `current_revision_origin`/`current_revision_seq`. All foreign keys use
`NO ACTION` unless the transaction explicitly replaces a receipt's children.
IDs cannot change; catalog deletion and moving products between branches are
deferred. Correcting a receipt's branch requires a fresh branch confirmation and
complete reviewed snapshot, clearing or explicitly remapping every product link
to that branch. Remove old child projections before changing the branch and
replacing them in the same transaction; never move a product implicitly.

| Table | Required fields and constraints |
| :--- | :--- |
| `dataset_state` | Exactly one row (`singleton = 1`): `dataset_id`, fresh installation `device_id`, `next_local_seq` starting at 1. Check singleton and sequence bounds. Dataset ID remains stable through pairing/restore; local device ID does not survive restore. |
| `stores` | `id` primary key, `display_name`, optional `chain`, `address`, `printed_identifier`, selected revision, `created_at_ms`, `updated_at_ms`. A chain name alone cannot satisfy branch confirmation. Similar names may suggest an existing branch but never merge automatically. |
| `products` | `id` primary key, `store_id` foreign key, corrected `canonical_name`, nullable package quantity/scale/unit as an all-or-none group, selected revision, audit times. Package quantity must be positive and have a known unit. Also `UNIQUE(store_id, id)` for composite references. |
| `product_aliases` | `id` primary key, `store_id`, `normalized_name`, `normalizer_version`, `product_id`, `is_active`, selected revision, audit times. Composite foreign key `(store_id, product_id)` to products; partial unique index on `(store_id, normalized_name) WHERE is_active = 1`. Only effective, resolved projections enter this table. Inactive aliases retain identity/history but do not match. No silent replacement on collision. |
| `receipts` | `id` primary key, `store_id` foreign key, printed date fields from section 3, currency, `total_amount_cents`, `reviewed_at_ms`, selected revision, audit times, `is_deleted`, `has_conflict`. Also `UNIQUE(id, store_id)`. Receipt review metadata belongs to the selected revision. |
| `receipt_items` | `id` primary key, `receipt_id`, repeated `store_id`, zero-based `position`, `kind`, nullable `parent_item_id`, nullable `discount_scope`, nullable `product_id`, nullable `raw_name`, corrected `name`, versioned `normalized_name`, quantity fields, rate, `line_total_cents`, nullable `adjustment_reason`. `UNIQUE(receipt_id, position)` and `UNIQUE(receipt_id, id)`. |
| `receipt_reviews` | One row per selected live receipt: `receipt_id` primary/foreign key, policy and payload versions, approved-content SHA-256, review source (`manual`/`ocr`/`correction`), app/parser/OCR/model/timezone versions as applicable, exact reconciliation result, row count, structured evidence result. No images or OCR dumps. Replaced atomically with the receipt projection. |
| `receipt_review_decisions` | Receipt-scoped durable decision IDs, occurrence code/ordinal, decision code, optional source and target item IDs, typed relationship/classification, and comparison result. Composite foreign keys keep live row references within the same receipt. Removed-source decisions retain an occurrence code, not a foreign key to a deleted row. Only structured codes/targets/counts survive review; source words, boxes, and free-text evidence explanations do not. |

A receipt projection is exactly one of: live (`is_deleted = 0`,
`has_conflict = 0`), deleted (1, 0), or conflicted (0, 1). Live rows require all
reviewed fields, a selected revision and review record; deleted/conflicted shells
have null store/date/financial/reviewed fields and no item/review children.
A deleted shell selects its tombstone; a conflicted shell has null selected
revision columns and reads candidates through `entity_heads`. Enforce the
row-local state/nullability patterns with SQL checks and the child requirements
transactionally. Catalog caches also clear their selected revision while
conflicted; their retained identity/ownership columns preserve foreign keys.

`receipt_items(receipt_id, store_id)` references `receipts(id, store_id)` and
`(store_id, product_id)` references `products(store_id, id)`. A parent uses the
composite key `(receipt_id, parent_item_id)` referencing
`receipt_items(receipt_id, id)`, is never self, and must be a product row. The
repository checks parent type and all cross-row rules inside the transaction;
SQL foreign keys alone cannot enforce them.

Financial constraints:

- All items contribute signed `line_total_cents` exactly once. At least one row
  and dense positions 0..n-1 are required; row order is part of the receipt.
- `discount` amounts are strictly negative. `discount_scope = item` requires a
  product parent; `receipt` requires no parent. Scope is required for discounts
  and null for other kinds. Do not allocate receipt-wide discounts to products.
- A `deposit` may link to a product or have no parent. `product` and `adjustment`
  have no parent. This prevents parent cycles without recursive inference.
- `adjustment` requires a nonblank explicit reason; other kinds have no adjustment
  reason. A total mismatch never creates an adjustment automatically.
- A linked product is permitted only on a product row and must belong to the
  receipt's branch. Unmatched products remain null. Creating a row does not
  automatically create a product or alias.
- Explanatory prices, descriptions, duplicate OCR dispositions, payment data,
  and tax summaries are review decisions, not additional financial rows.
- Net/gross discount conversions and quantity combinations unsupported by the
  current review rules remain blocked; a schema field is not a new UI capability.

Before the first migration, choose and test alias normalization v1. Its output
must preserve package sizes/variants; never alter all existing keys silently in
an upgrade. A normalization migration must surface newly colliding keys.

Indexes: receipts on `(store_id, printed_year, printed_month, printed_day, id)`
and `(is_deleted, has_conflict)`; items on `(receipt_id, position)` and
`(product_id, receipt_id)`; products/aliases on store and their declared unique
keys. Add indexes for remaining foreign-key child columns. Avoid an FTS copy
of raw OCR; search can start with structured names.

## 5. Approval is bound to the saved content

`ReviewValidation.complete` and `OcrEvidenceAudit.ready` are necessary inputs,
not save authorizations. Existing review row IDs are temporary Dart objects.
The persistence adapter must introduce an immutable `ReviewedReceipt` command
with durable row IDs, explicit store ID, expected revision heads, and structured
review results. A caller-supplied `reviewed = true` flag is insufficient.

1. Resolve/create an explicitly confirmed branch. Choosing a store ID must bind
   the approval to that branch; editing its text cannot reuse an old selection.
   A pending new branch includes its approved catalog snapshot in the command;
   its actual event dependency is assigned during the atomic creation transaction.
2. Allocate receipt/row UUIDs once for the pending save and keep a stable mapping
   from review objects. Preserve IDs of retained rows when editing a stored
   receipt; new rows get new IDs. Never recycle removed IDs or share them with
   another receipt. Allocate decision IDs and translate all targets together.
3. Revalidate branch/date, field ranges, row order, signs, quantity arithmetic,
   typed relationships, and exact total reconciliation with shared domain rules.
   Manual entry needs explicit field/row review; it must not claim OCR comparison.
   OCR requires the live, matching image/source context and the full evidence
   audit, including omissions, removed rows, and fresh page/geometry approvals.
4. Bind final confirmation to the exact immutable content, row IDs/order, store
   ID, expected base heads, and evidence decisions. Any relevant edit invalidates
   it. The builder must reject stale/missing evidence independently of UI flags.
5. Produce a versioned canonical approved-content document and SHA-256 digest.
   Canonical form uses an explicitly ordered field list, ordered rows, decisions
   ordered by occurrence/ID, UTF-8 strings with deterministic JSON escaping,
   explicit nulls, and decimal strings for all integers. Omit only the digest
   itself and event envelope from this content. Specify golden bytes in tests
   before implementing the codec; do not hash arbitrary map iteration order.
6. In the save transaction, independently validate this command, digest, catalog
   references, and current revision heads. Reject changed bases with a visible
   stale-review result; never overwrite them or retry against a new base silently.

Persist branch/date/row confirmation results, row comparisons, whole-page check
results, finding occurrence codes and dispositions/targets, warning codes, and
audit/policy versions. Store the number of original findings, reviewed findings,
omissions/dispositions, and unresolved blockers (zero at save). This is a record
of a performed review, not evidence from which to rerun OCR or prove accuracy.
The digest detects accidental inconsistency; it is not a signature or proof of
human review. Imported events must still pass payload/domain validation.

Do not persist full OCR text, word IDs/geometry, images/thumbnails, file paths,
source-image hashes, the original parser draft, or free-text evidence notes.
Keep only necessary row names and structured results. Explain this retention in
the save UI; the current required evidence explanations remain temporary.
Correction of a stored receipt uses a new reviewed structured snapshot, retains
prior review history in immutable events, and explicitly records whether a new
image was compared. Do not pretend the discarded image remains available.

Only show save success after commit. Then release app-owned temporary evidence.
A failed save leaves the review available to retry/cancel; cancel never writes a
draft. Imported originals remain untouched on every path.

## 6. Atomic mutations and durable event identities

| Table | Contract |
| :--- | :--- |
| `change_log` | Primary key `(origin_device_id, origin_seq)`; shared dataset ID, entity kind/id, payload version, operation (`snapshot`/`tombstone`), canonical full payload, event SHA-256, audit time, mutation UUID/index/count. An event ID is the pair; no independent numeric revision counter. Rows are immutable. |
| `revision_parents` | Child event pair plus parent event pair as primary key; foreign keys to both events. Parents must refer to the same aggregate, be distinct and acyclic. Creation has no parents, ordinary edit/delete has its expected head, resolution has every current competing head. |
| `event_dependencies` | Event pair and required catalog event pair; foreign keys to immutable events. Receipt snapshots name the store/product revisions they reviewed; alias snapshots name their store/product dependencies. Dependencies are not revision parents. |
| `entity_heads` | Entity kind/id and head event pair; unique head per entity/event. The set contains exactly the maximal revisions under ancestry. One head selects a snapshot/tombstone; multiple heads mean conflict. |
| `sync_conflicts` | Conflict key (entity identity or alias business key), detection time, state, and nullable resolving event. A member table references all competing events. Candidate payloads remain in `change_log` after resolution. |
| `received_cursors` | Origin device primary key and highest contiguous committed sequence, starting at zero. Includes locally authored history. Never infer a cursor from `MAX(seq)` across gaps. |
| `sync_peers` / `peer_cursors` | Future paired peer ID, non-secret pinned identity/credential reference, protocol metadata, and peer-acknowledged cursor per origin. Not authorization secrets. Credentials/certificate private keys belong in platform secure storage. |

One store, product, alias, or complete receipt is an aggregate. Receipt rows,
review results, and decisions are nested in the receipt snapshot and have no
independent change events. No row-by-row sync merge. Catalog snapshots always
include their immutable store ownership; changing catalog ownership is invalid.
An event digest covers its canonical envelope, payload, sorted parent IDs and
dependency IDs, excluding only that digest. Replay equality compares this whole
body, not merely the financial payload. Use decimal strings for integers in
the serialized envelope as well as in receipt content.

Events from one atomic local operation share a mutation UUID, zero-based index,
and count, with consecutive sequences on the same origin. Receivers must commit
the complete group together, including multi-alias resolutions. A group cannot
be split by acknowledgements; reject an incomplete group with a retriable error.
Enforce `UNIQUE(origin_device_id, mutation_id, mutation_index)` and positive count
with index in 0..count-1; the repository checks group completeness/consistency.
Define bounded group sizes before transport and reject oversized local operations
rather than creating history that cannot sync.

A repository mutation, inside one transaction:

1. Checks expected heads, all dependencies, review policy, and constraints.
2. Reads/reserves local sequence numbers from `dataset_state`. Creating a branch
   and its first receipt uses ordered catalog and receipt events in one
   transaction. Sequence allocation rolls back with the transaction.
3. Appends immutable events, parent/dependency references, and replaces affected
   projections and child collections. Update heads, conflict state, and local
   contiguous cursor in the same transaction. Advance `next_local_seq` together.
4. Commits once. On any validation, storage-full, or SQL failure, none of those
   changes survive. Never emit a separate best-effort change-log write.

Generate pending receipt/row/mutation IDs before commit. A retry after an
uncertain response uses that mutation UUID to find the committed group and return
success only when the command matches; retain it as a unique local retry key.
An existing entity ID is edited only with explicit expected heads. Reusing a
mutation/event identity with different content is an integrity error, never
`INSERT OR REPLACE`. Database failures must not become successful saves.

Receipt deletion creates a tombstone event with its expected head. Keep a minimal
deleted projection with identity, revision, audit and deletion/conflict
state; remove current item/review children atomically. Historical payloads remain
in the event log. Deletion is therefore not secure erasure. Catalog and alias
deletion are deferred until their reference/collision semantics are implemented.

## 7. Incoming events and conflict projections

These rules constrain the schema now; do not implement networking in this step.

- Validate dataset/version, typed payload, sizes, ranges, review result shape,
  canonical digest, parents, and dependencies before applying. Establish and
  test bounded batch/payload limits before enabling a transport.
- First implementation rejects a batch with missing parents, catalog revisions,
  or origin sequence gaps, returning the missing identities for retry. It does
  not acknowledge or silently discard a partial batch. A future staging inbox
  requires a separate durable validation/cursor contract.
- Apply in dependency order inside a transaction. Each new event must be the
  next contiguous event of its origin. Previously received events are accepted
  only with identical canonical content; identity reuse with different content
  stops sync. Incoming events retain their origin and never consume local seqs.
  Acknowledgements and durable cursors advance only across complete mutation
  groups; replaying part of a known group cannot acknowledge an unseen member.
- Reduce heads by ancestry: a descendant supersedes its ancestors; an ancestor
  replay changes nothing; incomparable heads create a conflict. Clocks and
  arrival order never choose a winner. A tombstone participates in this graph,
  so an old snapshot cannot resurrect a deletion.
- A conflicted receipt has no selected financial candidate. Keep its identity
  shell with `has_conflict = 1`, clear selected item/review children, and expose
  candidates from immutable events in history. Exclude it from spending/prices;
  show that aggregates omit conflicts. Never count both candidate versions.
- A conflicted catalog entity likewise has no effective candidate. Existing
  store/product projection fields may remain only as reference-preserving cache,
  explicitly unavailable for matching/display as a resolved value. Query the
  head/conflict state, never treat cached values as current. If first received
  history is already concurrent, process its ancestors first to create the
  reference-preserving row. Missing complete history is a recovery error.
- Block automatic matching and analytics for receipts referencing a conflicted
  store/product. Unrelated receipts remain usable. Alias conflicts block that
  alias's matching, not independently reviewed receipt amounts. A new dependent
  write waits for a resolved catalog projection; never break a foreign key.
- Independent alias IDs can collide on `(store_id, normalized_name)`. Detect
  this as a business-key conflict even though their revision graphs differ.
  Remove every competing alias projection for that key and retain the events;
  no domain foreign key targets an alias projection. The same removal applies
  to a single alias with multiple revision heads. Inactive aliases do not compete.
  never let arrival order or a SQL unique violation choose a mapping. Resolution
  is one atomic mutation group updating all participating alias aggregates, with
  an event based on each aggregate's current heads. Keep the explicitly selected
  mapping active and deactivate the other aliases; do not physically delete
  their history. Concurrent resolutions can reopen the collision. Implement this
  workflow before enabling alias sync.
- Conflict resolution validates all current heads and creates a new reviewed
  snapshot or explicit tombstone referencing them. If heads changed while the
  comparison screen was open, reopen review. Receipt child replacement,
  conflict updates, incoming cursors, and commits are atomic.

Cursor acknowledgement means a valid event and its conflict/projection outcome
are durable, not that a user has resolved every conflict. On replay after a lost
acknowledgement, data and event counts remain unchanged. Keep all events and
tombstones in v1; compaction needs a later bootstrap/history contract.

## 8. Migrations and integrity checks

- Use generated Drift schema snapshots and migration tests for every released
  version. Verify foreign keys, indexes, integer storage classes, all-or-none
  groups, UUID/enum checks, and receipt/domain rules in addition to column names.
- Cross-row reconciliation, dense order, parent types, review freshness, and
  graph/dependency rules belong in shared transactional repository validation;
  row-level SQL checks cannot substitute for them. Corruption/import validation
  must run these same rules before data becomes queryable.
- After a migration/restore, run `foreign_key_check`, `integrity_check`, and
  domain/event consistency checks. Verify projections, heads, cursor continuity,
  and next sequence against retained history. Stop visibly on inconsistency;
  never repair it by choosing the most recent audit timestamp.
- Validate historical payloads under their supported payload/review-policy
  versions. An upgrade cannot turn an old assertion into a newly performed
  review or demand unavailable images to replay previously accepted history.
  Keep explicit readers for supported old versions; reject unsupported versions
  before changing the database.
- Normal operation may rebuild projections transactionally from validated
  immutable history. Rebuilds preserve all identities, unresolved heads and
  conflict exclusions. They do not create local events or fresh approvals.
- Do not log receipt values/payloads, database contents, paths to imported images,
  or credentials on failure. Diagnostics can identify versions/error codes.

## 9. Backup, restore, and initial pairing

Do not present the app as the only copy of financial history before tested
structured backup/restore exists. Sync propagates deletions and is not backup.

A future versioned backup contains the dataset ID, all canonical events with
parents/dependencies, heads/conflict information, and a manifest with versions,
counts and checksums. Projections can be rebuilt. It contains no receipt images,
OCR dumps, credentials, private keys, peer trust, or an active-device assignment.
Historical origin device IDs remain attached to their events.
Checksums detect corruption, not an authenticated publisher. Export privacy and
password/encryption policy require a separate user-visible decision before UI.

Restore must validate a complete package in isolated temporary storage, rebuild
and check it, then atomically activate it while the old dataset remains recoverable.
Do not restore over a populated active dataset without explicit user choice.
Assign a new device UUID and `next_local_seq = 1`; preserve imported origin IDs,
events, and contiguous history. Old local-origin events become historical foreign
streams. Discard peer cursors/trust and require re-pairing; never continue an old
device's sequence stream. A fresh install or OS transfer must use this identity
reset path, not silently clone a running replica.

Recovery with an existing peer of the same dataset:

1. Compare dataset/protocol identities and per-origin contiguous histories after
   explicit re-pairing. The recovered installation has a distinct device ID.
2. Retain the backup's history and request events absent from it, including later
   events from its former device origin. Do not rewind/reset the peer's history.
3. Exchange recovered-device edits as a new origin stream. Use causal parents
   to advance descendants or expose concurrent edit/delete conflicts normally.
4. Missing required history, reused identities with differing payloads, or
   unsupported versions stop recovery with a clear error. No timestamp-based
   repair, replacement of peer data, or guessed new dataset identity.

Initial pairing may seed an empty installation by replaying one selected dataset
while assigning a fresh local device identity. Two populated independent datasets
cannot be merged automatically. User-visible export/retention and pairing choices
remain separate features; none are implied by the current no-save completion.

## 10. Implementation order and acceptance checks

1. Add independently testable durable value models, range checks, snapshot codec,
   reviewed-command builder, and golden serialization/digest fixtures. Extend
   manual review to the same explicit row/relationship requirements before saves.
2. Add Drift and pin compatible versions after Android/Windows checks. Create
   schema v1, constraints, repository and atomic local events. Start with reviewed
   manual receipts and catalog branch selection; then adapt supported OCR reviews
   through the same command builder. Keep unsupported reviews blocked.
3. Add explicit save and history UI with correction/delete and failure recovery.
   Verify close/reopen on both platforms; never label a temporary review saved.
4. Implement backup/restore and migration checks before relying on real history.
   Add product/alias workflows and deterministic conflicts before network sync.

Required tests for those implementation steps (not claimed as passing today):

- Signed-64-bit edges, out-of-range `BigInt`s, overflow-prone sums, exact return
  rounding, unknown/partial quantities, invalid signs and adjustment reasons.
- Impossible dates, date-only null UTC, timed UTC round trip, DST gaps/folds and
  unsupported timezone ranges; receipt order uses civil dates without inventing
  midnight instants.
- Cross-branch product/alias references, cross-receipt parents, non-product
  parents, duplicate positions/IDs, alias collisions and changed normalizers.
- Manual/OCR stale approvals after branch, row, quantity, target/order, or evidence
  edits; source omissions, missing image, unsupported findings; totals matching
  alone must never authorize a save. Canonical encoding and stable row mappings.
- Rollback fault injection between sequence allocation, log append, children,
  review metadata, heads, and commit; reopen recovery and retry without duplicates.
- Multiple pending writers, stale base heads, full child replacement, immutable
  payloads, no-event UI cancellation, storage-full errors and migration rollback.
- Projection replay in different valid dependency orders, unchanged duplicate
  events, origin gaps, changed-content identity reuse, missing dependencies,
  concurrent edits/deletes/resolutions, catalog/alias conflicts and analytic
  exclusions. Clock changes must not affect any outcome.
- Snapshot backup consistency, malformed/future-version restore rejection,
  fresh restore identity, preserved old events, unsynced peer changes surviving
  recovery, and refusal to merge unrelated populated datasets.
- On Android and Windows, original image bytes unchanged, no image/OCR payload in
  database/events/backup/logs, successful save/cancel/error cleanup, and Android
  automatic backup/transfer exclusion. SQLite tests do not replace these checks.
