# Offline OCR development harness

This isolated package evaluates candidate engines; it is not part of the
receipt app and its dependencies do not select the production OCR stack.
See [findings and the geometry contract](../../docs/ocr-spike.md).

Run commands from the repository root in Windows PowerShell unless noted.
Public SDK/model installation needs internet; recognition uses local inputs.

## Setup

```powershell
winget install --id UB-Mannheim.TesseractOCR --exact --source winget
python -m venv localreceipts/.venv
.\localreceipts\.venv\Scripts\python.exe -m pip install -r tools/ocr_spike/requirements.txt
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/run.py models
flutter pub get --directory tools/ocr_spike
```

The `models` command downloads only pinned public Finnish/English Tesseract
models and verifies their SHA-256 hashes. It never uploads receipt data.
It also copies these public models to the harness's ignored Android assets
directory, so the next APK build bundles them for first-run offline use.
Tesseract was tested with UB Mannheim 5.4.0.20240606. A newer executable may
produce different output; its version is recorded in each result.

## Prepare and run

Put JPEG/PNG files directly in `localreceipts/`, then:

```powershell
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/run.py prepare
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/run.py windows
flutter emulators --launch Receipt_Reader_API_36_1
```

In a terminal at `tools/ocr_spike`, build the separate Android package:

```powershell
flutter build apk --debug
```

Back at the repository root:

```powershell
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/run.py android --device emulator-5554
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/run.py android --engine tesseract --device emulator-5554
.\localreceipts\.venv\Scripts\python.exe -m unittest discover -s tools/ocr_spike -p test_contract.py
```

Use `flutter devices` if the emulator ID differs. Do not use `flutter run`
for this harness: its merged manifest deliberately removes INTERNET permission,
so Flutter's network-based debugger cannot attach normally. The runner installs
and launches it through ADB instead.

The Android command removes an existing `fi.juhonis.ocr_spike` installation,
enables airplane mode before installation, stages hash-verified image copies
in app-private storage, and runs the chosen bundled engine on a fresh install.
The default is ML Kit Latin; `--engine tesseract` evaluates both segmentation
modes 3 and 6 with bundled Finnish/English models via Tesseract4Android 4.9.0.
It retrieves private results, uninstalls the harness, and restores the previous
airplane-mode setting in `finally`. The ordinary receipt app is untouched.
If the host process is killed, uninstall `fi.juhonis.ocr_spike` manually and
restore airplane mode; process cleanup cannot execute after forced termination.

## Private artifacts

All images, public model downloads, raw text, geometry, installation evidence,
and manual amount expectations live under ignored `localreceipts/ocr/`.
Source photos are read-only. Preparation applies EXIF orientation, strips
metadata, and writes full-resolution RGB PNG copies. No crop, deskew, contrast
adjustment, or resizing is applied in this baseline. IDs follow sorted filenames
and can change if the input set changes; SHA-256 identifies the actual input.

`expected.json`, if present, contains manually transcribed financial amounts.
It is private reference material, not an automatic correctness score.
Do not commit any real receipt output or include it in the production app.
The harness intentionally retains host-side artifacts for inspection; this is
an explicit development export, not the production image-retention policy.

## Controlled Windows preprocessing and portable prototype

These commands require the private baseline inputs and pinned models above:

```powershell
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/preprocess.py
.\localreceipts\.venv\Scripts\python.exe tools/ocr_spike/bundle_windows.py
.\localreceipts\.venv\Scripts\python.exe -m unittest discover -s tools/ocr_spike -p 'test_*.py'
```

Preprocessing additionally needs private `localreceipts/ocr/annotations.json`.
Its top-level keys are manifest sample IDs. Each value has `inputSha256`
(the prepared PNG hash), `quad` (four pixel points TL/TR/BR/BL), and
`amountRegions` (objects with `id`, `box: [left, top, right, bottom]`, and
`amountCents`). Annotate from the image, including the printed total separately;
exclude unit rates and explanatory discounts from posted amount regions.
Inspect region placement before interpreting matches. The annotation file is
deliberately private and must be recreated for new images.

The runner compares baseline, bounding crop, manual perspective correction,
and perspective correction with grayscale percentile contrast, in PSM 3/6.
All variants preserve their image hashes and forward/inverse transforms in
private JSON. The report probes word centers inside the annotated regions;
it is not a parser or a full receipt accuracy metric. OpenCV and NumPy are
development-only dependencies; pefile audits Windows PE imports.

The bundle command recursively copies the executable's imported/delay-imported
DLL closure, pinned models, and available source notices to a new private folder.
It relocates that folder to a path with spaces, removes system Tesseract from
PATH, clears TESSDATA_PREFIX, and explicitly selects the bundled models. Every
saved preprocessing case must reproduce identical text and word geometry.
Hashes, OS imports, and smoke evidence are saved beside the private bundle.
The source installation remains installed: this is a relocation smoke test,
not a clean-machine test or a runtime loaded-module audit. Complete dependency
and model notices, clean offline Windows testing, and Flutter integration are
still required before distribution. No downloadable release is produced.
