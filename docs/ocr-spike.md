# Offline OCR spike: platform baselines

Status: **exploratory; no production engine selected**. Run on 2026-11-14.
The independent harness is in [`tools/ocr_spike`](../tools/ocr_spike/README.md).
The receipt app's dependency list and starter screen are unchanged.

## Scope and evidence

Three private receipt photos from one store branch cover quantities, deposits,
weighed goods, and an already-net campaign price. The photos include folds,
slight perspective distortion, and background clutter. This is a small initial
corpus, not evidence of general receipt accuracy.

The originals remain unchanged in `localreceipts/`. Prepared PNGs, raw OCR,
geometry, engine/model versions, hashes, timings, and Android installation
evidence are retained only in ignored `localreceipts/ocr/`. Manually transcribed
line amounts reconcile to the printed total for each sample; these private
expectations are a starting point, not complete annotated parser fixtures.

### Android ML Kit baseline

- `google_mlkit_text_recognition` is pinned to 1.0.3 in the separate harness.
  Its Android dependency is **bundled** `com.google.mlkit:text-recognition:16.0.1`.
- All three photos completed on a fresh harness installation after airplane
  mode was enabled. The merged APK has no INTERNET permission. The runner checks
  that permission before installing; this also blocks library telemetry over
  the network during the experiment.
- APK inspection confirms native OCR libraries and Latin recognition model
  assets are included. Results and APK hash are in `android-evidence.json`.
- The runner verifies transferred image bytes against host hashes, validates
  output coordinates and dimensions, then uninstalls the harness and restores
  the previous airplane-mode setting. No image copy is left in shared Android
  storage. The host deliberately retains private development exports.
- Manual inspection found the expected posted line amounts in the price
  column for these samples. This is not an automatic row-association test or
  evidence that product names, quantities, or units are all correct.
- Recognition confused some Finnish diacritics and letters/digits in names.
  It frequently put the names and prices in separate blocks, sometimes with
  footer text between them in plain-text order. Reading order cannot define
  financial rows; use the word geometry and require user review.

### Windows Tesseract baseline

- Tested UB Mannheim Tesseract **5.4.0.20240606** as a local command-line
  process, with pinned `tessdata_fast` Finnish + English models. Exact model
  revision and SHA-256 hashes are recorded in `tools/ocr_spike/run.py`.
- Ran page segmentation modes **3** (automatic page layout) and **6** (single
  uniform text block) on identical prepared PNGs. Both returned TSV word boxes
  for all three inputs. Recognition uses installed assets; it has no model
  download step or cloud fallback in this harness.
- Both configurations recognized the printed totals on these samples, but
  missed or corrupted some individual item amounts. Mode 3 omitted several
  prices on one sample; mode 6 recovered those but still introduced other
  character/layout errors. Choosing the mode by total recognition would hide
  these failures. Image preprocessing and more samples need evaluation.
- This is **not yet a bundled Flutter Windows OCR adapter**. The baseline uses
  the development installation; the later relocation prototype is described below.

Timing fields are single-run diagnostic measurements. Android timing covers
recognition after decoding; Windows timing includes subprocess startup and TSV
conversion. They are not comparable benchmarks. The Android APK is a debug,
multi-ABI build; its size must not be presented as a release-size estimate.

### Shared-engine candidate: Tesseract on Android

- Added a native development adapter using **Tesseract4Android 4.9.0**
  (Tesseract **5.5.1**, standard single-threaded build). It runs outside the UI
  thread and exports block/line/word rectangles through the native iterator.
- The exact same pinned Finnish/English models are bundled as APK assets.
  The host verifies their SHA-256 hashes inside the APK before installing;
  no runtime model download is involved. Receipt images are never APK assets.
- All three images completed in modes 3 and 6 on a fresh installation in
  airplane mode, with INTERNET permission absent. Results passed the same
  image-dimension and coordinate checks as ML Kit and Windows Tesseract.
- The same important layout failures remained: mode 3 missed several prices
  on one sample, and mode 6 recovered those while still corrupting some amounts
  elsewhere. The shared-engine option is technically feasible, but this
  baseline does not justify choosing it for recognition quality.
- Windows 5.4.0 and Android 5.5.1 are different native versions. Matching model
  and input hashes makes the inputs controlled, but does not isolate the effect
  of OS, compiler, native version, or segmentation implementation.
- The experimental APK now includes both candidates. Its total size cannot be
  attributed to either engine individually. Model extraction temporarily keeps
  a second copy in app-private storage; the runner removes it with the harness.

The provisional direction is to keep ML Kit as the Android front-runner while
improving and packaging Windows OCR. This is based on manual inspection of this
small corpus, not a completed engine choice, correctness score, or guarantee.

## Proposed normalized geometry contract (version 1)

Both adapters export the same JSON shape:

```text
schemaVersion: 1
sampleId: anonymous local identifier
inputSha256: hash of the prepared PNG (added by the host)
engine, adapterVersion, elapsedMs
image: { width, height, orientation: "upright" }
text: engine output, retained only for development inspection
blocks: [
  { text, box, lines: [
    { text, box, words: [ { text, box, corners } ] }
  ] }
]
```

