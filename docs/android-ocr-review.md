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

All OCR drafts remain blocked from completion, even when their sums match.
Quantity/rate editing, row-specific evidence links, and resolution of individual
parser issues are still required. Nothing is saved. Closing the review discards
the app's temporary image and draft; the selected original is untouched.

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
