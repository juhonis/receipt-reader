import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show BackButton, MaterialPageRoute, OutlinedButton;
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/receipt_ocr.dart';
import 'package:receipt_reader/review_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('receipt_reader/ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'adapter validates dimensions and preserves upright image lifetime',
    () async {
      final evidence = await ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      );
      var width = 8;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'recognize');
        expect(call.arguments, isA<Uint8List>());
        return jsonEncode({
          'schemaVersion': 1,
          'image': {'width': width, 'height': 12, 'orientation': 'upright'},
          'blocks': [],
        });
      });
      expect((await recognizeReceipt(evidence)).height, 12);
      expect(evidence.isDisposed, isFalse);
      width = 12;
      await expectLater(recognizeReceipt(evidence), throwsFormatException);
      evidence.dispose();
    },
  );

  Future<void> open(
    WidgetTester tester,
    Future<OcrPage> Function(ReceiptEvidence) recognize,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    await tester.pumpWidget(const ReceiptReaderApp());
    Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(evidence: evidence, recognizer: recognize),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('abstaining layout requires explicit action and stays gated', (
    tester,
  ) async {
    await open(tester, (_) async => OcrPage(8, 12, []));
    await tester.tap(find.byKey(const Key('recognize')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rajoja ei voitu'), findsOneWidget);
    expect(find.byKey(const Key('ocr-draft-blocked')), findsNothing);
    await tester.tap(find.text('Muodosta riviehdotus näillä rajoilla'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ocr-draft-blocked')), findsOneWidget);
    expect(find.byKey(const Key('review-complete')), findsNothing);
  });

  testWidgets('manual edits disable OCR and failures allow retry', (
    tester,
  ) async {
    await open(tester, (_) async => throw const FormatException());
    await tester.tap(find.byKey(const Key('recognize')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tekstintunnistus epäonnistui'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('branch')), 'My store');
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('recognize')))
          .onPressed,
      isNull,
    );
    expect(find.text('My store'), findsOneWidget);
  });

  testWidgets('late OCR completion after closing route is ignored', (
    tester,
  ) async {
    final pending = Completer<OcrPage>();
    await open(tester, (_) => pending.future);
    await tester.tap(find.byKey(const Key('recognize')));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    pending.complete(OcrPage(8, 12, []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ocr-draft-blocked')), findsNothing);
  });

  testWidgets(
    'confirmed layout seeds rows and keeps original OCR after edits',
    (tester) async {
      final page = OcrPage(800, 1200, [
        OcrWord('15.11.2026', PixelBox(50, 100, 250, 120)),
        OcrWord('MILK', PixelBox(50, 200, 200, 220)),
        OcrWord('2,00', PixelBox(650, 200, 750, 220)),
        OcrWord('BREAD', PixelBox(50, 300, 200, 320)),
        OcrWord('3,00', PixelBox(650, 300, 750, 320)),
        OcrWord('YHTEENSÄ', PixelBox(50, 400, 300, 420)),
        OcrWord('5,00', PixelBox(650, 400, 750, 420)),
      ]);
      await open(tester, (_) async => page);
      await tester.tap(find.byKey(const Key('recognize')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tarkista ehdotetut rajat'), findsOneWidget);
      await tester.tap(find.text('Muodosta riviehdotus näillä rajoilla'));
      await tester.pumpAndSettle();
      expect(find.text('5,00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('row-name-0')),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.enterText(
        find.byKey(const Key('row-name-0')),
        'Corrected milk',
      );
      await tester.pump();
      expect(page.words[1].text, 'MILK');
      expect(find.text('Corrected milk'), findsOneWidget);
      expect(find.byKey(const Key('review-complete')), findsNothing);
    },
  );
}
