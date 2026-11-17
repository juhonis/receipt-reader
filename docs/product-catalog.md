# Store-scoped product and alias storage

Status: storage foundation implemented on 2026-11-17. Product-management screens,
reviewed receipt matching/correction and price trends are the next increment.
The normal receipt save paths still reject product links until that workflow is
implemented. Existing receipts are not automatically matched or rewritten.

## Identity and matching rules

Products have durable UUIDs and one immutable store-branch owner. Identical names
do not merge products, even within a branch. A product has a corrected canonical
name and optional package quantity represented as an integer value, scale 0..6
and unit (`piece`, `kg`, `litre`). The package group is all present or all absent;
its quantity must be positive. These are package details, not a receipt's purchased
quantity, and no price comparison is inferred yet.

Aliases map exact normalized receipt names to products in the same branch.
They reuse `normalizeReceiptNameV1`: trim, collapse whitespace and lowercase,
preserving diacritics, punctuation, sizes and variants. No fuzzy matching or
accent folding is performed. Normalizer version 1 is recorded and validated.

An alias's UUID, branch and normalized key remain fixed. Correcting its spelling
means explicitly deactivating that identity and creating another key. Its product
target and active state can change through a new reviewed revision. Inactive
aliases retain history and never produce matches. Two active identities cannot
claim the same `(store_id, normalized_name)`; a collision fails without replacement.
Changing the product target affects future suggestions; it does not alter receipts.

This first API supports individual mutations, not a multi-alias conflict
resolution transaction. Replacing an active mapping can edit that alias's target;
switching between separate alias identities requires explicit deactivation first.
Deterministic concurrent conflict resolution remains required before sync.

## Storage-facing APIs

`receipt_domain` adds immutable `ProductSnapshot`, `ProductDocument`,
`ProductAliasSnapshot` and `ProductAliasDocument` values and canonical v1 codecs.
Documents capture the expected previous head (null only on creation), reviewed
branch revision, review time and app version. Alias documents also capture the
reviewed product revision. The application must present and confirm these values
before calling the storage APIs; these types do not implement a UI confirmation.

The public `ProductCatalog` extension on `ReceiptRepository` adds:

- `saveProduct(document, mutationId: ...)` and `saveAlias(document, mutationId: ...)`.
- `readProduct(id)` and `readAlias(id)`, with canonical event/projection checks.
- `products(storeId, limit:, offset:)` and `aliases(storeId, activeOnly:, limit:,
  offset:)`, with deterministic ordering and pages of 1..200 records.
- `matchAlias(storeId, receiptName)`, returning a suggestion with both alias and
  current product revisions. It never links a receipt row or creates catalog data.

Each write reparses canonical bytes at the storage boundary, validates the
expected head, immutable ownership and current branch/product dependencies, and
commits one full snapshot event with its sequence, parent, dependencies, effective
projection, selected head, cursor and retry metadata in one transaction. Audit
times may go backwards; causal revision ancestry determines order.

Mutation UUIDs are unique across receipt saves, deletion and catalog writes.
Identical retries return the original result after edits, reopen or backup restore.
Reusing a UUID for a different command fails. Stale edits, cross-branch references,
missing products and alias collisions fail before committing an event. Catalog
writes also invalidate a prepared workspace restore preview through the shared
sequence stamp. The app's serialized storage adapter will need catalog methods
when the UI is added.

## Schema 4 and integrity

Schema 4 adds strict `products`, `product_aliases` and `catalog_mutations` tables,
indexes and immutable retry triggers. A composite foreign key enforces alias
branch ownership; a partial unique index enforces active alias keys. Event and
head constraints now accept `product` and `alias` snapshot kinds. Receipt tables,
row identities and released canonical receipt/event bytes are unchanged.

Migrations from schemas 1, 2 and 3 run transactionally with foreign keys disabled
only outside the DDL transaction, followed by foreign-key validation and atomic
version assignment. Existing installation identity, history, tombstones and retry
results survive. A failed upgrade rolls back DDL, values and schema version so
opening can retry. Released schema snapshots remain committed unchanged, alongside
the new schema-4 snapshot and generated migration verification helper.

The complete integrity audit replays catalog history in causal order. It checks
canonical bytes/digests, parents, dependency types/identities, immutable ownership
and alias keys, active-key collisions, review/audit metadata, effective fields,
heads and mutation results. Corrupt projections/history fail opening or exporting;
the repository never silently resets them. Catalog deletion and moving a product
between branches have no API.

## Backup compatibility

The password-protected `.rrbackup` envelope and crypto suite remain version 1.
The **inner structured format** is independently versioned:

- Datasets with no catalog records continue to export the exact v1 format.
  Existing v1 packages and the independent encrypted fixture still restore.
- Datasets containing products or aliases export inner version 2. It adds
  `products` and `aliases` counts after the existing count fields and includes all
  catalog events/heads, inactive aliases and historical product/alias edits.
  Alias events have both store and product revision dependencies.
- Older builds reject inner version 2; they cannot silently discard catalog data.
  Returning to an older executable after migrating a database also fails its
  schema-version check. Keep the newer app available to restore these backups.

Recovery rebuilds schema 4 and all catalog projections, audits complete history,
and compares the canonical manifest. Original event bytes and retry results remain
intact. Only the active installation identity is fresh. Subsequent catalog edits
start the new device's stream at sequence 1 and retain historical parents.
Modified packages with recomputed checksums still fail historical validation.
All existing encrypted backup limits and private-storage requirements apply.

## Verification

From the repository root, run the app checks and native synthetic smoke:

```powershell
flutter analyze
flutter test
flutter test integration_test/product_catalog_test.dart -d windows
flutter test integration_test/product_catalog_test.dart -d emulator-5554
```

Run `dart test` and `dart analyze` in both `packages/receipt_domain` and
`packages/receipt_storage`. The catalog tests cover canonical values, branch
isolation, package rules, exact suggestions, separate equal-name identities,
stale edits, deactivation/reactivation/remapping, collisions, global mutation IDs,
write rollback, corrupt projections, modified backup histories, repeated encrypted
restore/write cycles and a catalog write invalidating a prepared replacement.
Migration tests include populated released schemas 1/2/3 and failed-upgrade retry.
Verified on 2026-11-17: 45 domain tests, 163 storage tests and 115 app tests pass,
with clean analysis for all three. The native catalog smoke passes on Windows
and Android in airplane mode; normal app builds and the prior network setting
were restored afterwards.

The native test uses a guarded `catalog-storage-smoke-*` app-support directory.
It exercises package metadata, encrypted file I/O, workspace activation, historical
retries, fresh-origin alias writes, reopen, stale edits and returning to the prior
dataset. It never opens or clears the normal app database. Run Android offline,
restore the prior airplane setting, and rebuild/reinstall normal app entry points
afterwards as described in [Windows development](windows-development.md).

## Remaining work

Add Finnish product/alias management, explicit selection during manual/OCR review,
reviewed correction of stored receipt links, and SQL/causal validation of those
links. Preserve source provenance and receipt/row identities. Only then build
comparable product history and price trends. Windows OCR packaging and all sync
transport/conflict workflows remain separate work.
