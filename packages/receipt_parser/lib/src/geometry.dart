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
  OcrPage(
    this.width,
    this.height,
    Iterable<OcrWord> words, {
    this.baselineSlope = 0,
  }) : words = List.unmodifiable(words) {
    if (!baselineSlope.isFinite ||
        baselineSlope.abs() > .15 ||
        width <= 0 ||
        height <= 0 ||
        this.words.any((w) => w.box.right > width || w.box.bottom > height)) {
      throw FormatException('Word outside image');
    }
  }
  final int width, height;
  final List<OcrWord> words;

  /// Robust local text-line estimate, not a receipt-row or price association.
  final double baselineSlope;
  double baselineY(OcrWord word) =>
      word.box.centerY -
      baselineSlope * ((word.box.left + word.box.right) / 2 - width / 2);

  /// Reads the spike's v1 contract. Blocks and engine line order are ignored.
  factory OcrPage.fromJson(Map<String, dynamic> json) {
    final image = json['image'] as Map<String, dynamic>;
    if (json['schemaVersion'] != 1 || image['orientation'] != 'upright') {
      throw FormatException('Unsupported OCR contract');
    }
    final words = <OcrWord>[];
    final slopes = <double>[];
    for (final block in json['blocks'] as List) {
      for (final line in block['lines'] as List) {
        final lineWords = <OcrWord>[];
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
          lineWords.add(words.last);
        }
        lineWords.sort((a, b) => a.box.left.compareTo(b.box.left));
        if (lineWords.length >= 2) {
          final first = lineWords.first.box;
          final last = lineWords.last.box;
          final span = (last.left + last.right - first.left - first.right) / 2;
          if (span > (image['width'] as int) * .1) {
            final slope = (last.centerY - first.centerY) / span;
            if (slope.abs() <= .15) slopes.add(slope);
          }
        }
      }
    }
    double median(List<double> values) {
      values.sort();
      return values.length.isOdd
          ? values[values.length ~/ 2]
          : (values[values.length ~/ 2 - 1] + values[values.length ~/ 2]) / 2;
    }

    var slope = 0.0;
    if (slopes.length >= 5) {
      final center = median(slopes);
      final deviation = median(slopes.map((s) => (s - center).abs()).toList());
      if (deviation <= .025) slope = center;
    }
    return OcrPage(
      image['width'] as int,
      image['height'] as int,
      words,
      baselineSlope: slope,
    );
  }
}
