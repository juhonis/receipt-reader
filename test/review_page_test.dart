import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart'
    show BackButton, MaterialPageRoute;
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/review_page.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';

void main() {
  testWidgets('quantity corrections preserve posted amount and row source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = ReceiptDraft(
      [
        FinancialRow(
          name: 'MILK',
          cents: BigInt.from(200),
          quantity: Quantity(BigInt.from(2), 0, QuantityUnit.piece),
          rateMicros: BigInt.from(1000000),
        ),
      ],
      BigInt.from(200),
      [],
      [],
      parseReceiptDate('15.11.2026'),
      [],
      rowEvidence: [
        [OcrWord('ORIGINAL MILK', PixelBox(1, 1, 6, 8))],
      ],
    );
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
    final vertical = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('row-quantity-0')),
      200,
      scrollable: vertical,
    );
    expect(find.text('2'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('row-quantity-0')), '3');
    await tester.pumpAndSettle();
    expect(find.textContaining('ei vastaa rivisummaa'), findsOneWidget);
    expect(draft.rows.single.quantity!.value, BigInt.from(2));
    expect(draft.rows.single.cents, BigInt.from(200));
    await tester.scrollUntilVisible(
      find.byKey(const Key('row-evidence-0')),
      150,
      scrollable: vertical,
    );
    await tester.tap(find.byKey(const Key('row-evidence-0')));
    await tester.pumpAndSettle();
    expect(find.text('ORIGINAL MILK'), findsOneWidget);
    expect(find.byKey(const Key('row-evidence-crop')), findsOneWidget);
    await tester.tap(find.text('Sulje'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'OCR name proposal changes only the name and keeps review gated',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = ReceiptDraft(
        [FinancialRow(name: 'CONTINUED', cents: BigInt.from(123))],
        BigInt.from(123),
        [ParseIssue.wrappedNameNeedsReview],
        ['LONG NAME'],
        parseReceiptDate('15.11.2026'),
        [const WrappedNameCandidate(0, 'LONG NAME CONTINUED')],
      );
      await tester.pumpWidget(const ReceiptReaderApp());
      Navigator.of(
        tester.element(find.text('Kokeile kuitin tarkistusta')),
      ).push(MaterialPageRoute<void>(builder: (_) => ReviewPage(draft: draft)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr-draft-blocked')), findsOneWidget);
      await tester.tap(find.text('Käytä nimiehdotusta'));
      await tester.pumpAndSettle();
      expect(find.text('LONG NAME CONTINUED'), findsOneWidget);
      expect(draft.rows.single.name, 'CONTINUED');
      expect(draft.rows.single.cents, BigInt.from(123));
      await tester.enterText(find.byKey(const Key('branch')), 'TEST BRANCH');
      await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-confirmation')),
        200,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await tester.tap(find.byKey(const Key('review-confirmation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-complete')), findsNothing);
      expect(find.text('LONG NAME'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  testWidgets('manual corrections reset review and leaving discards inputs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ReceiptReaderApp());
    await tester.tap(find.text('Kokeile kuitin tarkistusta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('branch')),
      'Testimyymälä Keskusta',
    );
    await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
    await tester.enterText(find.byKey(const Key('date')), '15.11.2026');
    await tester.enterText(find.byKey(const Key('total')), '1,00');
    await tester.enterText(find.byKey(const Key('row-name-0')), 'TESTITUOTE');
    await tester.enterText(find.byKey(const Key('row-amount-0')), '1,00');
    await tester.scrollUntilVisible(
      find.byKey(const Key('review-confirmation')),
      200,
      scrollable: vertical,
    );
    await tester.tap(find.byKey(const Key('review-confirmation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-complete')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('row-amount-0')));
    await tester.enterText(find.byKey(const Key('row-amount-0')), '0,99');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-complete')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kokeile kuitin tarkistusta'));
    await tester.pumpAndSettle();
    expect(find.text('Testimyymälä Keskusta'), findsNothing);
    expect(find.text('TESTITUOTE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review supports adding and removing rows on narrow enlarged UI',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const ReceiptReaderApp());
      await tester.ensureVisible(find.text('Kokeile kuitin tarkistusta'));
      await tester.tap(find.text('Kokeile kuitin tarkistusta'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Lisää rivi'),
        200,
        scrollable: vertical,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lisää rivi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lisää rivi'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('row-name-1')),
        150,
        scrollable: vertical,
      );
      expect(find.byKey(const Key('row-name-1')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Poista rivi').last,
        150,
        scrollable: vertical,
      );
      await tester.tap(find.text('Poista rivi').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row-name-1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
