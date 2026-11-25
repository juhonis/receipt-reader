# Architecture and invariants

Shared design constraints for Android and Windows. For current functionality and
next work, use [the roadmap](plan.md). The [storage contract](local-storage-contract.md)
defines persistence details; feature contracts are indexed in [the docs](README.md).

The local import/review/storage/analytics workflows are implemented. Camera capture,
pairing, network transport and conflict-resolution UI remain planned. Requirements
for those features below describe the intended behavior, not existing capabilities.
Optional GitHub update checks are separate from receipt synchronization and must
preserve an offline core. See [releases and updates](releases.md).

Products belong to a branch. Explicit comparison groups compare equivalent products
across branches without merging identities or modifying receipt amounts. Category
and comparison-group edits may regroup earlier linked purchases. Money stays in
integer cents; quantities and weighted unit-price calculations use exact arithmetic.

## Data architecture and financial rules

### Numeric and Date Conventions

- Store posted monetary amounts as **integer cents**, never SQLite `REAL` or binary floating-point values.
- Store quantities as fixed-point integers with an explicit scale and unit (`piece`, `kg`, `litre`, or `unknown`). Preserve unknown quantities rather than inventing `1`.
- Represent unit rates with higher precision, for example integer millionths of EUR per unit. Calculate with integer/decimal arithmetic and explicitly test rounding to cents.
- The printed line total is the recorded amount; `quantity × unit rate` is a separate validation check, not a reason to silently overwrite it.
- Use signed line amounts: purchases and deposit charges are normally positive; discounts, refunds, and deposit returns are negative. Preserve return quantities consistently.
- Store the printed local receipt date/time, its precision, and the timezone. Derive a UTC instant only when unambiguous. Do not invent a time for date-only receipts or silently resolve ambiguous daylight-saving times.
- Audit timestamps use UTC milliseconds, but timestamps do not determine synchronization ordering.

### Logical Drift Schema

The following is a logical overview, not migration-ready SQL. The [local storage contract](local-storage-contract.md) defines concrete representations, constraints, reviewed-snapshot requirements, atomic writes, causal conflicts, and recovery behaviour for the first Drift implementation. The implemented local schema has generated snapshots and migration tests. The sync tables below remain planned.

| Table | Main fields and invariants |
| :--- | :--- |
| `dataset_state` | Shared `dataset_id`, unique installation `device_id`, and transactional monotonic `next_local_seq`. Sequence numbers order only one device's events; restore must not reuse an old device identity/sequence stream. |
| `stores` | UUID `id`, branch display name, chain, optional address/printed identifier, audit timestamps. Detecting `PRISMA` alone does not resolve a branch. |
| `products` | UUID `id`, `store_id`, canonical name, optional known package quantity/unit, audit timestamps. Products never cross store boundaries. |
| `product_aliases` | UUID `id`, `store_id`, normalized observed name, `product_id`. Unique alias within a store; collisions require review rather than automatic merging. |
| `receipts` | UUID `id`, `store_id`, printed local date/time and precision, timezone, nullable UTC instant, `currency = EUR`, `total_amount_cents`, validation results, parser/OCR engine versions, `reviewed_at`, current revision head(s), audit timestamps, deletion/conflict state. |
| `receipt_items` | UUID `id`, `receipt_id`, position, line type, optional parent item, nullable `product_id`, raw and normalized names, nullable fixed-point quantity/unit and unit rate, signed `line_total_cents`, warnings. |
| `change_log` | Unique `(origin_device_id, origin_seq)` event identity, entity kind/id, parent revision IDs, immutable full snapshot or tombstone. Written transactionally with local mutations; incoming events retain their original identity and are not re-emitted as local edits. |
| `sync_conflicts` | Entity identity, competing revision heads, detection metadata, and resolution state. Preserve candidate snapshots; do not silently discard either version. |
| `sync_peers` | Peer identity, pinned certificate identity, non-secret pairing metadata, and per-origin committed cursors. Secrets live in secure storage, not ordinary database columns. |

### Line Types and Reconciliation

Support normal receipt structures from the first parser iteration:
- `product`: ordinary or weighed goods, including returned goods.
- `discount`: item-specific or receipt-wide discount; optional parent product reference.
- `deposit`: deposit charge or refund; optional parent product reference.
- `adjustment`: explicitly identified receipt rounding or another user-confirmed adjustment.

Every persisted line contributes its signed amount **exactly once**:

`sum(line_total_cents) == total_amount_cents`

If a printed product amount is already net of a discount, do not also subtract that discount as a financial line. Preserve explanatory information separately. Payment methods, tendered cash, change, and VAT summaries are not purchased-item amounts.

Require exact cent reconciliation. A discrepancy is not accepted through an unexplained tolerance. Any rounding adjustment must be printed or explicitly entered and identified by the user.

Save only after store branch, date, total, and rows have been reviewed and reconciliation succeeds. An unresolved capture remains a temporary review session, not an approved receipt; image-backed draft persistence is out of scope.

### Product Identity and Price History

