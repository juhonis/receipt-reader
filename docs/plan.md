# PLAN.md: Local-First Receipt Tracker (S-Kaupat & Finnish Focus)

## 1. Project Overview & MVP Scope

A privacy-first receipt, spending, and product-price tracker built with **Flutter** for **Android** and **Desktop** (Windows, macOS, Linux).

### Guiding Principles
1. **Offline core:** Capture, OCR, parsing, review, storage, and analytics work without internet access, including first-run OCR. Optional synchronization uses only the local network.
2. **No retained receipt images:** Images exist only during capture/review in memory or private temporary storage. Structured receipt data is retained locally. This is not a guarantee of secure erasure from flash storage.
3. **Explicit validation, not accuracy percentages:** Matching totals verifies arithmetic, not product identity or transcription accuracy. Users review every receipt before saving.
4. **Store-specific products:** Product identities belong to a particular store branch (`Prisma Kaari != Prisma Jumbo`). No cross-store product merging in the MVP.
5. **One authoritative editor:** Android owns all edits; desktop is a read-only replica with local analytics. This avoids bidirectional conflict resolution in the MVP.
6. **Authenticated, encrypted local sync:** No cloud servers or accounts. Local Wi-Fi is not assumed to be trusted.

### MVP Boundaries
- One Android dataset paired with one desktop replica. Replacement/re-pairing must be explicit; multiple writers and merging existing datasets are out of scope.
- Android supports camera capture, review, corrections, deletion, and product-alias management.
- Desktop supports history, search, charts, and synchronization, but not capture, OCR, or editing.
- Currency is EUR; UI is Finnish. Receipt dates use Finnish conventions and `Europe/Helsinki` interpretation.
- Single-image capture is the first vertical slice. Long receipts must be rejected or clearly flagged when incomplete; multi-shot stitching is a later feature.
- Basic backup/export and restore are required before relying on the app as the only copy of financial history. Sync is not a backup because deletions propagate.

---

## 2. Tech Stack & Platform Constraints

| Component | Technology | Requirements |
| :--- | :--- | :--- |
| Framework | Flutter / Dart | Shared domain logic and UI where appropriate; verify supported SDK versions when initializing. |
| Database | Drift / SQLite | Transactions, foreign-key enforcement, migrations, reactive queries, and desktop support. |
| Android capture | `camera` | Private temporary files only; platform-specific cleanup. |
| Android OCR | `google_mlkit_text_recognition` | Explicitly configure a bundled Latin-script model and verify first-run operation in airplane mode. Not the desktop OCR solution. |
| Desktop sync server | `shelf` with Dart HTTPS server support | TLS and certificate/public-key pinning; never transmit credentials or receipts over plaintext HTTP. |
| Android sync client | Dart HTTP client with explicit pin validation | Restrict any self-signed certificate exception to the paired identity; never disable verification globally. |
| Pairing / discovery | QR pairing; optional `nsd` / `multicast_dns` | Discovery is optional and untrusted. Manual pairing must work without multicast. |
| Secure credential storage | Platform-backed secure storage | Validate support and behaviour on each desktop OS before selecting the package. |
| Charts | `fl_chart` | Store-specific comparable price observations. |
| State management | `flutter_riverpod` | Keep parser, financial rules, and sync logic independently testable. |

Do an early platform spike for bundled OCR, HTTPS pinning, secure storage, firewall requirements, and macOS sandbox/network entitlements. Pin compatible dependency versions after these checks.

---

## 3. Data Architecture & Financial Rules

### 3.1 Numeric and Date Conventions
- Store posted monetary amounts as **integer cents**, never SQLite `REAL` or binary floating-point values.
- Store quantities as fixed-point integers with an explicit scale and unit (`piece`, `kg`, `litre`, or `unknown`). Preserve unknown quantities rather than inventing `1`.
- Represent unit rates with higher precision, for example integer millionths of EUR per unit. Calculate with integer/decimal arithmetic and explicitly test rounding to cents.
- The printed line total is the recorded amount; `quantity × unit rate` is a separate validation check, not a reason to silently overwrite it.
- Use signed line amounts: purchases and deposit charges are normally positive; discounts, refunds, and deposit returns are negative. Preserve return quantities consistently.
- Store the printed local receipt date/time, its precision, and the timezone. Derive a UTC instant only when unambiguous. Do not invent a time for date-only receipts or silently resolve ambiguous daylight-saving times.
- Audit timestamps use UTC milliseconds, but timestamps do not determine synchronization ordering.

