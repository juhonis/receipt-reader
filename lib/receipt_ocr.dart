import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'receipt_import.dart';

bool get supportsReceiptOcr => Platform.isAndroid;

/// Experimental bundled Android candidate. Pixels and results stay in memory.
Future<OcrPage> recognizeReceipt(ReceiptEvidence evidence) async {
  // A clone keeps the pixels alive if the route closes during encoding.
  final image = evidence.image.clone();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw const FormatException('Image encoding failed');
    final json = await const MethodChannel('receipt_reader/ocr')
        .invokeMethod<String>(
          'recognize',
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
    final page = OcrPage.fromJson(jsonDecode(json!) as Map<String, dynamic>);
    if (page.width != image.width || page.height != image.height) {
      throw const FormatException('OCR image dimensions differ');
    }
    return page;
  } finally {
    image.dispose();
  }
}
