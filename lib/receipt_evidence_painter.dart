import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

class ReceiptEvidencePainter extends CustomPainter {
  ReceiptEvidencePainter(this.image, this.words);
  final ui.Image image;
  final List<OcrWord> words;
  @override
  void paint(Canvas canvas, Size size) {
    var left = words.first.box.left, top = words.first.box.top;
    var right = words.first.box.right, bottom = words.first.box.bottom;
    for (final word in words.skip(1)) {
      if (word.box.left < left) left = word.box.left;
      if (word.box.top < top) top = word.box.top;
      if (word.box.right > right) right = word.box.right;
      if (word.box.bottom > bottom) bottom = word.box.bottom;
    }
    final source = Rect.fromLTRB(
      (left - 12).clamp(0, image.width).toDouble(),
      (top - 12).clamp(0, image.height).toDouble(),
      (right + 12).clamp(0, image.width).toDouble(),
      (bottom + 12).clamp(0, image.height).toDouble(),
    );
    if (source.isEmpty) return;
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(image, source, destination, Paint());
  }

  @override
  bool shouldRepaint(ReceiptEvidencePainter oldDelegate) =>
      image != oldDelegate.image || words != oldDelegate.words;
}