### 3.2 Logical Drift Schema

The following is a schema contract, not migration-ready SQL. Add constraints, indexes, and migration tests during implementation.

| Table | Main fields and invariants |
| :--- | :--- |
| `dataset_state` | Persistent `dataset_id`, Android `source_device_id`, and transactional monotonic `next_change_seq`. A restore must not silently reuse an older sequence under an existing sync identity. |
| `stores` | UUID `id`, branch display name, chain, optional address/printed identifier, audit timestamps. Detecting `PRISMA` alone does not resolve a branch. |
| `products` | UUID `id`, `store_id`, canonical name, optional known package quantity/unit, audit timestamps. Products never cross store boundaries. |
| `product_aliases` | UUID `id`, `store_id`, normalized observed name, `product_id`. Unique alias within a store; collisions require review rather than automatic merging. |
| `receipts` | UUID `id`, `store_id`, printed local date/time and precision, timezone, nullable UTC instant, `currency = EUR`, `total_amount_cents`, validation results, parser version, `reviewed_at`, revision, audit timestamps, `is_deleted`. |
| `receipt_items` | UUID `id`, `receipt_id`, position, line type, optional parent item, nullable `product_id`, raw and normalized names, nullable fixed-point quantity/unit and unit rate, signed `line_total_cents`, warnings. |
| `change_log` | Monotonic `seq`, entity kind/id, entity revision, immutable full snapshot or tombstone. Written in the same transaction as the domain mutation. |
| `sync_peers` | Peer identity, pinned certificate identity, non-secret pairing metadata, acknowledged cursor. Secrets live in secure storage, not ordinary database columns. |

### 3.3 Line Types and Reconciliation

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

### 3.4 Product Identity and Price History
- Match aliases only within the confirmed branch. Normalization preserves meaningful package sizes and variants.
- Unknown names remain unmatched until reviewed; fuzzy matching may suggest, but must not silently merge products.
- Enforce that linked products, aliases, and receipts belong to the same store.
- All corrections happen on Android and are synchronized to desktop.
- Distinguish printed shelf/unit price from effective price after linked discounts. Exclude deposits from product price trends.
- Do not allocate receipt-wide discounts to individual products without a documented rule. Label such observations accordingly.
- Compare only compatible units/package sizes. Receipts without enough information still count toward spending but may be excluded from normalized price charts.

---

## 4. OCR, Parsing & Review

### 4.1 Pipeline

```text
Private camera capture
  -> bundled on-device OCR (text, blocks, lines, bounding boxes)
  -> geometry-aware parsing and receipt-section classification
  -> store branch and date candidates
  -> signed financial rows, quantities, rates, and receipt total
  -> independent validation results and row warnings
  -> mandatory user review and correction
  -> atomic SQLite save + change-log entry
  -> temporary image cleanup
```

Regexes identify candidates, not guaranteed facts. Use geometry to join names, quantities, and right-aligned prices, including wrapped descriptions. Separate receipt totals from payment totals and VAT sections.

Recognize Finnish decimal commas, Unicode spaces, negative amounts, and common OCR confusions. Never globally replace letters with digits in product names. Store-chain recognition (`PRISMA`, `S-MARKET`, `SALE`, `ALEPA`) must be followed by branch resolution or explicit user selection.

### 4.2 Validation UX

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

### 4.3 Fixture and Test Strategy
- Begin with 2–3 receipts to establish the fixture format, then expand to a representative corpus before accepting parser behaviour.
- Fixtures contain OCR text **and bounding boxes**, image dimensions/orientation where relevant, and manually verified expected output and warnings.
- Use synthetic or anonymized committed fixtures. Personal receipt images and raw OCR dumps are not logged or committed by default; any development-only fixture export requires explicit consent.
- Cover discounts, deposits/refunds, returns, multi-buy pricing, weighed goods, duplicate products, wrapped names, missing/duplicated rows, ambiguous totals, and poor OCR.
- Test Finnish dates, decimal separators, rounding, malformed inputs, and daylight-saving ambiguity.
- Assert extracted fields, financial rows, reconciliation, and warnings—not just a summary status.
- Keep parser tests independent of Flutter and maintain separate OCR/camera integration tests on real devices.

