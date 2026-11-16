# Experimental Android OCR review

Imported images now offer **Tunnista kuitin teksti** on Android. The candidate
uses bundled ML Kit Latin text recognition 16.0.1. This is an experiment, not
the final engine selection. Windows retains image import and manual review;
its OCR packaging and distribution audit remain open.

## Workflow

1. Import a local JPEG or PNG and check that the whole receipt is visible.
2. Start recognition before editing any fields. Recognition does not overwrite
   manual edits; reopen the image to start a fresh attempt after editing.
3. Check the proposed layout against the image. The red line marks the start
   of item rows after the header date; the blue line marks the left edge of
   posted row amounts. Adjust the sliders as needed. When detection abstains,
   the initial slider positions are placeholders, not inferred boundaries.
4. Explicitly apply the boundaries to create a draft. Compare and correct the
   date, total, row names, amounts, and kinds against the zoomable receipt.
   Original OCR words and pixel rectangles remain available in an expandable
   section, unaffected by corrections.

Supported OCR drafts can now complete the temporary review after individual
findings, row/image comparison, whole-page evidence approval, exact financial
validation, and final confirmation. Unsupported or incomplete evidence remains
blocked; matching sums alone cannot approve OCR output. See the final evidence
audit section below for current rules. Earlier milestone sections describe how
the prototype reached this point.

Nothing is saved. Closing the review discards the app's temporary image and
draft; the selected original is untouched.

## Adapter and ownership

The Dart adapter clones the already-oriented image while encoding PNG in memory.
The native method channel accepts bytes, not a path, and returns the parser's
v1 upright image/word-box contract. Dart validates geometry and checks that the
returned dimensions match the submitted pixels. Native requests are serialized,
with bounded image dimensions, and release the recognizer and bitmap after
completion. Late results cannot update a closed review screen.

The application adapter creates no image files and logs no receipt text or paths.
This does not claim that the third-party SDK creates no internal metadata or
diagnostics. The debug manifest retains Flutter's network permission and the SDK
adds network-state permission. Offline functionality is verified separately;
SDK diagnostics, release permissions, licenses, and distribution remain part of
the engine-selection audit.

## Verification (2026-11-15)

- Flutter tests cover adapter dimension validation, layout abstention, explicit
  draft creation, immutable source words, manual-edit protection, retry, and
  closing during recognition, alongside existing import/review tests.
- Flutter analysis and Android/Windows debug builds pass.
- Android emulator smoke in airplane mode: imported an invented receipt,
  recognized its date and aligned amounts, confirmed proposed boundaries, and
  observed MILK 2,00, BREAD 3,00, total 5,00 and date 15.11.2026 in review.
  Also verified the abstaining path with a synthetic image lacking receipt rows.
  Restored the emulator's original network setting afterward.
- This was an upgrade-install smoke, not a fresh-install release certification.
  The earlier OCR harness's fresh offline checks do not replace final app checks.
- Windows build verified; native Windows picker interaction remains pending.

No private receipt images or OCR text were added to source control.

## Row evidence and quantity corrections

Each parsed row retains immutable original OCR words, including an attached
quantity line and any proposed wrapped description. **Näytä rivin lähde** opens
their text and a crop of the original image. This association survives edits and
deleting other rows. The crop is supporting evidence, not confirmation of the
parser's interpretation; the full image remains available. Manually added rows
have no invented OCR source.

**Määrä ja yksikköhinta** permits editing quantity, unit (kpl/kg/l), and EUR/unit
rate. OCR values populate the controls without floating-point conversion.
Up to six decimal places are accepted. An entered quantity must be nonzero;
the rate must be nonnegative. Negative quantities support returns. If any part
is supplied, all three parts must be valid. Leave both fields empty and the unit
unselected when the receipt provides no quantity information.

Multiplication rounds once, half away from zero, to cents and is compared with
the posted row amount. It never replaces that amount. Mismatches, including
possible discounted prices, require review; matching receipt totals do not
override them. Original parser issues remain visible after corrections.

Validation: 42 parser tests and 17 Flutter tests, including signed rounding,
incomplete input, source immutability, quantity editing, and image-crop rendering.
Android and Windows debug builds and both analyzers pass. No new native adapter
changes were made in this step; the earlier offline smoke remains its baseline.

## Individual finding review

The parser now retains every warning occurrence with immutable source words and
an original draft-row index where applicable. Its existing category set remains
available to evaluation tools. Two rows with the same warning produce two review
cards; handling one does not handle the other. Row references remain attached to
their original row objects after edits or removal of another row.

