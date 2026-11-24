# Reviewed OCR saving

Android bundled ML Kit and [Windows bundled Tesseract](windows-ocr.md) share the
same review and transactional save workflow. The [quick and guided review guide](receipt-review.md)
describes the current UI and approval policy. Manual entry keeps its own policy.

## Review and save

Choose/name a branch, compare the editable extracted data to the original image,
and resolve highlighted problems. A straightforward receipt saves with one
**Hyväksy ja tallenna** action. The optional four-part **Tarkista vaiheittain**
guide has no required note. Completing the guide does not save or override errors.
Edits rerun validation without forcing the guide to be repeated.

Supported findings, omitted/removed source words, quantity links, discount scopes
and geometry decisions remain explicit. Deposits require a product parent or
standalone status; adjustments require a reason. Matching totals alone never
prove OCR correctness. Unsupported conversions and unsupported new discount rows
remain blocked. Corrections additionally review saved row matching/removals.

The immutable command binds current values, evidence/row identities, typed
decisions, branch, expected heads and deposit/adjustment details. Domain rules
independently validate ranges, dates, quantities, relationships and reconciliation.
The repository validates again and commits projection and change log atomically.
An uncertain failure holds the identical command for retry or explicit exit to
history. Only a committed save is success; history can be reopened to inspect it.

## Retained metadata and privacy

OCR policy 3 records source `ocr`, app/parser/timezone-rule versions, review time,
expected heads, reviewed row IDs, original row identities, receipt confirmation,
quick/guided method, finding counts, zero unresolved findings and typed decisions.
It does not assert individual row comparisons or four separate section checks.
Policy-2 historical documents retain those original assertions unchanged.

Quantities, posted amounts, discount/deposit parents, product links and adjustment
reasons belong to the receipt snapshot. Corrected retained source rows keep their
necessary original name in `raw_name`; added rows have no original name. Removed
source identities remain reserved to the receipt.

No image, thumbnail, OCR dump, geometry, file path, source-image digest or free-text
evidence explanation enters the saved document. Structured assertions cannot
reconstruct the source or prove recognition accuracy. Temporary pixels are released
when the review closes; imported originals are never modified or deleted.

## Versions and migration

| Layer | Current support |
| --- | --- |
| SQLite schema | 6; transactional migration from schemas 1–5 |
| Receipt/event payload | 1; prior canonical bytes unchanged |
| Manual review policy | 1, source `manual` |
| OCR review policies | 2 detailed historical; 3 receipt-level quick/guided |
| Parser | `receipt_parser/0.1.0` |

The review-projection rebuild preserves events, hashes, identities and retries.
Failed upgrades roll back. Unsupported schemas/policies/parser versions fail
without resetting data. A policy-2 record does not authorize a new correction;
new corrections approve fresh live evidence under policy 3.

## Verification

Domain regressions cover both approval methods, absent/stale approval, invalid
source/date/quantity/totals, mixed policies, canonical roundtrips, malformed
metadata and unchanged legacy golden bytes. Storage regressions exercise both
methods through save/reopen/retry and password-protected recovery. Populated
schema-1–5 migrations compare persisted values and exercise DDL rollback/retry.
Widget checks cover the exact shipped synthetic receipt, optional guidance,
editing after guidance, field-error navigation, narrow enlarged text, explicit
correction identities and immutable uncertain retries.

Native recognition/review/save/reopen and migration/recovery tests use guarded
synthetic storage on Android/Windows. They do not establish broader OCR accuracy.
Private receipt files are not used. Reproduction commands:

```powershell
$ocrFixture = (Resolve-Path test/fixtures/synthetic_receipt.png).Path
flutter test integration_test/ocr_first_install_test.dart -d windows --dart-define="OCR_SMOKE_FIXTURE=$ocrFixture"
flutter test integration_test/receipt_ocr_engine_test.dart -d emulator-5554 --no-uninstall
flutter test integration_test/migration_recovery_test.dart -d windows
flutter test integration_test/migration_recovery_test.dart -d emulator-5554 --no-uninstall
```

Keep Android native OCR tests offline, restore the previous airplane setting, and
rebuild/install the normal app entry points after integration testing.
