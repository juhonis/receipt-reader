# Manual saving and receipt history

Implemented on 2026-11-16 for Android and Windows. Manual entry now saves reviewed
structured receipts to the local repository and opens read-only history. Image
import and OCR use the separate [reviewed OCR save path](ocr-saving.md); neither
can be relabelled as manual entry or saved through this screen.

## Storage location and ownership

The normal entry point opens one repository through `lib/local_store.dart` and
keeps it across navigation. The app owns closing it, including when an asynchronous
open completes after widget disposal. Initialization failures offer retry or an
explicit [encrypted backup recovery](password-backups.md) workflow; they never
delete/reset data or silently switch datasets.

`path_provider` 2.1.6 resolves the platform application-support directory. The
initial file is `receipts.sqlite`, with SQLite-managed WAL/SHM sidecars as needed.
After restore, `workspace.sqlite` selects a validated `receipt-restore-*` slot under
the same private root and retains the original file. Initial locations are:

- Android: `/data/user/0/fi.juhonis.receipt_reader/files/receipts.sqlite`
  (the app-private directory; an OS alias may use `/data/data`).
- Windows: `%APPDATA%\fi.juhonis\receipt_reader\receipts.sqlite`, using the
  company/product metadata in the executable. The path is resolved at runtime.

The checkout, WSL Git configuration, gallery, Downloads and original receipt
paths are unrelated to these files. Widget tests inject a store instead of
opening the user's database. Native tests use a separately named synthetic
subdirectory and remove only that directory after closing their connection.

Android declares `allowBackup=false` and explicit exclusions in both
`backup_rules.xml` (older versions) and `data_extraction_rules.xml` (API 31+).
Cloud backup and device transfer exclude all credential/device-protected root,
file, database and shared-preference domains, plus app external files. This covers
identities and sidecars as well as the main file; cache/no-backup locations are
already outside normal Android backup. The rules compile into the debug APK.
Actual manufacturer transfer tools and fresh-install release behaviour remain
part of release testing.

Live databases rely on private OS storage. [Encrypted backup/restore](password-backups.md)
is available; retain completed files outside the device and keep their passwords
separately. Copying a live SQLite file is not a supported restore workflow, and
uninstalling/clearing application data can remove all local slots.

## Manual workflow

1. Choose manual entry from the home screen. Select an existing branch with its
   actual stored revision, or explicitly create a new named branch. There is no
   automatic name matching; even a duplicate name creates a distinct identity.
2. Enter the printed Finnish date/time and EUR total. Ambiguous or nonexistent
   Helsinki times and out-of-range integers block saving. Date-only input remains
   date-only; the app does not manufacture a time.
3. Enter product, negative discount, deposit/return, or adjustment rows. Discounts
   require a receipt-wide scope or an explicit product parent. Deposits require
   an explicit standalone or product choice. Adjustments require a reason.
   Optional quantity, unit and unit rate must form a complete, exactly reconciled
   group; the app never invents quantity one or rewrites the posted amount.
4. Check branch, date, total and every row against the original receipt. Any data
   edit, row addition/removal, type change or relationship change clears all
   checks. Removing/changing a product also clears dependent parent selections.
5. A separate final dialog confirms the save. The domain binds the exact snapshot,
   reviewed row IDs and expected heads to a fresh mutation ID. A matching total or
   an old prototype completion flag cannot authorize a write.
6. Saving creates the branch when needed, receipt, children and change events in
   the repository transaction. Success opens history. Cancelling final confirmation
   writes nothing.

A failed save keeps the same immutable command and locks editing/back navigation. Retry sends the
identical mutation, including its review timestamp and row identities, so an
uncertain response cannot create a second receipt. The command is retained only
while this screen is alive. If leaving it or restarting after an uncertain save,
check history before entering the receipt again. The error screen also offers a
route straight to history. Command preparation/size failures remain editable and
require review again rather than throwing an unhandled UI exception.

## History and current limits

History loads consistent pages of 30 receipts and offers load-more, retry and
refresh actions. The repository validates each returned canonical document,
projection and revision in the page transaction. Sorting uses printed civil date
and time, with unknown time after known times on the same day; durable IDs break
ties. Money stays exact signed integer cents throughout, including returns.

Details show row types, quantities/rates, discount/deposit parents and adjustment
reasons. [History filters](history-filters.md) and
[reviewed manual corrections](manual-corrections.md) and
[fresh-image OCR corrections](ocr-corrections.md) are now implemented. [Reviewed deletion](receipt-deletion.md),
[product/alias management and explicit links](product-catalog.md), and
[encrypted export/restore](password-backups.md) are also available. Branch editing,
analytics and synchronization remain later work. Images and OCR
text dumps are not stored. `lib/manual_receipt_page.dart` records application
version `0.1.0+1`; keep its version constant aligned with `pubspec.yaml` when
cutting a release.

## Verification

The counts below describe the initial manual-saving baseline. See
[manual corrections](manual-corrections.md) for current app verification.

- 40 storage tests, 18 domain tests, 68 parser tests and 53 Flutter unit/widget
  tests pass; app and storage analyzers are clean.
- Widget coverage includes required checks, stale confirmation, cancelled saves,
  explicit new/existing branch identity, scoped discount/deposit parents,
  adjustment/quantity validation, Helsinki ambiguity, numeric overflow, uncertain
  retry without duplicates, database ownership, history read retry/pagination,
  and narrow/wide screens with enlarged text and large amounts.
- Android UI integration passed with airplane mode enabled. It enters an invented
  receipt, saves through final confirmation, closes/reopens the real native
  SQLite repository, verifies unchanged identities/content and opens history
  details. The prior airplane setting is restored afterward.
- The same UI save/reopen integration passes on native Windows. Host connectivity
  is unchanged. No real receipt or image is used on either platform.
- Android and Windows normal debug builds pass; the normal Android app is
  reinstalled after the test entry point. Backup XML is packaged successfully.

Run the shared UI smoke with:

```powershell
flutter test integration_test/manual_save_test.dart -d emulator-5554 --no-uninstall
flutter test integration_test/manual_save_test.dart -d windows
```

Native integration builds use a test entry point. Afterwards build the normal app
again (`flutter build apk --debug` or `flutter build windows --debug`), and
reinstall the normal APK if using the emulator. These upgrade-install debug
checks do not certify release packaging, physical-camera behaviour, power loss,
manufacturer device transfer, or recovery from a backup.
