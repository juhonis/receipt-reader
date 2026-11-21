# Approved OCR engines and Windows development bundle

Approved on November 18, 2026: keep Google's bundled Latin-script ML Kit on
Android; use app-bundled Tesseract with Finnish and English models on Windows;
distribute the Windows MVP as a complete ZIP. Recognition adapters differ, while
geometry parsing, financial validation, review, catalog links and saving stay shared.

This is the implementation direction for the MVP, not an accuracy certification.
The [initial spike](ocr-spike.md) used three private photos from one branch and
found missed/corrupted Windows amounts. The Android shared-engine experiment did
not demonstrate a reason to replace ML Kit. A broader representative corpus is
still needed before claiming general recognition quality. User approval and exact
reconciliation remain mandatory regardless of the engine.

## Pins and build design

- Android: com.google.mlkit:text-recognition:16.0.1, bundled Latin model. No runtime
  model-download choice or cloud fallback is added.
- Windows: Tesseract 5.5.1 and Leptonica 1.85.0, built from public upstream source
  archives with SHA-256 checks. No executable or DLL is taken from the installed
  development Tesseract or the earlier private relocation prototype.
- Models: tessdata_fast Finnish and English, revision
  87416418657359cb625c412a48b6e1d6d41c29bd. Model/license hashes and archive URLs are
  committed in tools/windows_ocr/sources.json.
- Initial Windows recognition uses LSTM only and fixed page segmentation mode 6.
  It does not choose between modes by checking whose total happens to reconcile.
  Comparing best versus fast models remains a quality experiment, not a new engine
  decision or a user-facing setting.
- The worker statically links Tesseract/Leptonica and the MSVC runtime. Training,
  legacy recognition, OpenMP, native-CPU-specific optimization, graphics,
  libcurl/libarchive and external image codecs are disabled. Flutter supplies
  decoded pixels, so the worker needs no extra image codec DLLs.

Sources download during explicit developer setup. Recognition needs no Python,
Tesseract installation, internet or PATH changes. The binary is x64; Windows
ARM-native distribution is not implemented here.

