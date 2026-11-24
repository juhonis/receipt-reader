# Product links on saved receipts

Implemented November 23, 2026 for offline Windows and Android workflows.

## Use the shortcut

Open a saved receipt from history or a dashboard category, then choose
**Muokkaa kuitin tuoteliitoksia**. Each product row shows its original receipt name,
amount and current product/category. Choose a product explicitly, replace an
existing link or remove it through the picker. Catalog creation and category
editing are available in that same picker.

Choose **Hyväksy tuoteliitokset ja tallenna** once to approve the changed links.
There is no receipt-image import or financial checklist for this operation.
Saving is disabled until a link changes. Selecting the original product revision
again is a no-op. Cancelling the draft leaves the receipt unchanged. Products
created or edited in the picker remain independently saved to the catalog, as the
screen and picker explain.

The date, branch, original/reviewed row names, order, durable row identities,
quantities, unit prices, signed amounts, discounts, deposits, adjustments and total
cannot be changed here. For financial corrections use the existing receipt
correction action; OCR corrections still require fresh image/evidence review.
There is no automatic or bulk historical matching.

History and dashboard reports reload on return. A newly categorized link can move
a receipt out of the unclassified history filter. Its item discounts follow the
product; total spending remains unchanged. Current product categories regroup
earlier linked purchases according to [product categories](product-categories.md).

## Approval and storage

Review policy **4** records only changed product-row identities, the exact prior
receipt document's SHA-256, the expected receipt revision, original manual/OCR
provenance, review time/app version and retained OCR source-row identities. It
does not assert another review of the receipt's financial fields or invent OCR
evidence. Prior approval documents and canonical events remain unchanged in
history; the current document gains a new explicitly approved link revision.

The live command derives its snapshot directly from the saved document and an
immutable selection map. Decoding historical review data cannot authorize a
write. Transaction validation and full history/backup replay check that only
product references changed, that the recorded changed rows match exactly, and
that the predecessor hash, provenance and OCR identities agree. Branch ownership,
product dependencies and receipt heads remain checked.

Newly selected references must use the current reviewed catalog revision.
Untouched references retain their original reviewed revisions even if a product
has since changed category/name. Thus linking a second row does not silently
refresh existing links. Explicitly selecting a newer revision is itself a link
change. Uncertain saves freeze the exact command/mutation for retry; a successful
retry does not create another event. Stale/deleted receipts and stale selections
require returning to history and reopening.

## Compatibility and recovery

**Schema 8** rebuilds only the review projection for policy 4 when upgrading from
schema 7. Earlier released schemas 1–6 run their required migrations in the same
transaction. Failed migrations preserve the prior schema/values and can retry.
Existing canonical documents, events, identities and retry results do not change.
Older executables refuse the upgraded database; keep using the updated app.

Structured inner backup **5** is required whenever retained history contains a
policy-4 revision, including after unlinking or receipt deletion. Recovery accepts
inner versions 1–5, rebuilds schema 8 and validates link-only predecessors and
unchanged fields. Datasets without policy 4 keep their previous exact v1/v2/v3/v4
export format. Receipt/event payload versions stay unchanged. The authenticated
password-protected envelope stays **v1**, and app backup files remain encrypted.

## Verification

The complete suites pass: **102 domain, 220 storage and 194 app tests**, with clean
Flutter analysis. The dependency notice audit and its four Python tests pass.
Focused cases cover link/replacement/removal, explicit selection,
no-op/cancellation, retained catalog saves, stale/deleted/cross-branch rejection,
identical uncertain retries, historical catalog revisions, checksummed forged
backups, encrypted recovery and unclassified-history refresh. The editor and
picker also work at 320px with doubled text.

Native Windows and Android airplane-mode tests migrate a real schema-7 dataset,
link saved OCR and manual purchases, verify signed category totals/item discounts,
unlink a row, restore an encrypted backup and reopen. Windows screenshots use
synthetic data and have been visually checked. Historical migration/rollback and
recovery rehearsals now include schemas 1–7. Normal user data and private receipt
images are not read or cleared by these tests.

```powershell
flutter analyze
flutter test
flutter test integration_test/receipt_product_links_test.dart -d windows
flutter test integration_test/receipt_product_links_test.dart -d emulator-5554 --no-uninstall
```

Run Android native tests offline and restore its prior airplane setting. Rebuild
normal Windows Debug/Release and Android Debug entry points after native tests;
upgrade-install Android with `adb install -r` and launch the normal app.
