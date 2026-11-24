# PLAN.md: Local-First Receipt Tracker (S-Kaupat & Finnish Focus)

## 1. Project Overview & MVP Scope

A privacy-first receipt, spending, and product-price tracker built as **one Flutter app for Android and Windows**, with a shared codebase and adaptive layouts. The project produces native Android and Windows builds, not an Android APK running inside a Windows emulator. macOS and Linux are potential later targets, not MVP release requirements.

### Guiding Principles
1. **Offline core:** Capture, OCR, parsing, review, storage, and analytics work without internet access, including first-run OCR. Optional synchronization uses only the local network.
2. **No retained app-owned receipt images:** Captured images and temporary import copies exist only during capture/review in memory or private temporary storage. Structured receipt data is retained locally. Imported original files remain under the user's control and are never deleted by the app. This is not a guarantee of secure erasure from flash storage.
3. **Explicit validation, not accuracy percentages:** Matching totals verifies arithmetic, not product identity or transcription accuracy. Users review every receipt before saving.
4. **Store-specific products:** Product identities belong to a particular store branch (`Prisma Kaari != Prisma Jumbo`). No cross-store product merging in the MVP.
5. **Full local functionality on both platforms:** Android and Windows can independently import, OCR, review, edit, delete, and analyze receipts. Synchronization is optional; neither platform depends on the other to operate.
6. **Authenticated, encrypted local sync:** No cloud servers or accounts. Local Wi-Fi is not assumed to be trusted.

### MVP Boundaries
- One Android device and one Windows device may share a dataset through bidirectional local sync. Both may edit offline. Concurrent edits require explicit resolution rather than silent overwrites.
- Both platforms support image import, offline OCR, review, corrections, deletion, product-alias management, history, search, and charts. Android additionally supports phone-camera capture; Windows webcam capture is deferred.
- Start with single-image JPEG/PNG import on both platforms. PDF import and multi-shot stitching are deferred. Long receipts must be rejected or clearly flagged when incomplete.
- Each installation can start standalone. Initial pairing seeds an empty installation from the chosen existing dataset; automatically merging two independently populated datasets is deferred and must never overwrite either dataset silently.
- Currency is EUR; UI is Finnish. Receipt dates use Finnish conventions and `Europe/Helsinki` interpretation.
- Adaptive layouts share workflows and domain logic: compact phone navigation, and keyboard/mouse-friendly desktop tables and panels. This is not a separate desktop product with reduced functionality.
- Basic backup/export and restore are required before relying on the app as the only copy of financial history. Sync is not a backup because deletions propagate.

---

## 2. Tech Stack & Platform Constraints

| Component | Technology | Requirements |
| :--- | :--- | :--- |
| Framework | Flutter / Dart | One project with Android and Windows targets, shared workflows/domain logic, and adaptive UI; verify supported SDK versions when initializing. |
| Database | Drift / SQLite | Transactions, foreign-key enforcement, migrations, reactive queries, and desktop support. |
| Android capture | `camera` | Private temporary files only; platform-specific cleanup. |
| Image import | Platform file picker behind a shared import service | JPEG/PNG on Android and Windows; read originals without modifying them and use private temporary copies only when needed. |
| Offline OCR | Shared recognition request and normalized word geometry | Android bundled ML Kit plus app-owned Windows Tesseract, approved after the spike. Shared parsing/review remains independent. No runtime model downloads or cloud fallback. Broader accuracy and release checks remain open. |
| Android OCR | Bundled native Google ML Kit Latin recognition | Approved MVP engine; native integration uses com.google.mlkit:text-recognition:16.0.1. Keep first-run offline verification and release terms checks explicit. |
| Windows OCR | App-owned Tesseract 5.5.1 + Leptonica 1.85.0, pinned Finnish/English models | Approved MVP engine; source-built worker, memory-only IPC and ZIP packaging. Clean-machine and final release licensing/signing remain open. See [Windows OCR](windows-ocr.md). |
| Windows sync server | `shelf` with Dart HTTPS server support | TLS and certificate/public-key pinning; never transmit credentials or receipts over plaintext HTTP. Serving requests does not make Windows authoritative for data. |
| Android sync client | Dart HTTP client with explicit pin validation | Pushes and pulls changes during each sync; restrict any self-signed certificate exception to the paired identity and never disable verification globally. |
| Pairing / discovery | QR pairing; optional `nsd` / `multicast_dns` | Discovery is optional and untrusted. Manual pairing must work without multicast. |
| Secure credential storage | Platform-backed secure storage | Validate Android and Windows support and behaviour before selecting the package. |
| Charts | `fl_chart` | Store-specific comparable price observations. |
| State management | `flutter_riverpod` | Keep parser, financial rules, and sync logic independently testable. |

