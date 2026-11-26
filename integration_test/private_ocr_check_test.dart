import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/receipt_ocr.dart';

// Opt-in local check only. Stage anonymous input-N.jpg files in app-private
// cache/receipt-private-ocr-check via adb run-as, then remove them after testing.
// No private image assets or OCR fixtures are bundled or written by this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('PRIVATE_OCR_CHECK');
  for (var sample = 1; sample <= 3; sample++) {
    testWidgets('local private OCR check $sample (no content logged)', (
      tester,
    ) async {
      final cache = await getTemporaryDirectory();
      final input = File(
        '${cache.path}/receipt-private-ocr-check/input-$sample.jpg',
      );
      final evidence = await ReceiptEvidence.decode(await input.readAsBytes());
      String? failure;
      try {
        final page = await recognizeReceipt(evidence);
        final proposal = proposeLayout(page);
        debugPrint(
          'PRIVATE_OCR_CHECK $sample: success; words=${page.words.length}; size=${page.width}x${page.height}; layout=${proposal.available}',
        );
        expect(page.words, isNotEmpty);
      } catch (error) {
        failure = error is PlatformException
            ? 'native:${error.code}'
            : error.runtimeType.toString();
        if (error is FormatException &&
            const {
              'Invalid pixel rectangle',
              'Word outside image',
              'Unsupported OCR contract',
              'OCR image dimensions differ',
            }.contains(error.message)) {
          failure = error.message;
        }
        debugPrint('PRIVATE_OCR_CHECK $sample: failure=$failure');
        // Count malformed boxes in memory to distinguish engine errors from the
        // shared geometry adapter; never print words, coordinates or raw JSON.
        try {
          final png = await evidence.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final response = await const MethodChannel('receipt_reader/ocr')
              .invokeMethod<String>(
                'recognize',
                png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
              );
          final json = jsonDecode(response!) as Map<String, dynamic>;
          var total = 0, negative = 0, empty = 0, outside = 0;
          for (final block in json['blocks'] as List) {
            for (final line in block['lines'] as List) {
              for (final word in line['words'] as List) {
                total++;
                final box = word['box'];
                final l = box['left'] as num, t = box['top'] as num;
                final r = box['right'] as num, b = box['bottom'] as num;
                if (l < 0 || t < 0) negative++;
                if (r <= l || b <= t) empty++;
                if (r > evidence.image.width || b > evidence.image.height) {
                  outside++;
                }
              }
            }
          }
          debugPrint(
            'PRIVATE_OCR_CHECK $sample: geometry counts total=$total negative=$negative empty=$empty outside=$outside',
          );
        } catch (diagnostic) {
          debugPrint(
            'PRIVATE_OCR_CHECK $sample: diagnostic=${diagnostic is PlatformException ? diagnostic.code : diagnostic.runtimeType}',
          );
        }
      } finally {
        evidence.dispose();
      }
      expect(
        failure,
        isNull,
        reason: 'OCR failed; only sanitized status was recorded',
      );
    }, skip: !enabled || !Platform.isAndroid);
  }
}
