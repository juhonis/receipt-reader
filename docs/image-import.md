# Temporary receipt image import

The home screen's **Avaa kuittikuva** opens one JPEG/PNG for manual review.
Android uses the system document picker; Windows uses the native file picker.
The image is displayed above the fields on narrow screens and beside them at
widths of 1000 logical pixels or more. Zoom/pan allows comparison with the
receipt. Users must check that the complete receipt is visible; this iteration
does not detect truncated or multi-page captures.

Imported evidence now supports the shared [OCR review/save workflow](ocr-saving.md)
and [saved history](history-filters.md). The limits and original-file ownership below
still apply. Android also offers **Ota kuva**, using an in-app rear-camera preview
and a memory-only JPEG handoff. It creates no gallery or temporary image file;
decoded pixels follow the same review lifetime. Captures are limited to 12 million
pixels and the same 20 MiB input cap. Cancel/backgrounding closes the camera.
PDF, multiple selection and image-backed persisted drafts remain deferred.

## Limits and lifetime

- Only JPEG/PNG signatures are accepted, followed by actual codec validation.
  Animated images are rejected. Extension filters assist selection but are not
  trusted as content validation.
- Input is limited to 20 MiB (20 × 1024 × 1024 bytes), 24 million pixels, and
  12,000 pixels per side. Encoded dimensions are checked before frame decoding.
  These are provisional resource limits, not receipt-accuracy thresholds.
- A synthetic EXIF-rotated JPEG test verifies that Flutter's decoder honors
  orientation. Full-resolution decoded pixels are used for the preview.
- Preview pixels are route-owned `ui.Image` objects displayed with `RawImage`;
  the image is not inserted into Flutter's global image cache. Pixels are
  explicitly disposed on review exit and when import finishes after the owning
  screen has gone away. Encoded buffers, descriptors, and codecs are released
  after decoding, including error paths. Managed bytes become garbage-collectable;
  this does not claim forensic memory erasure.
- No app-owned image file, thumbnail, database record, or image log is created.
  Original files are read-only and never deleted or overwritten. Process death
  leaves no import cache to sweep on startup. OS/provider caches and screenshots
  outside this app are not controlled by this implementation.

## Platform implementation

Windows uses pinned `file_selector` 1.1.0. It checks the selected file's length
and reads a bounded stream, so a growing file cannot bypass the byte cap.

The package's Android implementation copies selections to a cache file. This
app deliberately does not call that implementation. Its small native channel
launches `ACTION_OPEN_DOCUMENT` for JPEG/PNG, requests local/openable content,
and reads the provider stream into bounded memory on a worker thread. It never
takes a persistent URI grant or requests write access. Cancellation returns no
image; provider/read errors return a generic code without paths or receipt text.
There is no app network request or upload. A provider/network filesystem can
have its own behavior; select locally available files for offline use.

The native picker is single-flight. Dart also prevents repeated import clicks
while selection or review is active. Return/back discards the review session.
The original source remains available to select again.

## Verification

Flutter tests cover format rejection, byte/pixel limits, malformed JPEG data,
EXIF orientation, cancel/error behavior, preview disposal and cache exclusion,
and side-by-side desktop layout. The committed JPEG and PNG fixtures are generated
solid-color images with no personal receipt data. Existing review tests continue
to cover editing, enlarged text, and the unresolved-OCR completion gate.

Native picker smoke tests use generated synthetic receipt images only. Private
development photos remain in ignored `localreceipts/` and are not app assets.

Verified on 2026-11-15: eleven Flutter tests pass and analysis is clean. The Android
debug build launched on the API 36 emulator; the native picker opened a generated
synthetic PNG into the preview. Its source SHA-256 remained unchanged, and the
app cache directory was empty during preview and after back navigation. Native
picker cancellation returned to the home screen. The Windows debug build succeeds;
desktop picker interaction was not manually smoke-tested at that milestone.

On November 25, 2026, the opted-in native image-picker harness passed on Windows
and the Android emulator: import the committed synthetic 1000×1000 receipt, dispose
the preview and cancel a second import. Source SHA-256 remained unchanged. The
native backup-picker round trip also passed on both platforms. Reproduction commands
are in [testing](testing.md#restore-normal-entry-points-after-integration-tests).

On November 26, the offline emulator camera harness passed denial/grant, cancel,
two upright captures with native OCR, and background/resume cancellation. Gallery
image IDs and app-private image paths were unchanged; prior permission/airplane
state was restored. The 239 app tests and analysis pass. Physical-phone focus,
lighting and long-receipt quality remain acceptance checks.
Synthetic preview/capture framing was also compared in portrait and landscape;
the native transform avoids applying the sensor rotation twice.
