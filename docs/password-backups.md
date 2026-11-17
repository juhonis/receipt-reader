# Password-protected backups and dataset recovery

The user-facing workflow uses password-protected `.rrbackup` files on Android and
Windows. The plaintext [structured core format](backup-recovery.md) is an inner
representation; the normal app exports and accepts only the encrypted wrapper.

## Using the app

1. Open **Varmuuskopiointi ja palautus** from the home screen.
2. To export, enter a password twice and choose **Tallenna salattu varmuuskopio**.
   Use at least 12 characters, at most 1024 UTF-8 bytes. Case and spaces matter.
   Keep the password separately: it is not stored and there is no password reset.
3. Choose a destination in the native file picker. Keep the completed file outside
   this device too. Existing Windows backup files are never truncated; choose a
   new name. Android's document-creation picker creates a separate document.
4. To restore, enter that backup's password and choose **Avaa salattu varmuuskopio**.
   Password confirmation is needed only for export. A wrong password or modified
   ciphertext fails without changing the active data.
5. Review the validated receipt/deletion/event counts and replacement notice.
   Check the explicit review box, then choose **Ota varmuuskopio käyttöön**. This selects the complete restored dataset;
   independent datasets are not merged. Cancellation removes the staged candidate.
6. **Palaa edelliseen paikalliseen aineistoon** opens a separate confirmation and
   switches back to the prior local dataset. The current one is retained, so the
   same action can switch back again. This is a local selection, not a new restore
   from a file, and it preserves that slot's device/sequence identity.

If the current receipt database cannot open, startup offers **Palauta
varmuuskopiosta**. This explicitly opens recovery mode with normal receipt
editing/export disabled. A valid encrypted backup can then be reviewed and
activated; unreadable original files remain preserved. An unreadable or future
workspace registry fails closed and requires diagnosis; it is never silently reset.

Every backup includes immutable past receipt snapshots, corrections and tombstones,
including records hidden by deletion. Receipt images and raw OCR dumps are absent.
Passwords protect exported files; live, previous and staged SQLite data still rely
on private OS application storage. Retaining an old slot is not secure erasure.

The encrypted envelope remains v1 when the inner package contains catalog data.
[Product/alias backups](product-catalog.md) use structured inner version 2, or
version 3 when retained receipts have product links. The encrypted envelope stays
v1; legacy
receipt-only packages retain inner version 1. Both recover through this workflow.

## Encrypted envelope v1

The binary layout is:

| Bytes | Meaning |
| --- | --- |
| 0..7 | ASCII `RRBACKUP` |
| 8 | Envelope version 1 |
| 9 | Fixed algorithm suite 1 |
| 10..25 | Fresh random 16-byte Argon2id salt |
| 26..37 | Fresh random 12-byte GCM nonce |
| 38..end-17 | AES-256-GCM ciphertext of the structured package |
| final 16 | GCM authentication tag |

Suite 1 derives a 32-byte key with Argon2id v19, 19,456 KiB memory, two iterations,
and one lane, then uses AES-256-GCM. All 38 header bytes are additional authenticated
data. Input files cannot choose arbitrary KDF cost parameters. Unknown suite or
version, short input and excessive lengths fail before derivation. The maximum
file size is the 64 MiB inner limit plus 54 bytes. There is no plaintext fallback.

The implementation pins `cryptography` 2.9.0 and runs password derivation and cipher
operations in a worker isolate. Each export uses secure random salt and nonce;
passwords/keys are not written to files, SQLite, preferences, logs or native channels.
Known mutable buffers are cleared when practical, but Dart strings and runtime
copies do not provide guaranteed memory zeroization. Authentication errors do not
distinguish a wrong password from ciphertext tampering. Historical validation still
runs after authentication: a valid tag is not permission to import invalid history.

