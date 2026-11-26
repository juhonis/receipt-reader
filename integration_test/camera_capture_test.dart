import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/receipt_ocr.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const interactive = bool.fromEnvironment('INTERACTIVE_CAMERA');
  testWidgets(
    'private camera denial, cancellation, OCR, reuse and background cleanup',
    (tester) async {
      Future<void> stage(String name) async {
        // Only synthetic emulator pixels; no application store is opened.
        debugPrint('CAMERA CHECK: $name');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Center(child: Text('Camera check: $name'))),
          ),
        );
        await tester.pumpAndSettle();
      }

      await stage('deny permission');
      await expectLater(
        captureReceiptImage(),
        throwsA(
          isA<ReceiptImportException>().having(
            (error) => error.failure,
            'failure',
            ImportFailure.cameraDenied,
          ),
        ),
      );

      await stage('grant permission and cancel');
      expect(await captureReceiptImage(), isNull);

      for (var attempt = 0; attempt < 2; attempt++) {
        await stage('capture ${attempt + 1}');
        final evidence = await captureReceiptImage();
        expect(evidence, isNotNull);
        try {
          expect(
            evidence!.image.width * evidence.image.height,
            lessThanOrEqualTo(12 * 1000 * 1000),
          );
          expect(
            evidence.image.height,
            greaterThanOrEqualTo(evidence.image.width),
          );
          if (attempt == 0) {
            final page = await recognizeReceipt(evidence);
            expect(page.width, evidence.image.width);
            expect(page.height, evidence.image.height);
          }
          expect(PaintingBinding.instance.imageCache.currentSize, 0);
        } finally {
          evidence?.dispose();
        }
        expect(evidence.isDisposed, isTrue);
      }
      await stage('background cancels');
      expect(await captureReceiptImage(), isNull);
    },
    skip: !interactive || !supportsReceiptCamera,
  );
}