The current resolution flow supports missing/ambiguous/noncanonical totals,
quantity mismatches, normalized amounts on recognized rows, and wrapped-name
proposals. It requires an imported image, valid relevant fields, explicit image
comparison, and a written explanation. Quantity mismatches require matching
quantity arithmetic; wrapped names require an explicit accept/keep decision.
Handling a finding does not change financial values or erase original evidence.

Data edits reopen all handled findings conservatively, retaining their notes for
rechecking. Deleted-row findings cannot be reassigned accidentally to the next
row. Scoped unparsed-row and total corrections are described below. Layout
ambiguity/skew and legacy findings without adequate scope/evidence remain open.
Older manually constructed drafts without occurrence
details retain category-level warnings and cannot invent missing row links.

OCR completion and persistence remain disabled even if every currently supported
finding has been handled. Orphan/discount relationships are described below;
geometry review and full human evidence-coverage validation are still open.

Verification: 44 parser tests and 18 Flutter tests cover repeated occurrences,
immutable source evidence, resolution prerequisites, independent handling, and
reopening after edits. Android/Windows debug builds and analyzers pass.

## Quantity and discount relationships

Orphan quantity findings now retain any strictly parsed quantity/rate candidate
alongside their original words. **Tarkista tämä huomio** opens a relationship
dialog. Select a product using its current row number, name, and amount, then
check or correct the quantity, rate, and unit against the image. No target is
selected from geometry or matching arithmetic. Confirmation requires valid
quantity arithmetic, an image comparison, and a written explanation. It copies
the confirmed quantity fields to that product and leaves its posted cents alone.

Replacing existing quantity fields requires a separate explicit checkbox. Cancel
discards all dialog changes. A second orphan quantity line cannot be assigned to
a product already claimed by another orphan line. To move an established link,
first clear the old product's quantity, rate, and unit (or remove that product),
then select and confirm the new target. Ordinary row edits reopen the review;
rechecking an existing link starts from the product's current quantity fields.

Every recognized ALE/ALENNUS financial row now has a discount relationship
finding, including correctly negative amounts. Choose a product-specific or
receipt-wide discount. The financial source must still exist as a named discount
row with a strictly negative amount; deleting it or changing its type/sign leaves
the finding unresolved. Scope does not allocate receipt-wide discounts to products
or change any row amount.

NORM/NORMAALIHINTA/KAMPANJA text remains explanatory rather than another financial
contribution. It can be explicitly linked to a product after image comparison,
without subtracting an amount again. The dialog does not convert explanatory text
into a financial row or a posted discount into a non-financial note. If the parser
chose the wrong interpretation, keep the finding open and correct the rows; that
conversion workflow remains pending.

Links refer to stable row objects during the temporary review. Removing another
row changes the displayed position without changing the target. Removing a target
or source reopens review and cannot silently attach the finding to another row.
Source words from linked findings are available through the target's row-evidence
view, including when the link needs rechecking. Original drafts remain immutable.
Relationship decisions and notes are discarded when the review is closed.

Quantity transfers that change fields reopen previously handled findings.
Confirming metadata-only relationships or rechecking unchanged quantity fields
does not reopen unrelated findings. All decisions reset final review confirmation.

Quantity mismatches caused by discounted prices still need explicit validation
rules; a discount link alone does not waive the quantity check. Legacy findings
without typed discount evidence remain unresolved. Manually entered discount
rows do not yet have the full relationship workflow. OCR completion and saving
remain disabled while these and the remaining issue types are implemented.

Verification for this step: 48 parser tests, 23 Flutter tests, clean analyzers,
and Android/Windows debug builds. UI checks cover cancel/replace behavior,
conflicting quantity ownership, deleted targets, independent discount handling,
positive-discount rejection, missing-image rejection, and a 320 px screen with
doubled text size. The enlarged-text check also fixed overflow of the receipt
preview hint and relationship unit control.

Offline emulator smoke (upgrade install, synthetic receipt only): recognized an
orphan `2 kpl 1,00 EUR/kpl` line, a MILK row at 2,00, NORM. text at 2,50, an ALE
row at -0,50, and a total of 1,50. Explicitly attached the quantity and explanatory
price to MILK, then marked ALE as receipt-wide; all three finding cards showed
handled while MILK remained 2,00 and the receipt total remained 1,50. Restored the
emulator's original network setting. Fresh-install certification and native
Windows picker interaction remain pending.

## Unparsed item text and source coverage (2026-11-16)

Findings now identify whether they concern an item, the printed total, or the
receipt generally. An invalid or whitespace-normalized total can be reviewed
against the total field without inventing a product link. Old manually built
findings with no scope cannot be treated as unparsed item rows automatically.

