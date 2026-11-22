import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../packages/receipt_parser/test/fixtures/finnish_receipts.dart';

/// Test-only invented pixels. Render the source words, never expected outputs.
Future<Uint8List> renderFinnishReceipt(FinnishReceiptFixture fixture) async {
  final page = fixture.page();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  for (final word in page.words) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'monospace',
              fontSize: 28,
              textDirection: ui.TextDirection.ltr,
            ),
          )
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
          ..addText(word.text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: page.width - word.box.left));
    canvas.drawParagraph(paragraph, ui.Offset(word.box.left, word.box.top));
    paragraph.dispose();
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(page.width, page.height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Synthetic fixture encoding failed');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
