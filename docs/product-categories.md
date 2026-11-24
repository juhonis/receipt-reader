# Product categories and spending

Categories are optional, reviewed labels on branch-owned products. In **Kuitit →
Tuotteet ja kuittinimet**, select a branch and open a product. Choose **Ruoka ja
juoma**, **Kodinhoito**, **Hygienia ja terveys**, **Vapaa-aika** or **Muut**, or type
a custom label. Clear the field to leave the product unclassified. Check the
existing catalog review box and save. Categories are not guessed from OCR.

[Inline editing](inline-product-editing.md) also provides product creation/category
editing inside receipt product selection, and a shortcut on saved linked rows.
Catalog saves remain separate; explicitly choose the product to link a receipt row.

Labels trim and collapse whitespace when saved and allow at most 80 Unicode code
points. Case remains significant. The suggestions are shortcuts, not a locked
taxonomy or separate category registry. Editing one product's label does not
rename other products' labels. Products with the same label share a reporting
group across branches; product identities remain separate.

## Earlier purchases and coverage

The user chose to regroup earlier purchases using each product's **current**
reviewed category. This applies only to receipt rows explicitly linked to that
product. It preserves their original names, quantities, amounts, reviewed product
revisions, receipt bytes and events. Changing or clearing a category immediately
changes reporting for those links. It never matches old receipt rows automatically.
Use receipt correction to explicitly add a missing product link.

**Seuranta → Kulutus tuoteluokittain** follows the selected week, month, year or
custom range and branch filter. It shows categorized product-row coverage, exact
signed amounts, row counts and distinct receipt counts per group. Unlinked rows
and products without a category remain in **Luokittelematon**, including their
amounts. Coverage counts product rows, including returns; it is not a percentage
of monetary spending or proof that every purchase has been recorded.

Every posted row contributes once:

- Product purchases and returns follow the product's current category.
- Item discounts follow their parent product's category.
- Deposits, receipt-wide discounts and reviewed adjustments have separate groups.

These groups reconcile exactly to the selected dashboard total. A custom label
matching a special group's display name remains a separate typed group. Bars
share a center zero axis: positive nets extend right, negative nets extend left
in red. Text retains exact amounts; relative drawing coordinates are rounded.
Category receipt counts overlap when a receipt contains multiple groups.

Pressing a group opens whole receipts containing matching rows, retaining the
selected range and branch. The history notice explains that each displayed
receipt total includes its other categories too. Category matching precedes
pagination. Other history filters retain the category; resetting filters clears
it. Returning refreshes the dashboard after receipt corrections or deletion.

## Storage and backup compatibility

**Schema 7** upgrades released schemas 1–6 transactionally. It permits product
event payload version 2 while retaining version 1 for all other event kinds.
Product documents without a category retain byte-compatible v1 encoding;
categorized documents use v2. Latest categories are read from verified canonical
product events rather than a new SQL category projection. Existing receipt and
event bytes stay unchanged during upgrade.

The structured backup selects **inner version 4** when any retained product-v2
event exists, even after a category is cleared. It retains all category edits and
original receipt links. Earlier datasets keep their v1/v2/v3 exports unchanged.
Restore accepts all four versions and rejects a downgraded version declaration.
The password-protected envelope and crypto suite remain version 1.

Older applications refuse the upgraded database and category backups. Keep the
new executable and independent encrypted backups available. Category editing does
not change the existing backup limits, replacement confirmation, fresh device
identity on restore, or retained previous datasets.

Category, store and calendar folds share one verified read transaction and the
workspace queue. Product metadata uses a bounded 128-entry cache. At most 64
selected category groups, including special groups, are retained. Exceeding the
limit fails the whole dashboard with a request to narrow its range or branch;
no partial monetary result is shown.

## Verification (November 23, 2026)

All 178 app, 92 domain, 206 storage and 123 parser tests pass (599 total), with
clean analysis. The dependency notice audit and its four Python tests pass.

The category domain tests cover v1 compatibility, strict v2 decoding, label rules,
exact mixed signed rows, immutable results, historical regrouping, special-name
collisions, large integers and the group limit. Storage tests cover current-label
history, filtering before pagination over multiple batches and date precisions,
unchanged receipt bytes, retries, reopen, v4 recovery and downgrade refusal.

Widget tests exercise reviewed editing, frozen retries, historical regrouping,
receipt links, unclassified/special groups and a 320px editor at doubled text size.
Native Windows and Android airplane-mode tests migrate a real generated schema-6
fixture, edit a category through the UI, open older linked receipts, regroup
again, activate an encrypted backup with a queued dashboard read, reopen, and
return to the previous dataset. Windows editor/dashboard screenshots were
visually checked. Only guarded synthetic datasets are used; normal receipt data
and private receipt images are untouched.

```powershell
flutter test test/category_workflow_test.dart
flutter test integration_test/category_workflow_test.dart -d windows
flutter test integration_test/category_workflow_test.dart -d emulator-5554 --no-uninstall
```

Restore the prior emulator network setting and normal application build entry
points after native integration tests. Also run the app and package suites,
analysis and dependency notice audit before packaging.