For an unclassified item line or an invalid item amount, the review dialog offers
explicit choices. Link it to a valid existing financial row, add a missing row,
attach it as a product-description continuation, or classify it as header/metadata,
payment/tax information, or explanatory text. A normalized amount with no parsed
row can use the same flow. No choice is inferred from arithmetic.

Creating a missing row requires a name, an exact signed amount, and a line kind
(product, deposit, or adjustment). Image comparison and a written explanation
are required for all choices; non-financial classifications require a separate
acknowledgment that the text is not a contribution to the purchased-item sum.
The printed total is never changed to accommodate a new row. Existing-row and
description links do not alter the row's fields.

Cancel discards dialog changes. A new row is appended only on confirmation;
rechecking its finding starts from the existing row instead of creating another.
If the user wants to reinterpret a finding that created a row, they must remove
that created row first before changing its target or classifying it as non-financial.
Removing targets reopens findings and never selects replacement targets silently.
Source words remain attached to the relevant temporary row-evidence view.

Discount-row repair is intentionally excluded from this dialog: a corrected
discount needs an explicit financial/explanatory interpretation and discount
relationship. Invalid quantity data must also be corrected before linking a row.
Geometry issues, split/merged financial lines, and some conversions still need
their own workflows. OCR completion and persistence remain disabled.

The **Tunnistetun tekstin kattavuus** section counts source words and lists any
words outside the parser's header, row evidence, findings, totals, and footer.
The comparison preserves word identities even when strings repeat. It catches
such omissions as text removed with a band crossing the item-section boundary,
or text between competing totals. Unassigned words can be inspected against an
image crop. This inventory is structural coverage, not proof of transcription,
correct section boundaries, or human review. An empty omissions list does not
clear findings or enable completion. Incomplete or misclassified layouts still
need review even if every word appears somewhere in the inventory.

Verification: 53 parser tests and 30 Flutter tests cover item/total scope,
normalized-total correction, strict repair prerequisites, immutable coverage,
boundary/competing-total omissions, cancellation, single row creation, guarded
reclassification, non-financial acknowledgment, deleted targets, and enlarged
narrow layouts. Both analyzers pass.

Android and Windows debug builds pass. Restarted `Receipt_Reader_API_36_1` after
the host reboot and ran an offline upgrade-install smoke with a synthetic image:
STORE NOTE remained unclassified, MISSING ITEM had the deliberately unreadable
amount `X,XX`, and recognized rows at 2,00 and 3,00 had a printed total of 6,00.
The new dialog added one confirmed MISSING row at 1,00 with source evidence;
the item issue became handled and financial validation showed matched totals.
The separate STORE NOTE finding remained open. The coverage inventory counted
15 source words and no structural omissions without clearing that finding.
Original structured OCR output remained unchanged. No private images were used.
Restored airplane mode and the temporary handwriting-input setting afterward.

## Layout inspection, fresh interpretation, and row comparison

Parsed drafts now retain their original OCR page and the explicit item/price
boundaries. **Tarkista kuitin asettelu** opens a zoomable full-image view with
red/blue section boundaries and optional OCR word rectangles. Opening a geometry
finding highlights its affected words in orange, using the original upright
pixel coordinates. Boundary-crossing and competing-band findings retain their
word context; skew findings retain the page words.

Adjust the boundaries and explicitly preview the interpretation. The preview
shows proposed rows, total, findings, and omissions; changing a slider invalidates
that preview. **Avaa uusi tarkistus** opens a separate temporary review from the
preview. Existing edits, row relationships, notes, and comparison marks stay in
the previous review and can be reached with Back. The new review starts from
the parser output with no inherited approvals or branch selection. No native
OCR rerun or arithmetic-driven layout search occurs.

Each review owns a separate handle to the same immutable image pixels. Closing
the new review releases its handle without invalidating the old preview. No
image files or global image-cache entries are created. Layout inspection is
available only with retained parser context and matching image dimensions.

Geometry evidence is now explicitly excluded from structural word accounting:
highlighting a word does not explain its role. This is especially important for
whole-page skew evidence, which must not hide words lost across a section boundary.
Every structurally omitted word gets its own review-only finding and can be
linked, corrected, or explicitly classified with the existing image-backed flow.
The original inventory remains immutable; a separate count reports which
omissions still need review. Editing data reopens those reviews.

OCR draft rows now have an explicit image-comparison checkbox covering name,
amount, type, and quantity/rate fields. The progress count includes manually
added rows. Data edits reset all row comparisons; evidence/relationship changes
reset affected rows, and adding a row resets the existing comparisons as well.
These marks are temporary review progress, not a completion/persistence grant.