- Match aliases only within the confirmed branch. Normalization preserves meaningful package sizes and variants.
- Unknown names remain unmatched until reviewed; fuzzy matching may suggest, but must not silently merge products.
- Enforce that linked products, aliases, and receipts belong to the same store.
- Corrections can happen on either platform and synchronize in both directions. Concurrent alias mappings or store/product changes require review just like receipt conflicts; independent UUIDs alone do not identify duplicate real-world products or branches.
- Distinguish printed shelf/unit price from effective price after linked discounts. Exclude deposits from product price trends.
- Do not allocate receipt-wide discounts to individual products without a documented rule. Label such observations accordingly.
- Compare only compatible units/package sizes. Receipts without enough information still count toward spending but may be excluded from normalized price charts.

---

## OCR, Parsing & Review

### Pipeline

```text
Planned Android private camera capture OR existing Android/Windows image import
  -> bundled offline OCR adapter (normalized text, blocks, lines, bounding boxes)
  -> geometry-aware parsing and receipt-section classification
  -> store branch and date candidates
  -> signed financial rows, quantities, rates, and receipt total
  -> independent validation results and row warnings
  -> mandatory user review and correction
  -> atomic SQLite save + change-log entry
  -> app-owned temporary image cleanup (never delete an imported original)
```

Regexes identify candidates, not guaranteed facts. Use geometry to join names, quantities, and right-aligned prices, including wrapped descriptions. Separate receipt totals from payment totals and VAT sections.

Recognize Finnish decimal commas, Unicode spaces, negative amounts, and common OCR confusions. Never globally replace letters with digits in product names. Store-chain recognition (`PRISMA`, `S-MARKET`, `SALE`, `ALEPA`) must be followed by branch resolution or explicit user selection.

### Validation UX

Replace `confidence_score` and percentage badges with independent states:
- **Totals:** matched / mismatched / missing.
- **Store:** branch confirmed / needs confirmation.
- **Date:** valid / ambiguous / missing.
- **Rows:** incomplete fields, uncertain associations, quantity/rate inconsistencies, or unclassified candidate rows.
- **Review:** unreviewed / user-confirmed.

Example Finnish messages:
- `Summat täsmäävät — tarkista tuotteet` (arithmetic matches; still review products).
- `Summat eivät täsmää` with the exact discrepancy in EUR.
- `Vahvista myymälä` or `Tarkista päivämäärä`.

Recompute validation after every edit. Arithmetic success must never hide unresolved row warnings or imply a statistical accuracy guarantee. Users must resolve required fields and explicitly acknowledge remaining non-blocking warnings before saving.

### Fixture and Test Strategy

- Begin with 2–3 receipts to establish the fixture format, then expand to a representative corpus before accepting parser behaviour.
- Fixtures contain OCR text **and bounding boxes**, image dimensions/orientation where relevant, and manually verified expected output and warnings.
- Use synthetic or anonymized committed fixtures. Personal receipt images and raw OCR dumps are not logged or committed by default; any development-only fixture export requires explicit consent.
- Cover discounts, deposits/refunds, returns, multi-buy pricing, weighed goods, duplicate products, wrapped names, missing/duplicated rows, ambiguous totals, and poor OCR.
- Test Finnish dates, decimal separators, rounding, malformed inputs, and daylight-saving ambiguity.
- Assert extracted fields, financial rows, reconciliation, and warnings—not just a summary status.
- Keep parser tests independent of Flutter and maintain Android camera/import and Windows import/OCR integration tests. Run comparable fixtures through each selected OCR backend and check the normalized geometry contract.

---

## Secure Bidirectional Local Sync

### Roles and Pairing

- Windows runs a user-enabled HTTPS endpoint on an available port; Android initiates connections and both pushes and pulls changes. Transport roles do not limit editing rights or determine which data wins.
- Windows creates a cryptographically random, short-lived, single-use pairing secret and shows a QR code containing protocol version, endpoint, certificate/public-key fingerprint, secret, and expiry.
- Android pins the advertised identity before transmitting the pairing secret. The QR/manual fingerprint exchange is the trust anchor; discovery never establishes trust.
- Successful pairing consumes the temporary secret and creates a separate persistent device credential stored securely on both platforms.
- Provide peer revocation, credential rotation, and explicit re-pairing. Certificate identity changes require confirmation/re-pairing, never automatic trust.
- Manual pairing provides the same authenticated information as QR pairing; typing only an IP address is insufficient.
- Enforce authentication, payload/schema validation, request-size limits, timeouts, and bounded batches. Do not expose secrets in logs or discovery records.

### Multi-Writer Change Protocol

Do not use wall-clock timestamps as delta cursors or last-write-wins conflict resolution.

