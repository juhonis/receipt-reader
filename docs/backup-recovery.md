# Structured backup and isolated recovery core

Status: core implemented on 2026-11-16. [Password-protected backup files and
reviewed activation](password-backups.md) followed on 2026-11-17, with synthetic
native checks on Windows and Android offline. This document describes the
plaintext inner format and isolated rebuild API, below the encrypted app workflow.

## Supported APIs and lifecycle

`ReceiptRepository.exportBackup()` returns canonical UTF-8 JSON bytes from one
consistent read transaction. It first audits the database. A concurrent writer
cannot leave the export with half of a branch/receipt mutation or mismatched
projections. Export does not allocate sequences or change dataset/device identity.

`ReceiptRepository.restoreBackup(bytes, stagingParent: privateDirectory)` validates
the bytes and creates a unique `receipt-restore-*` subdirectory under the existing
caller-selected directory. It never chooses or replaces an active database path.
It rebuilds a new schema-4 database transactionally from immutable events, audits
it, checks the rebuilt manifest and heads, and closes it before returning a
`RestoredReceiptBackup`. The result exposes its directory, database file, fresh
identity and counts. It can be opened with `ReceiptRepository.open` for inspection.

The caller owns successful staging output and must keep it private and either
activate or remove it. On validation/rebuild failure, the connection closes and
only that attempt's guarded staging directory is removed. A process termination
can leave staging output; the workspace now cleans unregistered staging on startup
and retains all activated slots. This API is not a restore-over-existing-data operation and
has no hidden replace or merge fallback.

## Structured formats 1 and 2

[Catalog storage](product-catalog.md) adds inner version 2 for datasets with
products/aliases, including their full event history and manifest counts. Datasets
without catalog records retain the exact v1 format. Both restore; older builds
reject version 2. Password encryption is independently versioned and unchanged.

The v1 envelope has a fixed format name (`receipt_reader_backup`), string version
`1`, SHA-256 of canonical content, and content. Content contains:

- Dataset ID and event-envelope version.
- Counts of events, branches, receipt identities, deleted receipts, reserved row
  identities and selected heads. Receipt counts include deleted shells.
- Every original canonical event string and its SHA-256, including receipt
  snapshots, review assertions, deletion tombstones, causal parents/dependencies,
  original origin/sequence identities and mutation grouping.
- The selected entity heads, checked against replay rather than trusted as input.

The JSON uses fixed field order, compact encoding, canonical decimal strings and
strict UTF-8 without a BOM or trailing whitespace. Unknown/missing fields,
noncanonical representations, unsupported versions, invalid values, incomplete
mutations, missing ancestors, stream gaps and reused identities fail validation.
Recomputing checksums does not bypass domain or historical consistency checks.
Checksums detect corruption; they do not authenticate who created a package.

Current bounds are 64 MiB per package, 20,000 events, 1 MiB per canonical event,
128 event origins and 200,000 historical row identities. Exports exceeding a bound
fail explicitly rather than truncating history. Schema, backup, event, review and
deletion-policy versions are separate. Recovery now targets schema 4;
existing schema-1/2/3 migration and legacy-v1 recovery checks remain required.

The core representation is plaintext and contains financial history, including
prior corrected/deleted records. It excludes receipt images, raw OCR dumps,
free-text evidence notes, credentials, private keys and peer trust. Historical
origin IDs remain with events; there is no active-device assignment or saved
sequence allocator in the package. The normal app wraps it in authenticated password encryption; its native pickers
do not offer this plaintext format. The user chose password protection on 2026-11-17.

## Identity and replay after restore

Restore retains the dataset ID and every original event's bytes and identity.
It assigns a new device UUID distinct from all imported event origins, starting
its local allocator at sequence 1. Historical origin streams remain immutable.
Local contiguous-history cursors are recomputed from events; peer trust and
acknowledgement state are not imported. Re-pairing remains future sync work.

Integrity auditing now sorts history by causal dependencies and each origin's
previous sequence, with stable revision ordering for independent events. Audit
clocks and SQL row insertion order do not select receipt heads. The current
repository still rejects conflicts, provenance changes and unsupported catalog
mutations; this support does not add arbitrary incoming-event or sync APIs.

Receipt projections, row ownership and mutation retry results are reconstructed
and verified. Retired IDs remain reserved, tombstones still exclude deleted
receipts, and replaying an old committed save returns its old result without
resurrection. A new correction/deletion uses the recovered installation's origin
and can reference a preserved historical head. Repeated backup/restore cycles
retain all historical streams and reset only the active installation identity.

## Verification

The storage suite has 98 passing tests, including 32 new recovery tests. Coverage
includes an independently generated empty golden fixture; exact historical bytes,
metadata and row ownership; OCR provenance; retries and deletion retention;
three restore cycles with intervening writes; signed 64-bit extremes and printed
timestamps; concurrent snapshot export; malformed/future/oversized packages;
forged resurrection; and cleanup after late manifest/history failures. Existing
migration, disk-full, concurrency and write-rollback suites still pass. App tests
remain at 98; app and storage analysis are clean.

```powershell
cd packages/receipt_storage
dart analyze
dart test
cd ../..
flutter test integration_test/backup_restore_test.dart -d windows
flutter test integration_test/backup_restore_test.dart -d emulator-5554
```

The native smoke writes a synthetic package to a private temporary file, restores
and reopens it, verifies identity and old command retries, displays the recovered
OCR receipt in history, deletes it through the UI on the new origin, restores
again, rejects a corrupt package and confirms the source database is unchanged.
It uses a guarded temporary application-support directory, never the normal app
database or private receipt images. Android runs in airplane mode. Restore the
prior airplane setting and normal application builds after native tests; see
[Windows setup](windows-development.md).

## App workflow

[Password-protected backups](password-backups.md) now add native file selection,
validated preview, explicit replacement confirmation, transactional slot selection
and previous-dataset recovery. The current suites contain 115 app tests and 120
storage tests; the counts above describe the earlier core milestone.
