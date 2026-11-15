# Synthetic import fixtures

These images contain no receipt or personal data. Generated with Pillow:

- `oversized.png`: solid white RGB, 5000 × 5000 pixels; tests the pixel-count
  rejection before frame decoding despite the small compressed file size.
- `rotated.jpg`: solid red RGB, 12 × 8 pixels, EXIF orientation 6; tests the
  decoder's upright 8 × 12 output and preview disposal.