1. Each local mutation on either device appends an immutable event with its device-scoped sequence and the entity revision(s) the edit was based on, in the same SQLite transaction as the domain mutation. Editing an old screen must detect a changed base rather than silently overwrite it.
2. Changes contain full store/product/alias snapshots, full receipt snapshots including all current items, or supported deletion tombstones. A receipt is the conflict unit: do not merge rows independently. Store/product deletion is deferred in the MVP.
3. Devices exchange dataset/protocol identities and committed per-origin cursors, then transfer missing events in bounded batches in both directions. Validate causal parents and catalog dependencies; missing dependencies must be requested or safely staged, not discarded or applied with broken references.
4. Receiving devices persist events, apply valid projections or record conflicts, and advance their contiguous per-origin cursors transactionally. Cursors acknowledge durable receipt of events, not user resolution of conflicts. A receipt snapshot replaces its item collection atomically when selected as the current version.
5. Acknowledge only committed batches. Deduplicate by event identity so lost responses and replay are harmless. Received events keep their original identity to prevent sync feedback loops. Reject cursor gaps, identity mismatches, invalid dependencies, and incompatible versions explicitly.
6. Use revision ancestry to distinguish a newer descendant from a concurrent edit: descendants can advance automatically, ancestors are historical, and incomparable heads create a conflict. Numeric revision counts or timestamps alone cannot establish ancestry.
7. Receipt deletion is a versioned tombstone. A concurrent edit versus deletion is a conflict; an old replay cannot resurrect a deleted receipt. Resolving a conflict creates a new event referencing all competing heads, containing the selected/reviewed snapshot or deletion.

Keep immutable events and tombstones in the MVP, with storage monitoring. Defer compaction until a consistent snapshot/bootstrap protocol exists. Initial pairing seeds an empty installation by replaying the chosen dataset's history, preserving event identities but assigning the new installation a distinct device identity. Never automatically merge populated unrelated datasets.

Restore must assign a fresh local device identity and preserve imported event identities. If an existing peer contains changes absent from the backup, recovery must reconcile the histories and surface conflicts; it must not reset the peer or overwrite its newer work. Specify and test this recovery procedure before enabling sync. Missing required history must stop sync with an explicit recovery path rather than guessing.

### Conflict UX and Analytics

- Show both receipt versions with origin device, audit time for context only, row differences, and any delete-versus-edit state.
- Let the user keep either version or manually produce a reviewed, reconciled version; deletion is an explicit choice. Never automatically choose the latest wall-clock timestamp.
- Retain candidate snapshots until resolution is durably recorded. Concurrent resolutions can themselves conflict and must follow the same rules.
- Unresolved receipt conflicts remain visible in history but are excluded from aggregate spending and price trends, with a clear warning that totals are incomplete. Never count both versions.
- Catalog conflicts and alias uniqueness collisions block affected automatic matching; unrelated records remain usable. Define deterministic projection rules for affected references before implementing sync.

### Required Sync Tests

- Retry after a lost acknowledgement; duplicate batch; interrupted upload.
- App crash during local mutation or incoming-event application on either platform.
- Offline edit/delete followed by reconnect; removed receipt items; stale replay after deletion.
- Clock skew, equal timestamps, and clock changes have no effect on ordering.
- Invalid certificate/pin, expired pairing secret, revoked device, malformed payload, and oversized request.
- Changed IP, blocked multicast, unavailable desktop, firewall restrictions, and incompatible protocol.
- Independent imports/edits on each device followed by two-way exchange without duplicate events or echo loops.
- Sequential edits versus concurrent receipt edits, item removals, delete-versus-edit conflicts, catalog/alias collisions, and concurrent conflict resolutions.
- Missing dependencies, partial causal histories, deterministic projections, and exclusion of unresolved conflicts from analytics.
- Empty-device bootstrap, refusal to merge unrelated populated datasets, and backup restore/re-pairing without loss of unsynced peer changes.

---

## Privacy, Retention & Recovery

- Capture only into private application cache; do not export to the gallery. Import originals read-only and never delete or modify them. Explain that source images may remain in the user's gallery, file storage, or backups outside the app's control.
- Delete temporary images on save, cancel, review exit, and error paths. Run stale-cache cleanup at startup after crashes; immediate deletion while the process is dead cannot be guaranteed.
- Exclude temporary captures from OS backups where supported. Verify platform behaviour rather than promising secure erasure.
- Do not retain full OCR dumps in production. Keep only structured receipt fields, necessary per-line names, validation metadata, and parser version.
- Redact receipt contents and credentials from logs, crash reports, and diagnostics. No cloud OCR or app-owned automatic telemetry. Bundled SDK diagnostics must be assessed separately when permissions change; see [dependency disclosures](dependency-licenses.md).
- Ordinary SQLite storage is not application-level encryption. Document reliance on device/OS storage protection; separately evaluate database encryption if stronger at-rest protection is required.
- Provide explicit user-initiated structured export/backup and tested restore. Warn that backups retain financial data and that image deletion does not remove those records.
- Define Android OS database-backup policy explicitly; do not silently rely on cloud backup. Export destination and any encryption/password policy must be clear before changing the existing password-protected backup workflow.
- Define user-visible dataset deletion, including replicas, credentials, retained change logs, and the limits of deleting separately exported backups.
