class PixelBox {
  PixelBox(this.left, this.top, this.right, this.bottom) {
    if (![left, top, right, bottom].every((n) => n.isFinite) ||
        left < 0 ||
        top < 0 ||
        right <= left ||
        bottom <= top) {
      throw FormatException('Invalid pixel rectangle');
    }
  }
  final double left, top, right, bottom;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

class OcrWord {
  OcrWord(this.text, this.box);
  final String text;
  final PixelBox box;
}

class OcrPage {
  OcrPage(this.width, this.height, Iterable<OcrWord> words)
    : words = List.unmodifiable(words) {
    if (width <= 0 ||
        height <= 0 ||
        this.words.any((w) => w.box.right > width || w.box.bottom > height)) {
      throw FormatException('Word outside image');
    }
  }
  final int width, height;
  final List<OcrWord> words;

  /// Reads the spike's v1 contract. Blocks and engine line order are ignored.
  factory OcrPage.fromJson(Map<String, dynamic> json) {
    final image = json['image'] as Map<String, dynamic>;
    if (json['schemaVersion'] != 1 || image['orientation'] != 'upright') {
      throw FormatException('Unsupported OCR contract');
    }
    final words = <OcrWord>[];
    for (final block in json['blocks'] as List) {
      for (final line in block['lines'] as List) {
        for (final word in line['words'] as List) {
          final b = word['box'];
          words.add(
            OcrWord(
              word['text'] as String,
              PixelBox(
                (b['left'] as num).toDouble(),
                (b['top'] as num).toDouble(),
                (b['right'] as num).toDouble(),
                (b['bottom'] as num).toDouble(),
              ),
            ),
          );
        }
      }
    }
    return OcrPage(image['width'] as int, image['height'] as int, words);
  }
}
