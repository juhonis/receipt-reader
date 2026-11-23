# Native migration and recovery integrity rehearsal

This rehearsal checks populated receipt database schemas 1–7 upgrading to schema 8,
then using the current catalog, spending and product-price APIs before and after
encrypted recovery. The same assertions run in the pure Dart storage suite and
native Flutter integration tests on Windows and Android. Application behavior and
the database schema were unchanged by the original rehearsal milestone. The
November 21 extension covers schema 6 for receipt-level OCR approval.
The November 23 extension adds source schema 6 and target schema 7 for categories.
The separate [native category workflow](product-categories.md) also migrates a
schema-6 fixture containing existing product-linked purchases on both platforms.
The subsequent [saved-link workflow](saved-product-links.md) adds source schema 7,
target schema 8, review policy 4 and inner-backup-v5 recovery on both platforms.
The shared rollback/recovery rehearsal covers every source schema 1–7.

## Historical fixture matrix

| Source schema | Synthetic history present before upgrade |
| --- | --- |
| 1 | Manual receipt and correction, retired row identity, linked deposit, receipt discount, reviewed adjustment, negative receipt, zero receipt and leap-day date |
| 2 | All schema-1 cases plus an OCR receipt and correction with retained provenance and row identity |
| 3 | All schema-2 cases plus a reviewed deletion and retained tombstone history |
| 4 | All schema-3 cases plus a product edit and alias creation/deactivation history |
| 5 | The same history in the released product-link-capable schema, retaining policy-2 reviews |
| 6 | The same compatible history in the released receipt-level-review schema |

The fixture builder creates each historical database from its committed generated
Drift schema. It copies compatible synthetic commands and projections from a
closed seed database. It does not turn a current schema into an old one by lowering
the version flag. Old receipt schemas forbid product links; links are added through
reviewed commands only after the real migration succeeds.

These are generated-schema compatibility fixtures, not archived databases produced
by running historical application binaries. The source files and fixtures contain
only synthetic data; private local receipts and normal application datasets are
never read or changed.

## Assertions

For every supported source version, the rehearsal:

1. Injects failure after the final migration DDL step and verifies that schema SQL,
   user version and every existing table value roll back. It then retries through
   the normal workspace opener.
2. Compares pre-upgrade table values and exact structured export bytes after the
   successful migration. The schema-3 default for existing live receipts is
   normalized explicitly. The dataset and original device identity stay unchanged.
3. Adds reviewed product links, an item discount, a later product revision, an
   active alias and another purchase. Piece prices retain two distinct saved
   product revisions. Retired row identities and original event bytes survive.
4. Verifies exact signed spending and price summaries, whole-day date filters,
   catalog coverage counts, negative receipts, reviewed adjustments, zero totals,
   printed calendar months, OCR provenance and tombstone exclusion.
5. Exports an encrypted backup, rejects a wrong password and altered authentication
   tag, and confirms that those failures leave the current export unchanged.
6. Makes a further correction to distinguish the current dataset from the backup,
   restores the backup, and compares every restored table except the intentionally
   renewed device state/cursor. Historical cursors remain present. Exact event,
   review, projection, ownership, catalog and retry records are checked.
7. Retries original manual commands without adding events, writes a correction on
   the fresh recovery origin at sequence 1, closes and reopens the workspace, and
   checks both summaries again.
8. Returns to the retained pre-activation dataset and compares its exact export
   bytes, then restores a second time and verifies another fresh device identity.

An additional case creates a synthetic future-version database and a database with
an inconsistent receipt total projection. Normal repository opening must refuse
both without resetting their schema, values or identities.

The baseline recovered spending totals are 4,75 € for schema 1 and 6,75 € for schemas
2–5; the difference is the preserved OCR receipt. The two explicitly linked price
rows total 6,00 € before item discounts and 5,00 € after them. Whole-receipt spending
also includes deposits, receipt discounts, adjustments, unlinked rows and the
negative receipt, so it deliberately differs from the product-price subtotal.
The subsequent correction adds 3,00 €; restoring the older backup removes it.

The native integration callback also renders the restored Finnish spending and
purchase-price screens, checking their total, row count and product-revision groups.

## Running the checks

From the repository root, using Windows PowerShell and the documented Flutter SDK:

    flutter analyze
    flutter test
    flutter test integration_test/migration_recovery_test.dart -d windows
    flutter test integration_test/migration_recovery_test.dart -d emulator-5554

Run the storage suite separately:

    cd packages/receipt_storage
    dart analyze
    dart test

The storage package explicitly pins matcher 0.12.20 as a test dependency so the
shared assertions work in Dart and Flutter test runners. This package was already
used transitively by the test toolchain; no production dependency or additional
native SDK is introduced.

Use a temporary Flutter build-dir when existing Windows Debug sessions hold the
normal executable open, then restore its previous configuration. Android runs in
airplane mode and restores the prior setting. Afterwards rebuild the normal
Windows release and Android debug entry points, upgrade-install the APK and launch
the app without uninstalling or clearing application data. See
[Windows development](windows-development.md).

Native tests create only guarded migration-recovery-smoke-v*-* and
migration-recovery-refusal-* directories under app support. Package tests use
migration-recovery-test-* under the system temporary directory. Every connection
is closed before cleanup, and recursive removal checks the exact parent and
expected directory prefix.

## Evidence and limits

Verified on November 17, 2026:

- All 191 storage tests passed, including the existing eight migration cases and
  five new upgrade/recovery cases; storage analysis is clean.
- All 136 app tests passed and app analysis is clean.
- All five native cases passed on Windows and on the Android emulator in airplane
  mode, including both restored summary screens.
- Normal Windows release and Android debug builds passed. The normal Android app
  was upgrade-installed and launched, the prior airplane setting was restored, and
  the temporary Flutter build-dir setting was removed. Existing Windows Debug
  sessions were preserved.

This is a repeatable synthetic integrity check, not evidence of physical power-loss
durability, every historical installation, manufacturer transfer behavior, picker
reliability or production Windows OCR availability. Keep independent encrypted
backups and their passwords separate; the rehearsal does not make this app the
only safe copy of financial history. Networking and unresolved sync conflicts
remain future work.

On November 21, the rehearsal was extended through source schema 5 and target
schema 6. All six native cases pass on Windows and on Android in airplane mode;
the storage suite now has 196 passing tests. The review-projection migration
retains historical policy-2 canonical bytes. Separate policy-3 storage regressions
exercise quick/guided save, reopen, identical retries and encrypted recovery; see
[receipt review](receipt-review.md).

On November 23, source schema 6 and target schema 7 were added for product
categories. All seven native cases pass on Windows and offline Android, and all
206 storage tests pass. A separate native category rehearsal upgrades an actual
schema-6 fixture with existing product links, checks unchanged export/receipt
bytes, then exercises category edits, encrypted recovery and retained datasets.
See [product categories](product-categories.md) for product-v2/backup-v4 details.
