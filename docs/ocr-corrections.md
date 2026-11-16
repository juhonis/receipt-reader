# Reviewed OCR corrections

Implemented on 2026-11-16. A saved OCR receipt has its own correction action in
history. It retains source `ocr` and the receipt ID, writes a new causal revision,
and preserves earlier snapshots and reviews in immutable local events. It uses
SQLite schema 2, receipt/event payload 1 and OCR review policy 2; no migration or
historical document rewrite is needed.

## User flow

1. Open a saved OCR receipt and choose **Korjaa kuvasta tallennettua kuittia**.
   Compare the saved branch, date and amount, then confirm that you will select
   this receipt's original image. The app has no retained image or image hash;
   it relies on this explicit confirmation, not automatic source verification.
2. Select the original JPEG/PNG. Run recognition and review the layout. The
   correction starts with fresh recognition, not a reconstructed saved audit.
   Existing saved names, quantities and relationships are not copied into this
   review; verify and enter all necessary values against the image again.
3. For every current row, explicitly select its corresponding saved row or
   **Uusi rivi**. The choices include saved row position, name and signed amount;
   position/name similarity never chooses an identity automatically. A saved
   row can be assigned only once. Retained rows keep their IDs even if reordered
   or corrected; new rows get fresh IDs. Unmatched saved rows are removals.
4. Reconfirm the branch, compare every row and review the entire page. Resolve
   every supported finding and relationship, including omitted/removed source
   words. Explicit deposit parents/standalone choices and adjustment reasons
   are still required. Matching a saved row resets comparisons and approval.
5. The final dialog lists the row matches and every saved row being removed.
   Separately confirm these choices, the date/time and printed total. Cancel
   writes nothing. Saving creates one immutable command with the opened receipt
   revision as its only expected head.

Changing the layout opens another fresh review for the same receipt and base
revision, with independent image ownership and empty approvals/row matching.
Back returns to the prior review. Success returns through the correction and
detail routes to refreshed history, retaining the active history filters.

A new fully reviewed image can create a revision even when financial content is
unchanged: it records a fresh review and may have different source dispositions.
There is no automatic merge, saved-version browser or one-click revert.

## Evidence, identity and retry rules

The command captures exact live content, durable row mapping, branch dependency,
row details and evidence before the final modal. All of them are checked again
before saving. Decoding an old review record never authorizes a save. Both OCR
correction entry points reject manual receipts at runtime, including release
builds; the repository independently rejects source changes and wrong save APIs.

Each revision records the source-row IDs and typed decisions for its own fresh
scan. Retained current rows can carry their previous IDs into that scan. Old
source IDs and decisions remain in earlier events and all historical IDs remain
reserved. Removed IDs cannot be recycled by the same receipt or another receipt.
The current `raw_name` comes from the fresh scan for a retained source row;
previous raw names remain in historical documents. Added rows have no raw name.

The repository atomically replaces current projections and appends the reviewed
snapshot/event. A changed receipt head or branch dependency rejects the whole
write and offers a return to fresh history, without retrying against a new base.
An uncertain failure locks the review behind the save dialog: retry sends the
identical command and mutation ID. Explicit close returns to refreshed history
because the command may already have committed. Committed retries remain valid
after later edits and reopening, without duplicate events.

No image, path, OCR dump, word geometry, image digest or free-text evidence note
is persisted. Pixels are released on success, cancellation, explicit uncertain
exit, route disposal and late picker completion after navigation away. Imported
original files remain untouched. See [OCR saving](ocr-saving.md) for the full
policy and retention limits.

## Verification and current limits

Widget tests cover fresh review gates, explicit retained/new/reordered/removed
row choices, duplicate prevention, final removal confirmation and cancellation,
layout re-review, stale receipt/branch failures, identical-command uncertain
retries, source guards, picker errors/cancellation/late disposal, history refresh
and 320-pixel confirmation at 2× text. The app suite contains 87 tests; storage
has 50 tests including correction history, retained/new rows, retired-ID rejection,
stale heads, reopening and historical-command replay.

```powershell
flutter test integration_test/ocr_correction_test.dart -d emulator-5554
flutter test integration_test/ocr_correction_test.dart -d windows
```

The synthetic native smoke corrects through the UI, checks receipt/row IDs,
raw/corrected names and causal revision, reopens SQLite and verifies integrity.
It also commits a competing reviewed command while final confirmation is open
and checks that the stale write cannot replace it. It uses generated synthetic
pixels/seeded OCR geometry and an isolated temporary database, never private
receipts or the normal application-support database. Android is tested in
airplane mode. Restore normal app builds and the prior airplane setting afterwards.

Android can use its production image import/OCR adapter. Windows shares the
review and persistence path, but production Windows OCR packaging/recognition
is still pending. These native tests do not establish recognition accuracy or
Windows OCR availability. Deletion/tombstones, structured backup/restore and
synchronization remain separate milestones.