Opening or closing layout inspection does not resolve geometry findings.
Correcting boundaries may remove a boundary issue in the new parser output,
while the old review retains its original warning. Overlap/skew and split/merged
row cases still need explicit resolution rules; final header/footer/field evidence
approval is also pending. OCR completion and saving remain disabled even with
matching totals, all currently supported findings handled, or all row boxes checked.

Verification: 56 parser tests and 35 Flutter tests; both analyzers and Android/
Windows debug builds pass. Tests cover preserved geometry, independent omitted
word reviews, preview invalidation, corrected fresh layouts, parent-edit retention,
image-handle lifetime, row-comparison invalidation, and narrow enlarged layouts.

Offline Android emulator smoke (upgrade install, synthetic receipt only) confirmed
the full-image layout inspector and preview: two proposed rows, total 6,00, two
unresolved findings, and zero structural omissions. Marked one row compared in
the original review, opened a preview-based fresh review with 0/2 compared rows,
then used Back and observed the original 1/2 comparison state and findings intact.
Restored the emulator's original network setting afterward. This does not replace
fresh-install release checks or native Windows picker testing.

## Geometry decisions and final evidence audit (2026-11-16)

Geometry findings now distinguish section/price boundary crossings, competing
baseline bands, overlapping words, and skew adjustment. Boundary crossings still
require corrected parsing in a fresh review. They cannot be acknowledged away.
Legacy geometry warnings without a typed source context also remain blocked.

Overlap and competing-band findings generate separate source-word review items.
Each word must be explicitly linked, classified as non-financial, or identified
as an extra OCR recognition of an existing row. Duplicate recognition is an
evidence relationship, never another monetary contribution. Image comparison
and a written explanation are required for each decision. The original words
and parser output remain immutable.

After row corrections and source-word decisions, compare every row to the image.
Then **Tarkista koko kuitin aineisto** presents the whole receipt and current
branch/date/total/row values. Explicitly check the header fields, footer exclusions,
section boundaries and complete row coverage, and that the entire receipt is
visible. A written note is required. Approval captures immutable current field
values, row identities/order, and evidence links. Changes invalidate approval;
the domain audit also rejects stale snapshots independently of the UI.

**Käsittele kohdistushuomio** allows supported overlap/band/skew confirmation only
after valid row comparisons, whole-page approval, and all non-geometry findings
and omissions have been reviewed. Overlap/band source words must each have their
own valid disposition. The geometry confirmation includes the image overlay,
an explanation, and a separate explicit comparison checkbox. It captures its own
current-value snapshot. Reviewing another warning never resolves it implicitly.

The shared `OcrEvidenceAudit` checks original source context, current valid rows,
individual decisions and their live targets, whole-page approval, omissions,
discount relationships, and competing orphan-quantity claims. Deleted original
rows generate individual source review items. They require explicit duplicate
or non-financial dispositions; a sum match cannot justify deletion. Original
quantity/rate information cannot simply disappear, including through a duplicate
disposition whose target lacks matching quantity data.

When the evidence audit passes, the final review checkbox becomes available.
`ReviewValidation` still independently requires branch confirmation, a valid
printed date/time, valid quantities and signed amounts, exact total reconciliation,
and final confirmation. Evidence can be ready while totals disagree; completion
then stays blocked. Successful completion explicitly states that nothing was saved.
There is still no database/history or permission for a future save layer.

Unsupported cases stay open: malformed/legacy source context, unresolved boundary
issues, unsupported date ambiguity, manual discount rows without a typed discount
relationship, and quantity/net-discount combinations requiring additional rules.
Converting posted discounts to explanatory text or vice versa is still pending.
Windows OCR packaging and release certification remain separate tasks.

Verification: 68 parser/domain tests and 39 Flutter tests, clean analyzers, and
Android/Windows debug builds. Tests cover supported no-save completion, stale
page/geometry approval, missing context/image, immutable audit results, independent
arithmetic validation, overlap word decisions, skew confirmation, original row/
quantity preservation, conflicting quantity claims, and enlarged narrow layouts.

Offline Android emulator smoke (upgrade install, synthetic data only) completed
the full supported flow: TEST BRANCH, date 16.11.2026, MILK 2,00, BREAD 3,00,
printed total 5,00, no parser findings, and no omitted words. Compared both rows,
confirmed header/footer/layout/image completeness with a note, then made the
separate final confirmation. The screen displayed **Tarkistus valmis tässä
kokeilussa. Tietoja ei ole tallennettu.** No database or image persistence was
introduced. Restored airplane mode and the temporary handwriting setting afterward.
