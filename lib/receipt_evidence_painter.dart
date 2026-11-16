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

/// Original upright pixels with overlays; never rotates/resamples OCR geometry.
class ReceiptLayoutPainter extends CustomPainter {
  ReceiptLayoutPainter(
    this.image,
    this.page,
    this.itemTop,
    this.priceLeft,
    this.highlights,
    this.showWords,
  );
  final ui.Image image;
  final OcrPage page;
  final double itemTop, priceLeft;
  final List<OcrWord> highlights;
  final bool showWords;
  @override
  void paint(Canvas canvas, Size size) {
    final source = Size(page.width.toDouble(), page.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, source, size);
    final destination = Alignment.center.inscribe(
      fit.destination,
      Offset.zero & size,
    );
    final scale = destination.width / source.width;
    if (scale <= 0) return;
    canvas.save();
    canvas.clipRect(destination);
    canvas.translate(destination.left, destination.top);
    canvas.scale(scale);
    canvas.drawImage(image, Offset.zero, Paint());
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    if (showWords) {
      paint.color = Colors.grey;
      for (final word in page.words) {
        canvas.drawRect(
          Rect.fromLTRB(
            word.box.left,
            word.box.top,
            word.box.right,
            word.box.bottom,
          ),
          paint,
        );
      }
    }
    paint
      ..color = Colors.orange
      ..strokeWidth = 2 / scale;
    for (final word in highlights) {
      canvas.drawRect(
        Rect.fromLTRB(
          word.box.left,
          word.box.top,
          word.box.right,
          word.box.bottom,
        ),
        paint,
      );
    }
    paint.color = Colors.red;
    canvas.drawLine(Offset(0, itemTop), Offset(source.width, itemTop), paint);
    paint.color = Colors.blue;
    canvas.drawLine(
      Offset(priceLeft, 0),
      Offset(priceLeft, source.height),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ReceiptLayoutPainter old) =>
      image != old.image ||
      page != old.page ||
      itemTop != old.itemTop ||
      priceLeft != old.priceLeft ||
      highlights != old.highlights ||
      showWords != old.showWords;
}