`box` is `{left, top, right, bottom}` in pixels of the **prepared upright
image**, with origin at the top left, x increasing right, and y increasing
down. Bounds are half-open and must satisfy `0 <= left < right <= width` and
`0 <= top < bottom <= height`. No normalized 0..1 coordinates are mixed in.

`corners` holds four engine-reported points in clockwise order from top left,
or `null` when unavailable. Tesseract TSV does not provide rotated quadrilaterals;
its line/block rectangles are unions of word rectangles. ML Kit supplies native
word corners and line/block rectangles. Preserve these differences rather than
inventing equivalent geometry. Blocks and lines are engine groupings, not
canonical receipt rows; do not assume they are sorted or pair prices by index.
The Android Tesseract adapter uses native iterator rectangles and reports
`corners: null`; it does not synthesize rotated corners.

For preprocessing experiments, boxes refer to the actual variant image named
by `inputSha256`, not the original prepared PNG. `preparedInputSha256` and
`transform` record that original's dimensions and 3x3 forward/inverse homographies.
Map all four box corners for source overlays; the amount probe maps only centers.

Optional engine-specific configuration/model hashes may be attached. Confidence
values are deliberately absent from this contract; they do not verify amounts
or product identity. Raw text and coordinates are development fixture data,
not a proposal to persist production receipt images or full OCR dumps.

The Python adapter tests use synthetic words only and verify TSV grouping,
paragraph-scoped line IDs, rectangle aggregation, invalid coordinates, invalid
orientation, and rejection of plain text masquerading as TSV.

## Licensing and packaging checkpoints

- Tesseract and tessdata are Apache-2.0 projects. Shipping a Windows bundle
  still requires auditing the exact binary distribution, dependencies,
  license/notice files, and model assets. Installing the development executable
  does not complete this audit.
- The Flutter ML Kit wrapper is MIT-licensed; Google's native ML Kit SDK/model
  terms are separate. Review [ML Kit terms](https://developers.google.com/ml-kit/terms)
  before choosing the production integration.
- Tesseract4Android 4.9.0 is Apache-2.0 and ships native Tesseract, Leptonica,
  libjpeg, and libpng components with their own notices. The harness restricts
  its JitPack repository to that dependency group; production distribution
  still needs the complete native dependency/license audit.
- The harness uses Pillow 12.2.0 only for local preparation. It is not a runtime
  app dependency. Public SDK/model downloads occur during explicit setup only.

## Windows preprocessing and relocation experiment

Tested the same three images with baseline, manually guided bounding crop,
perspective correction, and perspective correction plus grayscale contrast.
Each variant ran in PSM 3 and 6 using the same Windows executable and models.
Originals remain hash-identical. Paper corners and posted-amount rectangles
were annotated privately and their placement visually checked against the photos.

Cropping recovered missing price-column text in one layout, but no variant
consistently fixed recognition. Perspective correction introduced or retained
errors on other images. Keep preprocessing optional pending broader evidence;
manual corners are not automatic receipt detection. The private spatial probe
checks strict decimal amounts at annotated positions, including the total.
It does not verify product identity, quantity, discount semantics, or row assembly,
and its matches must not be presented as whole-receipt accuracy.

Built a private relocatable Windows prototype from the installed executable's
recursive PE import/delay-import dependency closure, plus pinned models.
It ran in a new path containing spaces with a sanitized PATH and explicit
bundle-relative model selection. All 24 preprocessing cases reproduced the
installed executable's text and geometry exactly. The private bundle contains
binary/model hashes, system dependency names, and smoke evidence.

This verifies local relocation only. System Tesseract remains installed;
runtime loaded modules were not audited. Windows Sandbox is unavailable on
this PC, and a clean Windows machine without development tooling has not been
tested. Available source notices were retained, but complete dependency/model
license notices and release size remain open. Do not distribute this prototype
or mark the fresh-install milestone complete. No production Flutter code changed.

Seven synthetic Python tests cover the geometry adapter, transform round trips,
invalid crop corners, and signed amount probes that exclude footer regions and
reject character guesses. Real receipt data and all prototype binaries stay ignored.

## Next work

1. Extend the shared-engine comparison with matched native versions and more
   representative inputs if pursuing it further. Initial Android Tesseract
   feasibility is verified; the full engine-selection milestone remains open.
2. Expand the controlled preprocessing experiment to a broader private corpus,
   including returns, ambiguous dates, incomplete receipts, and longer layouts.
3. Build geometry-aware row assembly against manually annotated expectations.
   Preserve signed cents, fixed-point quantities, and the distinction between
   a posted net price and an explanatory discount. The discount already included
   in a net amount must not be subtracted a second time.
4. Complete dependency notices and verify the Windows prototype on a clean
   offline Windows installation, then measure release size and comparable
   cold/warm timings.
5. Finalize the Dart `OcrEngine` interface and dependency choice using that
   evidence. Do not wire an experimental engine into the production app yet.