Do an early platform spike for bundled OCR on both targets, HTTPS pinning, secure storage, and Windows firewall requirements. Normalize engine-specific OCR results into the same text/geometry model; keep the parser independent of native OCR packages. Pin compatible dependency versions after these checks.

### Development Environment
- Use a Windows-native checkout, for example `C:\dev\receipt-reader`, with Windows Flutter, Git, Android Studio/Android SDK, and Visual Studio 2022's **Desktop development with C++** workload and Windows SDK.
- Use a Windows-native editor/coding agent for the main build loop. Verify the environment with `flutter doctor -v`, accept Android SDK licenses, and test both an Android device/emulator and `flutter run -d windows` once the project exists.
- WSL remains optional for auxiliary work. Do not run Linux and Windows Flutter tooling against the same checkout or share generated build directories. A WSL symlink is only a path shortcut; use a separate checkout for Linux-specific tooling if needed.

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

The following is a logical overview, not migration-ready SQL. The [local storage contract](local-storage-contract.md) defines concrete representations, constraints, reviewed-snapshot requirements, atomic writes, causal conflicts, and recovery behaviour for the first Drift implementation. Add generated schema snapshots and migration tests during implementation.

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
- Corrections can happen on either platform and synchronize in both directions. Concurrent alias mappings or store/product changes require review just like receipt conflicts; independent UUIDs alone do not identify duplicate real-world products or branches.
- Distinguish printed shelf/unit price from effective price after linked discounts. Exclude deposits from product price trends.
- Do not allocate receipt-wide discounts to individual products without a documented rule. Label such observations accordingly.
- Compare only compatible units/package sizes. Receipts without enough information still count toward spending but may be excluded from normalized price charts.

---

## 4. OCR, Parsing & Review

### 4.1 Pipeline