---

## 5. Secure Local Replication

### 5.1 Roles and Pairing
- Desktop runs a user-enabled HTTPS endpoint on an available port; Android initiates all connections.
- Desktop creates a cryptographically random, short-lived, single-use pairing secret and shows a QR code containing protocol version, endpoint, certificate/public-key fingerprint, secret, and expiry.
- Android pins the advertised identity before transmitting the pairing secret. The QR/manual fingerprint exchange is the trust anchor; discovery never establishes trust.
- Successful pairing consumes the temporary secret and creates a separate persistent device credential stored securely on both platforms.
- Provide peer revocation, credential rotation, and explicit re-pairing. Certificate identity changes require confirmation/re-pairing, never automatic trust.
- Manual pairing provides the same authenticated information as QR pairing; typing only an IP address is insufficient.
- Enforce authentication, payload/schema validation, request-size limits, timeouts, and bounded batches. Do not expose secrets in logs or discovery records.

### 5.2 Single-Writer Change Protocol

Do not use wall-clock timestamps as delta cursors or last-write-wins conflict resolution.

1. Each Android mutation increments the affected entity revision and appends an immutable change with a dataset-wide monotonic sequence in the same SQLite transaction.
2. Changes contain full store/product/alias snapshots, full receipt snapshots including all current items, or supported deletion tombstones. Catalog changes precede receipts that reference them. Store/product deletion is deferred in the MVP.
3. Android sends ordered, bounded batches after the desktop's last committed cursor. Each batch includes protocol version, dataset/source identity, expected starting cursor, and ending sequence.
4. Desktop validates identity, ordering, references, and revisions. It applies the entire batch and advances its cursor in one transaction. A receipt snapshot replaces its item collection atomically; absent old items are removed.
5. Desktop acknowledges only committed changes. A lost response causes a safe retry; already-applied sequences are idempotent and cannot resurrect older state. Cursor gaps or identity mismatches trigger explicit recovery, not best-effort merging.
6. Receipt deletion is a higher-revision tombstone, not immediate removal from the source change history. Desktop does not upload edits.

Keep immutable changes and tombstones in the MVP; define storage monitoring. Compaction is deferred until a consistent snapshot/bootstrap protocol exists. Initial pairing or rebuilding an empty replica replays the retained history in order. If required history is missing, stop and require a defined rebuild path rather than guessing.

Acknowledgements are an optimization: the desktop's committed cursor is authoritative after connection loss. A restored Android backup must establish a new sync identity and require a replica rebuild, avoiding sequence reuse. Reject unsupported protocol/schema versions safely.

### 5.3 Required Sync Tests
- Retry after a lost acknowledgement; duplicate batch; interrupted upload.
- App crash during source mutation or destination application.
- Offline edit/delete followed by reconnect; removed receipt items; stale replay after deletion.
- Clock skew, equal timestamps, and clock changes have no effect on ordering.
- Invalid certificate/pin, expired pairing secret, revoked device, malformed payload, and oversized request.
- Changed IP, blocked multicast, unavailable desktop, firewall restrictions, and incompatible protocol.
- Empty replica rebuild and source backup restore/re-pairing.

---

## 6. Privacy, Retention & Recovery

