# Quick and guided receipt review

Implemented November 21, 2026 for the normal Android and Windows OCR workflow.
The receipt image remains beside the editable form on wide screens and above it
on narrow screens. Recognition and parsing still run locally.

## Everyday workflow

1. Import a JPEG/PNG, run recognition and check/apply the proposed layout.
2. Check the suggested branch, choose a stored branch or enter a new branch's
   name/location. There is no extra branch-confirmation checkbox.
3. Compare the displayed data to the original and edit anything incorrect. Field
   errors and the summary highlight missing/invalid fields and mismatched totals.
   Summary links return to the branch, date, total or affected row.
4. Choose **Hyväksy ja tallenna**. For a new receipt this one action approves the
   current branch, date, rows and total and saves them without another modal.

**Automaattiset tarkistukset läpäisty** means the implemented validation found no
remaining blocker. It does not promise OCR accuracy: a wrong product name, omitted
text the engine never recognized, or compensating amount errors can escape these
checks. Every field remains editable even when the totals match.

## Possible duplicate receipts

New OCR and manually entered receipts are checked against live saved receipts
when saving. A matching printed calendar date and minute raises a possible-duplicate
warning even if branch, total or seconds differ, so a corrected rescan can replace
a bad earlier reading. If either time is missing, the warning requires the same
day, branch (identity or complete normalized name) and total. Different known
minutes do not match. These are candidates, not proof that two purchases are equal.

The comparison shows the new and saved branch, date/time, total and expandable
item lists. Choose explicitly:

- **Säilytä vanhat ja hylkää uusi** closes the draft without writing anything.
- **Säilytä uusi ja poista tämä vanha** replaces only the selected saved receipt.
- **Säilytä molemmat** saves the new receipt alongside the old one.
- **Palaa muokkaukseen** keeps the draft editable without saving.

With multiple candidates, replacement targets one displayed receipt; other matches
remain untouched. No candidate means no additional dialog. Existing-receipt
corrections skip duplicate review. Lookup failures offer retry/cancel instead of
silently bypassing the check. Leaving during a pending lookup cannot trigger a
later dialog/save.

