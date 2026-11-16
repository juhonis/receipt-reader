import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/receipt_evidence_painter.dart';
import 'package:receipt_reader/review_page.dart';

void main() {
  final page = OcrPage(8, 12, [
    OcrWord('16.11.2026', PixelBox(.5, .5, 3, 1)),
    OcrWord('MILK', PixelBox(.5, 3, 3, 3.5)),
    OcrWord('2,00', PixelBox(6, 3, 7.5, 3.5)),
    OcrWord('YHTEENSÄ', PixelBox(.5, 6, 3, 6.5)),
    OcrWord('2,00', PixelBox(6, 6, 7.5, 6.5)),
  ]);
  final vertical = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;

  Future<ReceiptEvidence> open(WidgetTester tester, ReceiptDraft draft) async {
    tester.view.physicalSize = const Size(1400, 2300);
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
        builder: (_) => ReviewPage(draft: draft, evidence: evidence),
      ),
    );
    await tester.pumpAndSettle();
    return evidence;
  }

  test('cloned image handles have independent lifetimes', () async {
    final evidence = await ReceiptEvidence.decode(
      await File('test/fixtures/rotated.jpg').readAsBytes(),
    );
    final clone = evidence.clone();
    evidence.dispose();
    expect(clone.isDisposed, isFalse);
    expect(await clone.image.toByteData(), isNotNull);
    clone.dispose();
    expect(() => evidence.clone(), throwsStateError);
  });

  testWidgets(
    'new layout review owns its image and preserves parent corrections on back',
    (tester) async {
      final original = parseReceipt(page, itemTop: 3.25, priceColumnLeft: 5);
      final evidence = await open(tester, original);
      await tester.enterText(find.byKey(const Key('total')), '9,99');
      await tester.enterText(
        find.byKey(const Key('branch')),
        'Original branch',
      );
      await tester.tap(find.byKey(const Key('inspect-layout')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('open-layout-review')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('preview-layout')));
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('repair-item-top'));
      final bounds = tester.getRect(slider);
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .15, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('open-layout-review')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('preview-layout')));
      await tester.pumpAndSettle();
      expect(find.text('MILK: 2,00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-layout-review')));
      await tester.pumpAndSettle();
      final fresh = tester.widget<ReviewPage>(find.byType(ReviewPage));
      expect(fresh.evidence, isNot(same(evidence)));
      expect(fresh.evidence!.isDisposed, isFalse);
      expect(fresh.draft!.rows.single.name, 'MILK');
      expect(find.text('9,99'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('branch')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Kuittikuvaan verrattuja rivejä: 0/1.'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(fresh.evidence!.isDisposed, isTrue);
      expect(evidence.isDisposed, isFalse);
      expect(find.text('9,99'), findsOneWidget);
      expect(find.text('Original branch'), findsOneWidget);
      expect(original.rows, isEmpty);
      expect(original.parseContext!.itemTop, 3.25);
      expect(find.byKey(const Key('review-complete')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(evidence.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'geometry action highlights exact words and cannot dismiss warnings',
    (tester) async {
      final original = parseReceipt(page, itemTop: 3.25, priceColumnLeft: 5);
      await open(tester, original);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      final overlay =
          tester
                  .widget<CustomPaint>(find.byKey(const Key('layout-overlay')))
                  .painter!
              as ReceiptLayoutPainter;
      expect(overlay.highlights, [page.words[1], page.words[2]]);
      expect(overlay.highlights.first.box.top, 3);
      await tester.tap(find.text('Sulje'));
      await tester.pumpAndSettle();
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsNothing);
      expect(find.byKey(const Key('review-complete')), findsNothing);
    },
  );

  testWidgets('row comparison is explicit and resets after data edits', (
    tester,
  ) async {
    await open(tester, parseReceipt(page, itemTop: 2, priceColumnLeft: 5));
    await tester.scrollUntilVisible(
      find.byKey(const Key('row-image-compared-0')),
      150,
      scrollable: vertical,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('row-image-compared-0')));
    await tester.tap(find.byKey(const Key('row-image-compared-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('row-image-compared-0')),
          )
          .value,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const Key('row-name-0')));
    await tester.enterText(
      find.byKey(const Key('row-name-0')),
      'Corrected milk',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('row-image-compared-0')),
          )
          .value,
      isFalse,
    );
    expect(find.byKey(const Key('review-complete')), findsNothing);
  });

  testWidgets('layout inspector fits narrow screen with enlarged text', (
    tester,
  ) async {
    await open(tester, parseReceipt(page, itemTop: 2, priceColumnLeft: 5));
    await tester.tap(find.byKey(const Key('inspect-layout')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layout-overlay')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sulje'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
