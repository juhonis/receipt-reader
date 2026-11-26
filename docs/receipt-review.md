# Quick and guided receipt review

Implemented November 21, 2026 for the normal Android and Windows OCR workflow.
The receipt image remains beside the editable form on wide screens and above it
on narrow screens. Recognition and parsing still run locally.

## Everyday workflow

1. Import a JPEG/PNG, run recognition and check/apply the proposed layout.
2. Choose a stored branch or enter a new branch's name/location. This deliberate
   choice is sufficient; there is no extra branch-confirmation checkbox.
3. Compare the displayed data to the original and edit anything incorrect. Field
   errors and the summary highlight missing/invalid fields and mismatched totals.
   Summary links return to the branch, date, total or affected row.
4. Choose **Hyväksy ja tallenna**. For a new receipt this one action approves the
   current branch, date, rows and total and saves them without another modal.

**Automaattiset tarkistukset läpäisty** means the implemented validation found no
remaining blocker. It does not promise OCR accuracy: a wrong product name, omitted
text the engine never recognized, or compensating amount errors can escape these
checks. Every field remains editable even when the totals match.

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