Upstream references: [Tesseract models](https://tesseract-ocr.github.io/tessdoc/Data-Files.html),
[bundled ML Kit](https://developers.google.com/ml-kit/vision/text-recognition/v2/android),
and [Flutter ZIP/MSIX distribution](https://docs.flutter.dev/platform-integration/windows/building).

## Developer setup and builds

Use Windows Python 3.12+ and the existing Visual Studio 2022 C++/CMake tools. Python
is a build tool only. Setup uses its standard library and discovers Visual Studio
with vswhere when cmake is not on PATH:

    python tools/windows_ocr/setup.py
    flutter build windows --release
    python tools/windows_ocr/package.py

Sources, intermediates, logs and the OCR bundle are under ignored build/windows-ocr/.
Subsequent setup runs reuse verified public downloads and incremental builds.
Compiler/toolchain differences may change binary hashes: the build pins inputs,
not byte-identical outputs across machines. Private receipt directories are unused.

Windows CMake requires the prepared manifest/worker and copies the bundle beside
the Flutter executable in ocr/. A missing setup step fails the build with the
setup command; there is no fallback to an installed engine. Android-only builds
need no Windows OCR setup. Repeat setup after flutter clean removes the build cache.

The ZIP includes the normal release, app-local Visual C++ runtime DLLs, OCR notices,
BUILD-INFO.json, a synthetic PNG and clean-machine instructions. Packaging checks
PE architecture/import dependencies and bundle hashes, extracts to a new path with
spaces and Finnish characters, then runs model initialization and malformed-input
checks with sanitized PATH. It does not publish or modify normal receipt data.

Artifacts:

- build/distribution/receipt-reader-windows-x64-dev.zip
- build/distribution/windows-ocr-evidence.json: ZIP SHA-256, sizes, relocation
  results, import audit, source commit and working-tree state.

This is a development ZIP, not a signed installer. Data remains in Windows
application-support storage; moving the program does not move or back up receipt
history. A signed installer/MSIX can follow for wider distribution.

## Runtime contract and privacy

The route-owned decoded image is cloned and encoded as straight RGBA in memory.
The worker receives RRO1 plus little-endian dimensions and exactly four bytes per
pixel through stdin. It composites alpha on white, converts to 8-bit grayscale,
and returns UTF-8 TSV word boxes. No original paths, receipt photos, intermediate
images, OCR files or subprocess logs are written to disk. Tesseract diagnostics
go to NUL and Leptonica logging is suppressed. Bounded stderr is discarded;
exceptions expose sanitized codes rather than paths, receipt text or diagnostics.

Input matches image import: dimensions at most 12000, at most 24 million pixels.
Output is capped at 8 MiB, stderr at 64 KiB and accepted words at 50000. The adapter
validates dimensions, page count, TSV structure and every word rectangle. Malformed
output fails completely rather than returning partial rows. Paragraph IDs scope
line grouping, preventing repeated native line numbers from merging paragraphs.
The shared geometry layer estimates baselines as before.

One Windows request runs at a time. The absolute app-owned executable starts
without a shell, in its OCR directory, with a sanitized environment. Worker/model
hashes are checked before execution; model hashes are also pinned in Dart. This
detects missing/corrupt assets and does not substitute for signing or protect
against replacement of the entire application.

Recognition has a 90-second deadline. Closing review cancels the Windows worker;
late results cannot overwrite a closed route. The image clone is disposed after
completion. Android retains its in-memory adapter: a closed route ignores its
result while the native request finishes and releases its bitmap. Failure leaves
retry/manual entry available. Ordinary review screens expose no engine settings.

## Verification and release gates

    flutter analyze
    flutter test
    flutter test integration_test/receipt_ocr_engine_test.dart -d windows
    flutter test integration_test/receipt_ocr_engine_test.dart -d emulator-5554

Native verification uses generated synthetic pixels and guarded ocr-ui-smoke-*
app-support directories. It invokes the real engine, explicitly sets boundaries,
keeps saving gated, completes review controls, saves OCR provenance and checks
exact content after reopen. Windows also tests cancellation, deadline expiry and
successful retry. Android runs in airplane mode; restore its prior setting and
normal APK afterward.

Verified on November 18, 2026: all 142 app tests and analysis pass; actual-engine
recognition/review/save/reopen passes on Windows and Android (airplane mode).
Windows cancellation, deadline expiry and retry pass. The development ZIP is about
22 MB compressed (about 51 MB extracted), passes native-import/checksum validation,
and initializes models after Unicode/space-path relocation with sanitized PATH.
Five malformed protocol inputs are rejected and runtime files stay unchanged.
The included PNG also recognizes both products, their amounts, date and total using
the release worker; its source hash stays unchanged. Reproduce that check with:

    powershell -NoProfile -ExecutionPolicy Bypass -File tools/windows_ocr/smoke_image.ps1

Android release manifest merging now explicitly removes INTERNET and
ACCESS_NETWORK_STATE introduced by dependencies. This is appropriate for the
current standalone feature set; enabling future LAN sync requires a new permission
and SDK-networking review. Debug builds retain Flutter debugger connectivity.
The release APK permission inspection is separate from the offline native smoke.

OCR notices cover pinned Tesseract, Leptonica and model assets. Packaging includes
Flutter dependency notices and Visual C++ runtime DLLs. Final redistribution-license
review, signing and clean-machine first launch remain release gates. Local
relocation does not establish clean-install success. The user has a second Windows
PC available; use the [clean-machine instructions](windows-ocr-clean-machine.md)
to obtain that evidence.

## Laptop feedback and review guidance (November 21, 2026)

The user reported successful offline startup on the second Windows laptop and
correct recognition of the included sample's date, items and total. Saving was
blocked at the disabled final review checkbox, even after manually naming a new
branch. The exact transferred ZIP hash, remaining audit state and complete dialog
interaction were not reported, so this is partial user evidence rather than proof
of a completed save workflow or a diagnosed parser failure.

The exact shipped PNG now has a dedicated native Windows regression. Its pinned
source hash is checked, the real worker recognizes it, the proposed boundaries are
used, a first branch is named, both rows are compared and the whole-receipt dialog
is explicitly approved with a note. The receipt saves as 5,00 € with two rows and
survives reopen. No parser findings remain on the reproduced input.

The UI now opens first-branch naming on an empty installation, explains explicit
branch selection, lists outstanding row/page checks beside the disabled final
confirmation, and labels the whole-receipt note as required. Checking the four
dialog boxes without a note or without pressing its confirmation button does not
record approval. Later edits still invalidate prior checks. No review requirement
or persistence policy was weakened.

Run the exact-fixture Windows regression from the repository root:

    $ocrFixture = (Resolve-Path test/fixtures/synthetic_receipt.png).Path
    flutter test integration_test/ocr_first_install_test.dart -d windows --dart-define="OCR_SMOKE_FIXTURE=$ocrFixture"

A committed geometry fixture from this synthetic PNG supports deterministic widget
checks for first-branch entry, successful saving, required notes, reopened checks
after editing, and narrow enlarged-text layouts. Private receipts are not used.
The updated ZIP still needs a laptop save/reopen retest; relocation/cancellation
and complete clean-machine release acceptance remain unconfirmed by that report.

Verification for this guidance update: all 145 app tests and analysis pass, the
exact-shipped-image Windows recognition/review/save/reopen regression passes, and
the Android real-engine save/reopen regression passes in airplane mode. The ZIP
passes the existing dependency, checksum, malformed-input and relocation checks.