- Capture only into private application cache; do not export to the gallery.
- Delete temporary images on save, cancel, review exit, and error paths. Run stale-cache cleanup at startup after crashes; immediate deletion while the process is dead cannot be guaranteed.
- Exclude temporary captures from OS backups where supported. Verify platform behaviour rather than promising secure erasure.
- Do not retain full OCR dumps in production. Keep only structured receipt fields, necessary per-line names, validation metadata, and parser version.
- Redact receipt contents and credentials from logs, crash reports, and diagnostics. No automatic external telemetry or cloud OCR.
- Ordinary SQLite storage is not application-level encryption. Document reliance on device/OS storage protection; separately evaluate database encryption if stronger at-rest protection is required.
- Provide explicit user-initiated structured export/backup and tested restore. Warn that backups retain financial data and that image deletion does not remove those records.
- Define Android OS database-backup policy explicitly; do not silently rely on cloud backup. Export destination and any encryption/password policy must be clear before enabling backup.
- Define user-visible dataset deletion, including replicas, credentials, retained change logs, and the limits of deleting separately exported backups.

---

## 7. Implementation Roadmap

### Phase 1: Scope, Platform Spikes & Parser Foundations (Current Phase)
- [ ] Confirm single-writer scope, first-image capture limits, backup policy, and review rules.
- [ ] Verify bundled OCR works on a fresh Android install in airplane mode, including Finnish characters.
- [ ] Spike pinned HTTPS and secure credential storage on Android and all desktop targets.
- [ ] Define fixed-point arithmetic, financial row semantics, and date/time representation.
- [ ] Build representative geometry-preserving OCR fixtures and expected outputs.
- [ ] Implement standalone Dart parser and validation tests, including discounts, deposits, returns, and weighed goods.
- [ ] Define schema constraints, replication envelopes, and protocol versioning before creating migrations.

### Phase 2: Android Capture → Review → Save
- [ ] Initialize Flutter targets and separate platform-specific capture from shared domain code.
- [ ] Configure Drift, foreign keys, transactions, migration tests, and change logging.
- [ ] Implement camera guidance and clear warnings for incomplete/long receipts.
- [ ] Build editable store/date/total/row review with independent validation states.
- [ ] Support adding, removing, and correcting rows and their relationships.
- [ ] Save only reviewed, reconciled receipts; verify atomic domain/change-log writes.
- [ ] Test image cleanup on save, cancel, error, and startup after crashes.

### Phase 3: History, Product Identity & Recovery
- [ ] Build receipt history with branch/date/amount filters and Android correction/deletion flows.
- [ ] Add store-scoped products, aliases, and explicit match correction.
- [ ] Build price trends with unit comparability, discount semantics, and deposit exclusion.
- [ ] Implement structured backup/export and restore tests, including new sync identity after restore.
- [ ] Test migrations and data integrity before using real financial history as the only copy.

### Phase 4: Read-Only Desktop
- [ ] Add desktop navigation, wide tables, split-screen history, and monthly spending charts.
- [ ] Share validation and analytics rules; keep all editing controls Android-only.
- [ ] Exercise desktop queries using representative fixtures before networking is integrated.

### Phase 5: Secure Local Replication
- [ ] Implement pinned HTTPS, QR/manual pairing, credential persistence, and revocation.
- [ ] Implement transactional ordered change batches, cursors, receipts-as-snapshots, and tombstones.
- [ ] Add optional discovery without making multicast a prerequisite.
- [ ] Run retry, crash, deletion, restore, malicious-input, and network-failure tests.
- [ ] Make sync progress, last successful sync, and recovery errors visible to users.

### Phase 6: Release Hardening
- [ ] Complete Finnish localization and accessibility checks; externalize strings from the start.
- [ ] Test camera quality, poor lighting, crumpled receipts, performance, and large histories.
- [ ] Validate privacy guarantees, backup exclusions, log redaction, and dataset deletion.
- [ ] Test installers, firewall prompts, secure storage, and TLS behaviour on each supported desktop OS.
- [ ] Document unsupported receipt layouts and deferred features: multi-shot stitching, multi-device writers, cross-store merging, and desktop OCR.

---

## 8. Immediate Next Step

Collect 2–3 representative S-kaupat receipts to establish the parser fixture format, including at least one with a discount, deposit, or weighed item. Capture OCR text plus bounding boxes through a minimal Android harness; manually transcribed text can bootstrap lexical tests but cannot validate geometry.

Write expected financial rows and totals by hand, then expand the corpus and implement deterministic arithmetic, parser output, and validation tests before building the main Flutter UI. Development receipt exports must be explicit and anonymized before committing.
