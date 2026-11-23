# Product creation and categories inside receipt workflows

Receipt entry and correction now share the catalog's reviewed editor directly
inside **Valitse tuote**. This works offline on Windows and Android:

1. Select an existing receipt branch and open a product row's **Valitse tuote**.
2. Choose **Lisää tuote** to create a product. Its name starts with the row's
   current receipt name; edit it, choose a starter/custom category and optionally
   enter package metadata. Existing products have an edit button for the same form.
3. Review and save the catalog values. The picker shows **Juuri tallennettu tuote**
   even if the product would normally fall on another page.
4. Explicitly select that product to link it to the current receipt row. Creation
   or editing alone never accepts a product suggestion or changes the row's link.
5. Continue the normal receipt review and saving workflow.

Product creation and edits save to the catalog separately from the receipt. The
picker explains that cancelling the picker or receipt does not remove a product
already saved to the catalog. Closing the editor without saving leaves no new
product; after an uncertain response, a catalog write may already have committed.
The picker reloads after every editor close. An uncertain save freezes the exact
command and mutation identity for retry; stale edits require reload as before.

The row must belong to an existing branch before products can be created or
selected. Save the first receipt for a new branch before using its catalog. No
automatic alias is created from the prefilled name. Exact alias suggestions still
require an explicit choice, and cancelling the picker retains the prior link.
If the row name, branch or editable state changes while the picker is open, its
result is not applied to the changed row.

## Categories from saved receipts

Saved product-linked rows now show the current category and **Muokkaa tuotetta ja
luokkaa**. This opens the existing reviewed product editor with fresh product and
branch metadata. It edits the catalog, including its current category, without
rewriting the saved receipt, its reviewed product revision, or its amounts.
Historical reporting regroups earlier linked purchases as described in
[product categories](product-categories.md).

Receipt history reloads when returning from a detail screen. A receipt can leave
the **Luokittelematon** filtered list after its linked products are categorized.
Saved rows can now add, replace or remove explicit product links through the
separate [saved product-link review](saved-product-links.md), without repeating
financial review. OCR financial corrections retain their original-image/evidence
requirements. There is no silent or bulk historical matching.

## Implementation and compatibility

One shared catalog editor serves the catalog screen, product picker and linked
receipt details. Categories are visible on picker entries and selected-product
labels. Product identity, branch ownership, expected revisions, reviewed values,
package precision, mutation retries and catalog write validation use the existing
domain/storage commands. The initial inline editor used schema 7 without changing
backup formats; [saved product links](saved-product-links.md) subsequently add
schema 8 and inner backup 5. No toolchain or dependencies were upgraded.

## Verification

Verified on November 23, 2026: all 185 app tests pass, including seven new inline
workflow tests, with clean analysis. Native Windows and Android airplane-mode
workflows pass, and the Windows picker/detail screenshots were visually checked.
The dependency notice audit and its four Python tests pass.

Widget checks cover inline creation with prefilled names, explicit selection,
cancellation with a retained catalog save, editing and selecting the new revision,
uncertain retries, load failure/retry, saved-receipt byte preservation and category
history refresh, plus a 320px picker/editor with doubled text. The complete app
suite also exercises existing manual/OCR review, catalog and correction behavior.

The native smoke creates only a guarded `inline-catalog-smoke-*` dataset. It
creates a categorized product through the picker, explicitly links and saves a
receipt, edits the category from saved receipt details, checks exact dashboard
regrouping and unchanged receipt bytes, then restores an encrypted backup and
reopens it. Windows screenshots use invented data only. Normal app data and private
receipt images are not read, cleared or modified by this test.

```powershell
flutter analyze
flutter test
flutter test integration_test/inline_catalog_test.dart -d windows
flutter test integration_test/inline_catalog_test.dart -d emulator-5554
```

Run Android native tests offline, restore its prior network setting and rebuild
normal application entry points afterward. Upgrade-install with `adb install -r`;
do not uninstall or clear the normal app's data.
