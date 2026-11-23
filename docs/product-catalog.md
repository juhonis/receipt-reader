# Store-scoped product and alias storage

Status: Finnish catalog management and explicit reviewed receipt linking implemented
on 2026-11-17. Existing receipts are never automatically matched or rewritten.
[Purchase history and trends](purchase-history.md) and editable
[product categories](product-categories.md) are now available.

## Identity and matching rules

Products have durable UUIDs and one immutable store-branch owner. Identical names
do not merge products, even within a branch. A product has a corrected canonical
name and optional package quantity represented as an integer value, scale 0..6
and unit (`piece`, `kg`, `litre`). The package group is all present or all absent;
its quantity must be positive. These are package details, not a receipt's purchased
quantity. Package metadata alone never supplies the purchased quantity required
for [price comparisons](purchase-history.md).

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
`ProductAliasSnapshot` and `ProductAliasDocument` values and canonical codecs.
Uncategorized product documents and alias documents retain v1; categorized product
documents use v2. Categories are optional reviewed labels, not product identities.
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
sequence stamp. The app exposes these calls through `CatalogService`; the
workspace adapter queues them with receipt reads/writes and backup
preparation/activation.

## Schema and integrity

Schema 4 adds strict `products`, `product_aliases` and `catalog_mutations` tables,
indexes and immutable retry triggers. A composite foreign key enforces alias
branch ownership; a partial unique index enforces active alias keys. Event and
head constraints now accept `product` and `alias` snapshot kinds. Receipt tables,
row identities and released canonical receipt/event bytes are unchanged.

Schema 5 rebuilds receipt items to allow product links only on product rows, with
a composite foreign key enforcing the product and receipt branch. Canonical receipt
bytes remain v1; they already defined optional versioned product links.

Migrations from schemas 1, 2, 3 and 4 run transactionally with foreign keys disabled
only outside the DDL transaction, followed by foreign-key validation and atomic
version assignment. Existing installation identity, history, tombstones and retry
results survive. A failed upgrade rolls back DDL, values and schema version so
opening can retry. Released schema snapshots remain committed unchanged, alongside
the schema-4 and schema-5 snapshots and generated migration verification helper.

Current schema 7 additionally permits categorized product-v2 events; schema 6
introduced receipt-level review policy 3. Migrations now support source schemas
1–6, with released snapshots preserved. See [product categories](product-categories.md)
for current classification behavior and compatibility.

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
- Datasets containing products or aliases, but no linked receipt history, export
  inner version 2. It adds
  `products` and `aliases` counts after the existing count fields and includes all
  catalog events/heads, inactive aliases and historical product/alias edits.
  Alias events have both store and product revision dependencies.
- A linked receipt snapshot anywhere in retained history selects inner version 3,
  including after unlinking or deleting its current receipt. It retains the v2
  catalog manifest and permits one branch plus distinct product dependencies per
  receipt. Restore verifies dependency kinds, identities, ownership and revisions.
- Retained categorized product-v2 events select inner version 4, including after
  category clearing. Current-label reporting can regroup older explicitly linked
  rows without rewriting those receipts.
- Older builds reject unsupported inner versions; they cannot silently discard links.
  Returning to an older executable after migrating a database also fails its
  schema-version check. Keep the newer app available to restore these backups.

Recovery rebuilds schema 7 and all catalog projections, audits complete history,
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
flutter test integration_test/catalog_review_test.dart -d windows
flutter test integration_test/product_catalog_test.dart -d windows
flutter test integration_test/catalog_review_test.dart -d emulator-5554
flutter test integration_test/product_catalog_test.dart -d emulator-5554
```

Run `dart test` and `dart analyze` in both `packages/receipt_domain` and
`packages/receipt_storage`. The catalog tests cover canonical values, branch
isolation, package rules, exact suggestions, separate equal-name identities,
stale edits, deactivation/reactivation/remapping, collisions, global mutation IDs,
write rollback, corrupt projections, modified backup histories, repeated encrypted
restore/write cycles and a catalog write invalidating a prepared replacement.
Migration tests include populated released schemas 1/2/3/4 and failed-upgrade retry.
Current verification includes the existing suites plus explicit product selection,
catalog create/edit/deactivate/remap, frozen retries, stale writes, pagination,
large-text layouts, OCR confirmation binding and linked-history recovery tests.
Verified on 2026-11-17: 124 app tests, 46 domain tests and 175 storage tests pass,
with clean analysis. Both native catalog workflows pass on Windows and Android
in airplane mode. Normal Windows release/Android debug builds and the prior
emulator network setting are restored after verification.

The native test uses a guarded `catalog-storage-smoke-*` app-support directory.
It exercises package metadata, encrypted file I/O, workspace activation, historical
retries, fresh-origin alias writes, reopen, stale edits and returning to the prior
dataset. It never opens or clears the normal app database. Run Android offline,
restore the prior airplane setting, and rebuild/reinstall normal app entry points
afterwards as described in [Windows development](windows-development.md).

## Using the catalog and linking receipts

Open **Tuotteet ja kuittinimet** on the home screen and select an existing branch.
Save a receipt first if the branch does not exist. Products and aliases have
separate paginated lists (30 entries). Add or edit a product's canonical name and
optional exact package quantity/unit, then check the review box before saving.
Package details describe the package, not the quantity bought on a receipt.
A short identity code distinguishes independent same-name products.

Add a kuittinimi with the printed receipt name and an explicitly selected product.
You can remap or deactivate it later. Its normalized key and branch are immutable;
for another spelling, deactivate the old key and create another. A collision or
stale edit requires closing and reloading; it never replaces a different mapping.
After an uncertain save, fields freeze and retry sends the identical reviewed
command and mutation identity. Closing refreshes the list because the write may
already have committed.

During manual or OCR review, **Valitse tuote** opens the branch's products. An exact
active alias appears as a suggestion and requires an explicit tap. Cancel preserves
the previous choice; **Jätä ilman tuoteliitosta** explicitly removes it. A new branch
cannot use catalog products until its first receipt is saved. Linking is optional.
Changing the row name, row kind or branch clears an inapplicable choice and review
checks. The final confirmation shows each product row's link or unlinked status.
A catalog edit after selection makes a save stale; reopen and review current data.

History displays the current catalog label, with a notice if its revision is newer
than the receipt's recorded link. Fetch failure does not hide financial history.
Manual corrections retain row identity, raw name, amounts, quantities and related
rows. OCR corrections retain the fresh-image evidence workflow and start with no
product links: select them again and explicitly map saved row identities. Changing
an OCR row's identity also clears its product. Links are included in the reviewed
snapshot digest, so changing one invalidates the final approval. Every linked
save depends on the reviewed branch and distinct current product revisions.
Later catalog changes do not rewrite the saved receipt or its historical links.

The native UI test uses guarded `catalog-review-smoke-*` app-support storage. It
creates products and aliases through Finnish screens, explicitly accepts a
suggestion, saves a linked receipt, reviews its removal while retaining row
identity, and restores the encrypted full history. The storage smoke separately
checks linked receipt replay after encrypted activation and previous-data recovery.
Neither test opens or clears the normal database.

## Remaining work

[Purchase history and prices](purchase-history.md) now reads explicitly linked rows,
with full date-range summaries and bounded calendar price-range charts, exact
quantities, linked item discounts, deposit exclusion and separate unit/revision
groups. [Receipt spending](spending-summary.md) separately uses complete receipt
totals, including unlinked products. Further package conversions remain open.
Windows OCR packaging and sync transport/conflict workflows remain separate work.