The initial derivation cost follows the Argon2id baseline in the
[OWASP password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#argon2id).
See the library's [Argon2id API](https://pub.dev/documentation/cryptography/2.9.0/cryptography/Argon2id-class.html)
and [AES-GCM API](https://pub.dev/documentation/cryptography/2.9.0/cryptography/AesGcm-class.html).
A committed synthetic fixture was generated independently using Python
`argon2-cffi` and `cryptography` with these parameters; it is not a real backup.

## Native files and cancellation

Windows uses the existing `file_selector` plugin for open/save selection. Import
streams are bounded, including if a file changes size during reading. A new export
reserves a new filename exclusively and flushes the encrypted bytes. Existing
backups are preserved on failure. A crash or provider error during a new export
can leave a partial encrypted file; it cannot pass authenticated import.

Android uses `ACTION_CREATE_DOCUMENT` and `ACTION_OPEN_DOCUMENT` through a dedicated
method channel. Only encrypted bytes cross this channel. I/O runs off the activity
thread, with bounded reads, no plaintext cache file, no persistent URI grant and
no broad storage permission. Picker cancellation is a normal result. Provider
write errors can leave an incomplete document and are reported as failures.
See [Android's document access contract](https://developer.android.com/training/data-storage/shared/documents-files).

Pending processing disables fields/actions and blocks back navigation. Password
fields are masked and cleared after an operation starts. A late prepared result
is discarded if its route was disposed. Preview cancellation and failed rebuilds
remove only the attempt's private staging directory. A stale preview cannot replace
a dataset that changed after preparation. Activation also rechecks the exact
validated history digest and fresh installation identity of the staged candidate.

## Atomic activation and retained local data

The application-support root retains the original `receipts.sqlite`. A new
`workspace.sqlite` registry (version 1, WAL, `synchronous=FULL`) selects one slot
and records the previous slot and generation. Restored slots live under unique
`receipt-restore-*` subdirectories and keep their fresh device identity. The
receipt database schema remains 3; existing schema-1/2 migrations still apply.
An exclusive workspace lease prevents a second app process from opening it.

Activation audits and opens the candidate first, then commits the active/previous
selection in one registry transaction. Receipt files are never renamed, overwritten
or deleted to activate a restore. After commit, the app delegates to the new
repository and closes the prior connection. A lost COMMIT response is reconciled
with the exact persisted selection; unresolved state blocks further app mutations
until restart. Ordinary app reads/writes and backup operations share one queue.

Before registry commit, a process exit retains the old selection; after commit,
restart selects the restored slot. Startup removes only unregistered staging
directories under the owned prefix. All activated slots remain retained; automatic
purging and dataset erasure are separate work. A missing selected file is an error,
not a reason to create an empty dataset. Android automatic-backup/transfer exclusions
cover the registry, slot databases, SQLite sidecars and installation identity.

## Verification

The current suites contain 115 app tests and 120 storage tests. New coverage includes
independent crypto compatibility, randomized encryption, authenticated-header and
tampering failures, password/size bounds, preview gates/cancellation/retries, narrow
320-pixel UI at doubled text, stale replacement, registry rollback/retry, exclusive
workspace opening, unreadable/missing data, and real process exits before and after
registry commit. Existing receipt/event/migration/storage-full tests remain passing.

```powershell
flutter analyze
flutter test
cd packages/receipt_storage
dart analyze
dart test
cd ../..
flutter test integration_test/protected_backup_test.dart -d windows
flutter test integration_test/protected_backup_test.dart -d emulator-5554
```

The synthetic native workflow exercises UI encryption/export, wrong passwords,
preview cancellation, activation, retained tombstones, returning to the previous
dataset, and explicit startup recovery. It uses only its guarded private temporary
directory. Normal application data and private receipt images are not used.

The separate interactive picker check opens real native save/open dialogs. It is
skipped by default so an unattended integration run cannot wait on a chooser:

```powershell
flutter test integration_test/backup_picker_test.dart -d windows --dart-define=INTERACTIVE_BACKUP_PICKER=true
flutter test integration_test/backup_picker_test.dart -d emulator-5554 --dart-define=INTERACTIVE_BACKUP_PICKER=true
```

The Android save/open picker check passed in airplane mode. Windows native
workflow/file I/O tests pass, but direct Windows dialog interaction remains a
manual verification step: the desktop automation helper was unavailable after
reboot. Choose a new local filename for the synthetic fixture, then select the
same file in the open dialog. Run Android checks in airplane mode and restore the
prior setting afterwards. Rebuild normal app entry points after integration tests;
see [Windows setup](windows-development.md). This work does not establish physical
power-loss durability, cloud-provider reliability, manufacturer transfer behavior
or production Windows OCR availability.

The [migration/recovery rehearsal](migration-recovery.md) additionally checks
encrypted recovery after upgrading each supported historical schema, including
exact restored table values, catalog links, fresh-origin writes, both analytics
screens and repeated previous-dataset recovery on both native platforms.
