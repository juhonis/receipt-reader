# Reviewed OCR saving

Implemented on 2026-11-16. A supported OCR review can now save structured data
through a separate live-evidence command and the transactional local repository.
The normal Android image-import/OCR route uses this path. Manual entry keeps its
own review policy and save API. Windows uses the same review/storage code, but a
production Windows OCR adapter is still pending; the native Windows smoke uses
synthetic pixels and seeded OCR geometry.

## Review and save

1. Choose an existing stored branch or explicitly create a new branch, and
   confirm it against the receipt. Similar names never merge branch identities.
2. Compare every current row against the image. Resolve all supported findings,
   missing/removed source words, quantity links, discount scopes and geometry
   decisions. Review the complete page, including header, footer and layout.
3. Choose a product parent or explicitly standalone status for every deposit.
   Supply an explicit reason for an adjustment. Neither totals nor proximity
   infer these choices. Unsupported conversions and newly added discounts
   without a supported posted-discount finding remain blocked.
4. Confirm the review, then check date and total again in the final save dialog.
   Current values, evidence/row identities, typed decisions, branch and deposit/
   adjustment details must still match the approved content. Range, date,
   relationship, quantity and reconciliation rules are checked independently.
5. Commit one immutable command. Only a committed save returns to history. An
   uncertain failure holds the same command for retry; leaving that dialog exits
   to history so the user can check whether the receipt was committed.

Changing content or unchecking comparison invalidates approval. Reading a saved
review document never creates permission to perform another local save. The
repository rejects using the wrong source API or changing an existing receipt's
manual/OCR provenance. Saved receipts have separate
[manual](manual-corrections.md) and [fresh-image OCR](ocr-corrections.md) correction
paths; stored assertions never authorize a new correction.

## Retained metadata and privacy

OCR review policy 2 records source `ocr`, application/parser/timezone-rule
versions, audit time, expected heads, checked row IDs, original row identities,
explicit image/row/page checks, finding counts, zero unresolved findings, and
ordered typed finding decisions with durable row targets. Quantities, posted
amounts, discount/deposit parents and adjustment reasons belong to the receipt
snapshot. Corrected retained original rows keep their necessary original names
in `raw_name`; added rows have no original name. Removed source identities stay
reserved and cannot be used by another receipt.

The record retains no image, thumbnail, OCR text dump, word geometry, path,
source-image digest or free-text evidence explanation. Typed decisions and
counts cannot reconstruct the original receipt or prove recognition accuracy.
Their truth is the assertion of the completed live review. Application-owned
pixels are released on successful save, explicit exit after failure, cancellation
and route disposal. Imported originals are never modified or deleted. Persistent
capture caches and crash cleanup still need their own implementation/tests.

## Versions and migration

| Layer | Current support |
| --- | --- |
| SQLite schema | 2; transactional migration from released schema 1 |
| Receipt/event payload | 1; existing manual canonical bytes remain unchanged |
| Manual review policy | 1, source `manual` |
| OCR review policy | 2, source `ocr`, parser `receipt_parser/0.1.0` |

Schema 2 rebuilds only the review projection to permit the two source/policy
pairs. It copies existing projection values and leaves all events, hashes,
identities and retry records intact. The schema/version update is atomic;
failed upgrades roll back and can be retried. Unsupported schemas, policies,
parser versions or malformed metadata fail without resetting data. Future
parser/policy changes must explicitly support their historical records.

## Verification

Domain tests cover canonical bytes, stale/missing reviews, final field checks,
corrected raw names, explicit deposit/adjustment metadata, typed quantity and
discount links, removed-row dispositions and invalid serialized metadata.
Storage tests cover save/reopen/retry, wrong-source rejection, provenance
changes, removed-source ownership and write rollback. Populated released-schema
migration tests compare every stored row value before/after and inject a failure
after DDL to verify rollback of data, schema and version.

The current suites contain 26 domain, 68 parser, 50 storage and 87 app tests.
Widget tests cover review gates, final checks, uncertain retries of the identical
command, explicit exit and evidence disposal. Native Android (airplane mode) and
Windows synthetic UI smoke tests save, close/reopen, verify exact structured
content and inspect history. They do not evaluate new recognition accuracy or
release packaging. Private receipt files are unused.

```powershell
flutter test integration_test/ocr_save_test.dart -d emulator-5554
flutter test integration_test/ocr_save_test.dart -d windows
```

Restore the normal app entry point after native tests: rebuild Android/Windows,
reinstall the normal debug APK, and restore the emulator's prior airplane setting.
See [Windows environment setup](windows-development.md), [local storage](local-storage.md)
and [manual saving](manual-saving.md) for paths and commands.
[History filters](history-filters.md), [manual corrections](manual-corrections.md)
[fresh-image OCR corrections](ocr-corrections.md) and
[reviewed deletion](receipt-deletion.md), [catalog management and reviewed product
links](product-catalog.md), and [encrypted recovery](password-backups.md) are
available separately. Analytics and synchronization remain open.

[The bundled OCR adapters](windows-ocr.md) now have a separate real-engine synthetic
recognition/review/save/reopen check on Windows and offline Android:

    flutter test integration_test/receipt_ocr_engine_test.dart -d windows
    flutter test integration_test/receipt_ocr_engine_test.dart -d emulator-5554