```text
Android private camera capture OR Android/Windows image import
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
- Keep parser tests independent of Flutter and maintain Android camera/import and Windows import/OCR integration tests. Run comparable fixtures through each selected OCR backend and check the normalized geometry contract.

---

## 5. Secure Bidirectional Local Sync

### 5.1 Roles and Pairing
- Windows runs a user-enabled HTTPS endpoint on an available port; Android initiates connections and both pushes and pulls changes. Transport roles do not limit editing rights or determine which data wins.
- Windows creates a cryptographically random, short-lived, single-use pairing secret and shows a QR code containing protocol version, endpoint, certificate/public-key fingerprint, secret, and expiry.
- Android pins the advertised identity before transmitting the pairing secret. The QR/manual fingerprint exchange is the trust anchor; discovery never establishes trust.
- Successful pairing consumes the temporary secret and creates a separate persistent device credential stored securely on both platforms.
- Provide peer revocation, credential rotation, and explicit re-pairing. Certificate identity changes require confirmation/re-pairing, never automatic trust.
- Manual pairing provides the same authenticated information as QR pairing; typing only an IP address is insufficient.
- Enforce authentication, payload/schema validation, request-size limits, timeouts, and bounded batches. Do not expose secrets in logs or discovery records.

### 5.2 Multi-Writer Change Protocol

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

### 5.3 Conflict UX and Analytics
- Show both receipt versions with origin device, audit time for context only, row differences, and any delete-versus-edit state.
- Let the user keep either version or manually produce a reviewed, reconciled version; deletion is an explicit choice. Never automatically choose the latest wall-clock timestamp.
- Retain candidate snapshots until resolution is durably recorded. Concurrent resolutions can themselves conflict and must follow the same rules.
- Unresolved receipt conflicts remain visible in history but are excluded from aggregate spending and price trends, with a clear warning that totals are incomplete. Never count both versions.
- Catalog conflicts and alias uniqueness collisions block affected automatic matching; unrelated records remain usable. Define deterministic projection rules for affected references before implementing sync.

### 5.4 Required Sync Tests
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

## 6. Privacy, Retention & Recovery

- Capture only into private application cache; do not export to the gallery. Import originals read-only and never delete or modify them. Explain that source images may remain in the user's gallery, file storage, or backups outside the app's control.
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
- [ ] Confirm Android/Windows feature parity, two-writer scope, image-import limits, backup policy, and review rules.
- [x] Set up the Windows-native Flutter/Android/Windows C++ toolchains and verify both build targets. See [Windows development setup](windows-development.md) for the setup and smoke-build results.
- [x] Establish private-image baselines with offline Android ML Kit and Windows Tesseract, preserving normalized word geometry. See [OCR spike findings](ocr-spike.md) and the later [approved engines and app bundle](windows-ocr.md).
- [x] Verify the shared-engine candidate with bundled Finnish/English Tesseract models on a fresh offline Android installation; compare both page segmentation modes against the Windows baseline.
- [x] Evaluate manually guided Windows preprocessing and a relocatable Tesseract prototype against the private baseline. See [findings and limitations](ocr-spike.md); clean Windows installation and distribution licensing remain open.
- [x] Record the approved MVP engines (bundled Android ML Kit and app-owned Windows Tesseract), normalized geometry, pinned sources/models and Windows development ZIP. See [Windows OCR](windows-ocr.md).
- [ ] Complete broader representative OCR evaluation, final redistribution-license review and release acceptance.
- [x] Audit the pinned dependency closure, retain complete native/SDK license notices, expose an offline information/license screen and validate the built notice assets. See [dependency audit](dependency-licenses.md); application licensing, builder entitlement and public distribution acceptance remain owner decisions.
- [ ] Verify first-run offline OCR on fresh Android and Windows installs, including Finnish characters and bounding boxes.
- [ ] Spike pinned HTTPS and secure credential storage on Android and Windows.
- [x] Define fixed-point arithmetic, financial row semantics, and printed date/time representation with explicit Helsinki DST ambiguity. See [parser conventions](parser-foundations.md); persistence range checks and review resolution remain open.
- [x] Establish a standalone Dart parser foundation with exact arithmetic, geometry-based row candidates, header dates, and synthetic validation tests. See [parser scope and limitations](parser-foundations.md); broader layouts and review integration remain open.
- [ ] Build representative geometry-preserving OCR fixtures and expected outputs.
- [x] Add 23 hand-annotated synthetic Finnish cases and six actual-engine geometry captures, with native checks on both platforms and review/save safeguards. See [Finnish OCR corpus](finnish-ocr-corpus.md); representative photograph evaluation remains open.
- [ ] Implement standalone Dart parser and validation tests, including discounts, deposits, returns, and weighed goods.
- [x] Define schema constraints, causal revisions, event identities, conflict states, and versioning before creating migrations. See the [local storage contract](local-storage-contract.md); schema/event/review versions are independent, while transport limits and the wire format remain work for the sync implementation. Defer network implementation until both local workflows work.

### Phase 2: Shared Import → Review → Save, Plus Android Capture
- [x] Initialize one Flutter project with Android and Windows targets and externalized Finnish UI strings.
- [ ] Separate platform services from shared domain code and adaptive workflows as the OCR spike establishes the adapter contracts.
- [x] Configure a local manual-receipt Drift schema, strict constraints, foreign keys, atomic transactions, schema baseline/failure tests, and immutable change logging. See [local storage implementation](local-storage.md); the catalog storage extension is implemented; broader conflict/sync schema remains open.
- [ ] Implement camera guidance and clear warnings for incomplete/long receipts.
- [x] Implement JPEG/PNG selection and offline OCR on both platforms using shared geometry/review, with real-engine synthetic recognition/save/reopen checks. See [Windows OCR](windows-ocr.md).
- [x] Add bounded, temporary JPEG/PNG import and zoomable receipt evidence on Android/Windows; originals remain read-only. See [image import](image-import.md). Android OCR and reviewed saving now use the separate workflows below; Windows OCR is now available through the [app-owned bundle](windows-ocr.md).
- [x] Connect the experimental bundled Android OCR candidate to temporary image review with explicit layout confirmation and manual boundary fallback. See [Android OCR review](android-ocr-review.md); Windows OCR is now available through the [app-owned bundle](windows-ocr.md); supported issue review and saving are documented below.
- [ ] Build editable store/date/total/row review with independent validation states.
- [x] Simplify normal OCR review with highlighted validation problems, one snapshot-bound save approval and an optional four-part guide without routine notes or per-row checkboxes. Preserve historical reviews with policy 3 and schema-6 migration; see [quick/guided review](receipt-review.md).
- [x] Add a temporary manual review prototype with independent checks, editable signed rows, and explicit no-save messaging. Evaluate the parser against private OCR outputs; [real-layout failures remain open](review-prototype.md).
- [ ] Support adding, removing, and correcting rows and their relationships.
- [x] Add immutable row-level OCR evidence with image crops and editable quantities/unit prices with exact independent validation. Individual issue resolution and row relationships remain open.
- [x] Preserve individual parser finding occurrences and add evidence-backed review for supported total, quantity, normalized-row-amount, and wrapped-name findings; reopen handled findings after edits. Remaining issue types and row relationships still block OCR completion.
- [x] Add explicit orphan-quantity attachment and product/receipt-wide discount relationships with evidence-backed confirmation, overwrite protection, stable row targets, and non-financial explanatory price links. Remaining finding types and full evidence coverage still block OCR completion and saving.
- [x] Add scoped item/total findings, explicit correction/classification of unparsed item text, and a structural source-word coverage inventory that exposes parser omissions. Geometry review, full human evidence review, and OCR completion remain open.
- [x] Retain layout context and geometry source words, add image overlays and safe re-parsing into a separate temporary review, expose omissions as individual review items, and track per-row image comparison. Overlap/skew resolution and final OCR approval remain open.
- [x] Add typed overlap/band/skew evidence decisions and a shared final evidence audit with stale-approval rejection, whole-page review, source/quantity preservation, and supported no-save OCR completion. Boundary repair, unsupported conversions remain open; see the later [Windows OCR integration](windows-ocr.md). supported persistence is documented below.
- [x] Add independently tested durable UUIDs, range-checked receipt snapshots, canonical JSON/digest fixtures, and snapshot-bound manual confirmation commands. See [storage foundations](storage-foundations.md); the separate OCR evidence adapter is now implemented below.
- [x] Connect explicit manual review and reconciled saving to atomic domain/change-log writes, with private database ownership and basic read-only history on both platforms. See [manual saving](manual-saving.md).
- [x] Add the separate live OCR evidence adapter and reviewed OCR saving, with typed provenance, schema-v2 migration/rollback tests, stable source-row ownership and native save/reopen smoke checks. See [OCR saving](ocr-saving.md). Windows OCR is now packaged in the [development bundle](windows-ocr.md).
- [ ] Test image cleanup on save, cancel, error, and startup after crashes.
- [ ] Verify that imported original files remain untouched on both platforms.

### Phase 3: History, Product Identity & Recovery
- [x] Add read-only receipt history with inclusive branch/date/amount filters, exact signed cents, pagination/retry tests and native offline smoke checks on both platforms. See [history filters](history-filters.md).
- [x] Add reviewed correction of saved manual receipts on both platforms, preserving row metadata and causal revisions, with stale-write rejection and native reopen checks. See [manual corrections](manual-corrections.md).
- [x] Add original-image-backed correction of saved OCR receipts with explicit row matching, preserved provenance/identity and native synthetic correction/reopen/stale-write checks. See [OCR corrections](ocr-corrections.md). Production Windows recognition remains pending.
- [x] Add reviewed receipt deletion with immutable tombstone events, schema-3 migration, stale-write rejection, exact retries and native reopen checks on both platforms. See [receipt deletion](receipt-deletion.md).
- [x] Add store-scoped product/alias storage, immutable revisions, schema-4 migration and encrypted backup recovery. See [product catalog](product-catalog.md).
- [x] Add product/alias management UI and explicit reviewed receipt match correction. See [product catalog](product-catalog.md).
- [x] Add linked product purchase history and page-scoped price charts with exact quantity arithmetic, unit/revision comparability, linked item discounts, deposit exclusion and explicit receipt-wide discount/adjustment warnings. See [purchase history](purchase-history.md).
- [x] Extend product price trends to inclusive date-range summaries over every matching row, with exact counts/subtotals, bounded calendar min/max charts, exclusion counts and one consistent summary/detail snapshot. See [purchase history](purchase-history.md).
- [x] Add full-range quantity-weighted product prices, first/latest-day price changes, average chart markers and signed product-spending intervals with date drill-down. Preserve unit/revision groups and read-only encrypted recovery. See [product trends](product-trends.md).
- [x] Add selected-range product spending rankings with top ten/exact remainder, full paginated list, signed row attribution/coverage and direct branch/product history inheriting dashboard dates. See [product rankings](product-rankings.md).
- [x] Add receipt-level spending summaries by branch and calendar month, using complete current receipt totals, exact signed cents, inclusive branch/date filters and explicit coverage notices. See [spending summaries](spending-summary.md).
- [x] Add an offline weekly/monthly dashboard with up to 12 calendar bars, exact averages/deltas, matched-day comparisons for unfinished periods, branch filters and receipt drill-down. See [spending dashboard](spending-dashboard.md).
- [x] Make Seuranta the default home tab and group receipt entry/management in Kuitit; add year/custom ranges and charts covering exactly the selected timeframe, with independent whole-range totals. See [dashboard navigation and ranges](spending-dashboard.md).
- [x] Add selected-range store comparisons with exact branch nets/counts/averages, signed bars, a positive-net donut with explicit grouped-store choice, receipt drill-down and a whole-result branch limit. See [store comparisons](store-comparisons.md).
- [x] Add editable product category labels with five starter suggestions, historical regrouping of explicitly linked purchases, signed category spending/coverage, receipt drill-down and schema-7/inner-v4 encrypted recovery. See [product categories](product-categories.md).
- [x] Add reviewed product creation/category editing inside receipt product selection, visible category labels and direct catalog editing from saved linked rows, preserving explicit linking, retries and original receipt bytes. See [inline product editing](inline-product-editing.md).
- [x] Add explicit link-only review for saved manual/OCR receipt rows, preserving financial/evidence values, original history, frozen retries and schema-8/inner-v5 recovery. See [saved product links](saved-product-links.md).
- [x] Implement the versioned structured backup/isolated recovery core on both platforms, including strict validation, preserved event/tombstone/row identities, fresh device identity and repeated restore/write tests. See [backup recovery](backup-recovery.md).
- [x] Add password-protected backup files, native export/import UI, validated preview, explicit replacement confirmation, transactional activation/crash recovery and retained previous datasets on both platforms. See [password backups](password-backups.md).
- [x] Rehearse supported-schema (1–7) migration, rollback, retained history, catalog links and exact analytics through encrypted recovery/reopen using synthetic data. See [migration/recovery integrity](migration-recovery.md). Keep independent backups; this does not establish sole-copy safety.

### Phase 4: Adaptive UI & Standalone Feature Parity
- [ ] Refine Windows navigation, wide tables, keyboard shortcuts, split-screen editing, and charts alongside compact Android layouts.
- [ ] Verify import, OCR, review, corrections, deletion, aliases, history, and analytics work independently on both platforms without pairing or internet.
- [ ] Exercise shared validation/analytics and platform-specific integrations with representative fixtures before networking is integrated.

### Phase 5: Secure Bidirectional Local Sync
- [ ] Implement pinned HTTPS, QR/manual pairing, credential persistence, and revocation.
- [ ] Implement transactional two-way event exchange, per-origin cursors, causal revision tracking, receipts-as-snapshots, and tombstones.
- [ ] Implement conflict comparison/resolution for receipts and catalog changes, including edit-versus-delete and concurrent resolutions.
- [ ] Implement empty-device bootstrap, restore reconciliation, and safeguards against accidental merging/overwriting of unrelated datasets.
- [ ] Add optional discovery without making multicast a prerequisite.
- [ ] Run retry, crash, concurrent-edit, deletion, restore, malicious-input, and network-failure tests in both directions.
- [ ] Make sync progress, last successful sync, and recovery errors visible to users.

### Phase 6: Release Hardening
- [ ] Complete Finnish localization and accessibility checks; externalize strings from the start.
- [ ] Test camera quality, poor lighting, crumpled receipts, performance, and large histories.
- [ ] Validate privacy guarantees, backup exclusions, log redaction, and dataset deletion.
- [ ] Test Android/Windows installers, bundled OCR assets, Windows firewall prompts, secure storage, and TLS behaviour.
- [ ] Document unsupported receipt layouts and deferred features: PDF import, multi-shot stitching, Windows webcam capture, more than two synchronized devices, automatic merging of independent datasets, cross-store product merging, and macOS/Linux releases.

---

## 8. Immediate Next Step

[Manual saving](manual-saving.md), [reviewed OCR saving](ocr-saving.md),
[history filters](history-filters.md),
[reviewed manual corrections](manual-corrections.md),
[fresh-image OCR corrections](ocr-corrections.md) and
[reviewed receipt deletion](receipt-deletion.md) share reviewed persistence on
Android and Windows. App-bundled recognition now runs on both platforms; broader
quality and clean-machine release verification remain open. The normal
app owns one application-support database with schema-8 migration from released
schemas 1, 2, 3, 4, 5, 6 and 7. Native synthetic save/reopen, filtered-history,
correction/stale-write and deletion/tombstone checks pass on both platforms,
including Android airplane mode. Deletion retains prior structured snapshots;
it is not secure erasure and receipt undo is not implemented.

The [structured backup/recovery core](backup-recovery.md) now exports a consistent
versioned package and validates/rebuilds it in an isolated database with a fresh
device identity. Event/tombstone bytes, row ownership and retry identities survive
repeated restore/write cycles. Synthetic native recovery passes on both platforms.

[Password-protected backups](password-backups.md) now provide the native file
workflow, explicit reviewed replacement and retained previous datasets. A workspace
registry selects complete recovered databases atomically; startup also offers
explicit backup recovery if the selected receipt database cannot open. Unit,
widget, process-exit and native offline recovery checks pass. Completed encrypted
backup files must be kept off-device with their passwords stored separately.

[Store-scoped product and alias storage](product-catalog.md) now provides durable
branch-owned identities, exact alias suggestions, reviewed revision commands and
encrypted recovery, with migration from schemas 1/2/3/4. Finnish catalog screens
now support reviewed create/edit/deactivate/remap operations. Manual/OCR receipt
review and correction expose optional explicit product choices and alias suggestions.
Links retain reviewed product revisions and receipt/row identities; history and
inner-v3 encrypted recovery retain earlier linked snapshots after unlink/deletion.

[Product purchase history](purchase-history.md) now shows explicitly linked rows in
one branch, original financial data and full date-range price summaries. Normalized prices
require reviewed purchased quantities; linked item discounts apply, deposits stay
separate, and receipt discounts/adjustments remain unallocated and flagged. Returns
and missing-quantity rows stay visible outside price charts. Piece comparisons keep
saved product revisions separate; weight and volume use distinct purchased units.

Date filters now include whole Helsinki calendar days. Summaries cover every
matching linked row, with exact exclusion counts and at most 24 calendar min/max
intervals per unit/revision group. The summary and paginated details share one
transaction; excessive group counts require a narrower range without partial output.

[Receipt spending](spending-summary.md) now uses full current receipt totals, so
unlinked products, deposits, receipt discounts, returns and reviewed adjustments
contribute exactly once. Inclusive branch/day filters cover every selected receipt;
exact signed totals are broken down by branch and printed calendar month. Coverage
notices, negative receipt counts and adjustment/unlinked receipt counts stay visible.
These totals are separate from comparable product prices and update after encrypted
recovery without changing stored financial data.

[Migration/recovery integrity](migration-recovery.md) now has a shared synthetic
rehearsal for source schemas 1–7, with native category checks for 6→8 and
saved-link checks for 7→8 on Windows and Android. It checks migration
rollback/retry, unchanged existing values/event bytes, corrections and tombstones,
retired row identities, catalog revisions/aliases and exact spending/price summaries.
Repeated encrypted recovery, fresh-origin writes, reopen and retained previous
slots preserve history. Future schemas and corrupt projections are refused without
resetting data. These checks do not replace independent encrypted backups.

The approved [Windows OCR bundle](windows-ocr.md) integrates a source-built worker
with the normal review flow. Real-engine synthetic recognition/save/reopen passes
on Windows and offline Android. The development ZIP includes notices, a synthetic
receipt and a relocation/dependency rehearsal. It is not a signed or clean-machine-
certified release.

The initial November 21 laptop test confirmed offline startup and recognition
of the synthetic sample but hit a blocked final review checkbox. After the review
guidance update, the user reports correct information, successful saving, and
preserved receipt history after closing the app, moving the program folder and
opening it again. The exact retested build ID/hash, cancellation/retry, special
characters in the destination path and repeated recognition after relocation were
not separately reported; this confirms the reported workflow, not every release
check in the [clean-machine checklist](windows-ocr-clean-machine.md).

The [simpler receipt review](receipt-review.md) now provides one explicit
**Hyväksy ja tallenna** action and an optional four-part guide without a note.
Field errors and summary links direct attention to unresolved problems; editing
remains available when checks pass. Branch selection/naming needs no extra
checkbox. The completed guide survives edits, while final approval binds current
values. Review policy 3 records receipt-level quick/guided approval without
inventing policy-2 row/page comparisons. Schema 6 preserves earlier records and
migrates schemas 1–5. Correction identity/removal confirmation remains explicit.

The [dependency audit](dependency-licenses.md) now records exact pins and notice
hashes, preserves full native/SDK texts, provides an offline license screen and
checks actual built notice assets. App licensing/end-user terms, builder licensing
entitlement, signing and public distribution acceptance remain separate decisions.

The [Finnish OCR corpus](finnish-ocr-corpus.md) now covers 23 invented receipt
cases, source coverage and review gates. Three actual-engine synthetic cases
pass on each platform, including weighed purchases/returns and euro-suffixed
amounts. Windows dash recovery and Android split-decimal recovery retain explicit
warnings; matching sums never bypass review. This is not photograph accuracy
certification.

The [weekly/monthly dashboard](spending-dashboard.md) begins the expanded
analytics work: calendar charts, fair partial-period comparisons, exact averages
and receipt drill-down are available on both platforms. Home now separates the
default Seuranta dashboard from Kuitit management. Week, month, year and custom
range selections scope the full-width total, statistics and charts together.
The [store comparisons](store-comparisons.md) now provide signed bars, positive-net
shares, exact store statistics and receipt links for the selected range.
[Product categories](product-categories.md) now provide editable starter/custom
labels, historical regrouping of explicit product links, signed category bars,
classification coverage and receipt drill-down. Product-v2 events use schema 7
and inner backup format 4; existing receipt amounts and canonical bytes remain
unchanged. [Inline product editing](inline-product-editing.md) now makes reviewed
product creation/classification available during receipt selection, and lets saved
linked rows edit their current catalog category directly. Catalog saves remain
separate and selecting a product remains explicit. [Saved product-link review](saved-product-links.md)
now links, replaces or unlinks saved manual/OCR rows without changing financial
values or repeating image review. Schema 8 and inner backup 5 retain original
approvals and validate exact predecessors. [Product trends](product-trends.md) now
add quantity-weighted prices, first/latest-day comparisons and signed product
spending intervals with date drill-down, without changing stored data or formats.
[Product spending rankings](product-rankings.md) now show the top ten, exact
remainder and full paginated list, with direct product history using the dashboard
dates. Ranking overflow retains complete financial totals and coverage. The next
comparison decision is explicit matching of equivalent products across branches;
package conversions also still need explicit rules. Neither is inferred from names.
Privacy/permission auditing and native import/backup picker checks remain required
before release or networking work.

Keep representative S-kaupat images and OCR exports in ignored
`localreceipts/`; committed fixtures remain synthetic or explicitly anonymized.
Complete standalone workflows and tested recovery before bidirectional sync.
Representative photograph/layout evaluation, remaining clean-machine checks, privacy/permission audits,
manufacturer transfer tests and native Windows picker verification remain required.
