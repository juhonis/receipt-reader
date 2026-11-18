import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'receipt_import.dart';
import 'windows_ocr.dart';

bool get supportsReceiptOcr =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.windows;

/// A route-owned request. Pixels and recognition output are never saved to disk.
final class ReceiptRecognition {
  ReceiptRecognition(ReceiptEvidence evidence) {
    final image = evidence.image.clone();
    result = _recognize(image);
  }
  late final Future<OcrPage> result;
  WindowsOcrTask? _windows;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _windows?.cancel();
  }

  Future<OcrPage> _recognize(ui.Image image) async {
    try {
      final windows = defaultTargetPlatform == TargetPlatform.windows;
      if (!windows && defaultTargetPlatform != TargetPlatform.android) {
        throw const FormatException('Unsupported OCR platform');
      }
      final bytes = await image.toByteData(
        format: windows
            ? ui.ImageByteFormat.rawStraightRgba
            : ui.ImageByteFormat.png,
      );
      if (bytes == null || _cancelled) {
        throw const FormatException('Recognition unavailable');
      }
      final input = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (windows) {
        final task = WindowsOcrTask(input, image.width, image.height);
        _windows = task;
        if (_cancelled) task.cancel();
        return await task.result;
      }
      final json = await const MethodChannel('receipt_reader/ocr')
          .invokeMethod<String>('recognize', input);
      if (_cancelled) throw const FormatException('Recognition cancelled');
      final page = OcrPage.fromJson(jsonDecode(json!) as Map<String, dynamic>);
      if (page.width != image.width || page.height != image.height) {
        throw const FormatException('OCR image dimensions differ');
      }
      return page;
    } finally {
      image.dispose();
    }
  }
}

Future<OcrPage> recognizeReceipt(ReceiptEvidence evidence) =>
    ReceiptRecognition(evidence).result;