Replacement saves the approved new document and tombstones the exact reviewed
old revision in one transaction. Failure leaves both operations uncommitted;
uncertain retries reuse both original commands. Stale old data is not deleted.
The old receipt leaves ordinary history/statistics but its audit history remains.
Catalog entries and imported images are not deleted. See [deletion and atomic
replacement](receipt-deletion.md#duplicate-replacement) for the storage contract.

## Review problems one at a time

The normal receipt screen shows one problem at a time, a **Käsitelty n/total**
progress bar and a clear pending/done status. Separate source-word findings on
the same printed line share one review action. Overlap/band warnings no longer
require classifying every already-accounted word again; genuinely unassigned
text still needs an explicit disposition.

- **Ohita — ei ostosrivi** marks the displayed information as explanatory text,
  without adding/removing money or changing purchased rows. Alternatively choose
  **Selittävä teksti**, header metadata or payment/tax information directly.
- **Hyväksy nykyiset tiedot** confirms a valid field or image-backed geometry
  warning. Boundary warnings become acceptable after every cut word has been
  explicitly accounted for. Missing/invalid financial data remains blocked.
- **Lisää, liitä riviin tai korjaa…** opens the relevant row/relationship editor,
  fields or layout review when information needs correction.

Accepting/classifying advances to the next unfinished problem. **Seuraava** alone
does not resolve anything. Previous/next navigation also lets you inspect completed
items and change their handling. **Jatka tallentamiseen** reaches the final save
action after the queue is complete; classification never saves by itself.

Comments are optional for every finding, relationship, row-evidence, geometry and
page review. The quick flow uses the explicit action as confirmation, without a
second comparison checkbox. Optional comments remain temporary and are excluded
from saved receipt data. Completed text classifications survive unrelated edits;
field approvals reopen when their relevant values change, and geometry approvals
reopen after changes to their approved snapshot.

This does not automatically discard unknown content, create balancing amounts or
allow removing a parsed quantity to hide an inconsistency. Original row/source
accounting, valid dates and quantities, arithmetic reconciliation and final receipt
approval remain required. Review progress is temporary state for the current view.

## Toimipiste recommendations

After parsing, header text offers names to review. Exactly one existing branch
whose complete name matches a candidate is selected automatically, with a visible
reminder to check it. Matching trims/collapses whitespace and ignores case; it
preserves diacritics and punctuation and does not use substring or fuzzy matching.
Duplicate names or conflicting header matches require an explicit choice.

Header extraction separates names from explicit inline phone/tax labels and their
separator punctuation. Other metadata and text crossing the item boundary do not
become names. Closely spaced adjacent header lines can supply a combined name.
These are suggestions from OCR, not verified store identities or address lookup.

**Käytä uutena nimenä** explicitly fills a new branch's editable name. Recognition
never creates a stored branch by itself. Manual branch choices/edits take precedence
over later recognition, and correction screens do not automatically select a new
branch. The final save action approves the current branch along with the receipt.

## Product-name and catalog suggestions

For a product row, **Ehdota nimeä tai tuotetta** looks in the selected existing
branch's catalog. It offers exact active receipt-name aliases, exact canonical
names and conservative close spellings. Compare the proposal to the product and
package on the receipt; even an exact name does not establish product identity.
Equal-name products remain separate choices. Nothing is selected automatically.

- **Käytä nimeä** changes the editable row name and clears an earlier product
  link. The original OCR row name and evidence remain available; prices,
  quantities/rates, date and total stay unchanged.
- **Liitä tuote** selects that product and its reviewed revision without changing
  the row name. Choose the name separately if both changes are wanted.
- Closing the dialog leaves the draft unchanged. Catalog/alias records are never
  created or edited by these suggestions. Final receipt saving still requires
  **Hyväksy ja tallenna**.

Suggestions are read on request, not while typing. A product changed since loading
must be reviewed again before selection. A result cannot replace a row whose name,
branch or kind changed, or one removed while the dialog was open. The existing
**Valitse tuote** picker remains available for other products and catalog editing.

The first implementation scans at most 2,000 canonical product names in pages of
200 and shows up to five choices; exact active aliases are checked independently.
Close spelling allows one edit for names with 6–11 letters and two for longer
names, preserving token order, numbers, symbols and short variant/unit tokens.
Separate punctuation/spacing may differ. Names over 256 characters are excluded
from spelling comparison. These limits keep local work bounded; they do not imply
a confidence score, package equivalence or general spelling correction. Without
an appropriate catalog entry, correct the name manually. No image processing,
OCR engine, schema, saved payload or backup format changed.

## Optional guided review

**Tarkista vaiheittain** opens the four-part image checklist: header, footer,
layout and complete image. All four checks are required to mark the guide complete;
no review note is requested. Completing or closing this dialog never saves.
Closing an incomplete guide leaves quick saving available if validation passes.

The completed guide remains available after edits and reopens with its boxes
checked. It is assistance, not a preapproved saved snapshot. The final save action
always approves the exact current content. A new recognition/layout review starts
with its own guide state. There are no mandatory per-product comparison boxes or
separate date/total checkboxes in the normal OCR save workflow.

## Problems that still require attention

Missing/ambiguous dates, missing branches, malformed amounts, mismatched totals,
invalid quantities/rates and nonnegative discount rows block saving. Supported
parser findings, source omissions/removals and uncertain relationships still need
explicit resolution; unsupported cases remain blocked. Deposits require a product
or an explicit standalone choice; adjustments require a meaningful reason.
Issue-specific evidence decisions are retained; the optional checklist does not
resolve them or bypass validation. Ordinary parser notes remain informational.

OCR corrections use the same quick/guided review. They additionally require
explicit matching to saved row identities and a final review of retained/new/
removed identities. The existing-image selection confirmation remains necessary
because the app does not retain receipt images or source-image hashes.

## Recorded approval and migration

New OCR commands use review policy **3**, source `ocr`. They record a receipt-level
confirmation and method (`quick` or `guided`), along with existing structured
finding decisions and original row identities. They do not claim that individual
rows or all four image sections were checked separately. Policy **2** detailed
reviews and manual policy **1** remain readable with unchanged canonical bytes.
The separate no-save diagnostic prototype retains its detailed review controls.

Final approval binds the exact receipt values, row/evidence identities, branch,
relationships and expected revision heads. Edits after command preparation reject
the stale command. An uncertain write retries that identical immutable command.
Neither automatic readiness nor a historical decoded review authorizes a save.

SQLite schema **6** transactionally rebuilds only the review projection to allow
OCR policy 3. It migrates schemas 1–5, preserving prior values, events, hashes and
retry identities. Failed upgrades roll back; newer unsupported databases are
refused without reset. Earlier app builds cannot open a schema-6 database; keep
using the updated app after upgrading. Receipt/event payload and backup formats
are unchanged. Password-protected backups preserve both review policies.

Images, OCR dumps, geometry and free-text evidence notes are not retained. Imported
original files remain untouched. See [OCR saving](ocr-saving.md) and the
[storage contract](local-storage-contract.md) for the persistence boundary.

## Verification (November 21, 2026)

- 148 app, 67 domain, 68 parser and 196 storage tests pass; all analyzers are clean.
- Native Windows OCR of the exact shipped synthetic PNG saves through the quick
  path and reopens with both rows and 5,00 € total. Its source bytes stay unchanged.
- Native Android real-engine recognition uses the optional note-free guide, then
  saves/reopens successfully in airplane mode.
- Native OCR correction/reopen and concurrent stale-write checks pass on both
  platforms with the explicit identity confirmation retained.
- All six migration/recovery cases pass on Windows and offline Android, including
  schemas 1–5, DDL rollback/retry, retained historical bytes, restored analytics
  and refusal of future/corrupt databases. Policy-3 quick/guided encrypted recovery
  is additionally covered by the storage suite.
- Normal Windows Debug/Release and Android Debug builds are restored; the normal
  Android app is upgrade-installed and running, with the prior airplane setting
  restored to off. No normal app data was cleared.
- Widget regressions cover direct saving, optional/cancelled guidance, preserved
  guide state after edits, mismatch/date blockers, error-summary navigation and
  320-pixel layouts with doubled text size.

These checks use synthetic fixtures and isolated storage. The external laptop
acceptance report covers the prior detailed-review build. Broader store layouts,
physical-phone capture quality and final redistribution conditions remain open.
Alpha.6 adds in-app memory-only capture; see [phone testing](phone-testing.md).
