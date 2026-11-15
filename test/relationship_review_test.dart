import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show DropdownButtonFormField, FilledButton, MaterialPageRoute, TextField;
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/relationship_dialog.dart';
import 'package:receipt_reader/review_page.dart';

void main() {
  final words = [OcrWord('SOURCE', PixelBox(1, 1, 6, 8))];
  final vertical = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;

  Future<void> visible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 180, scrollable: vertical);
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    ReceiptDraft draft, {
    bool withImage = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final evidence = withImage
        ? (await tester.runAsync(
            () async => ReceiptEvidence.decode(
              await File('test/fixtures/rotated.jpg').readAsBytes(),
            ),
          ))!
        : null;
    await tester.pumpWidget(const ReceiptReaderApp());
    Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(draft: draft, evidence: evidence),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> target(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<RelationshipTarget>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('relationship-note')),
      'Checked source and target',
    );
    await tester.tap(find.byKey(const Key('relationship-compared')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('confirm-relationship')));
    await tester.pumpAndSettle();
  }

  testWidgets('a relationship cannot be confirmed without the imported image', (
    tester,
  ) async {
    final draft = ReceiptDraft(
      [FinancialRow(name: 'MILK', cents: BigInt.from(200))],
      BigInt.from(200),
      [ParseIssue.quantityWithoutProduct],
      [],
      parseReceiptDate('15.11.2026'),
      [],
      findings: [
        ParseFinding(
          ParseIssue.quantityWithoutProduct,
          words: words,
          quantityCandidate: QuantityRateCandidate(
            Quantity(BigInt.from(2), 0, QuantityUnit.piece),
            BigInt.from(1000000),
          ),
        ),
      ],
    );
    await open(tester, draft, withImage: false);
    await tester.tap(find.byKey(const Key('finding-0')));
    await tester.pumpAndSettle();
    await target(tester, '1. MILK (2,00)');
    await tester.enterText(
      find.byKey(const Key('relationship-note')),
      'No image available',
    );
    await tester.tap(find.byKey(const Key('relationship-compared')));
    await tester.pumpAndSettle();
    expect(
      find.text('Ratkaisu edellyttää alkuperäistä kuittikuvaa.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'quantity replacement, cancellation and conflicting links require explicit decisions',
    (tester) async {
      final candidate = QuantityRateCandidate(
        Quantity(BigInt.from(5), 1, QuantityUnit.kg),
        BigInt.from(4000000),
      );
      final draft = ReceiptDraft(
        [
          FinancialRow(
            name: 'MILK',
            cents: BigInt.from(200),
            quantity: Quantity(BigInt.one, 0, QuantityUnit.piece),
            rateMicros: BigInt.from(2000000),
          ),
          FinancialRow(name: 'BREAD', cents: BigInt.from(200)),
        ],
        BigInt.from(400),
        [ParseIssue.quantityWithoutProduct],
        [],
        parseReceiptDate('15.11.2026'),
        [],
        findings: [
          for (var i = 0; i < 2; i++)
            ParseFinding(
              ParseIssue.quantityWithoutProduct,
              words: words,
              quantityCandidate: candidate,
            ),
        ],
      );
      await open(tester, draft);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await target(tester, '1. MILK (2,00)');
      await tester.enterText(
        find.byKey(const Key('relationship-note')),
        'Replace after comparison',
      );
      await tester.tap(find.byKey(const Key('relationship-compared')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Sulje'));
      await tester.pumpAndSettle();
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsNothing);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await target(tester, '1. MILK (2,00)');
      await tester.tap(find.byKey(const Key('relationship-replace')));
      await confirm(tester);
      await visible(tester, find.byKey(const Key('row-quantity-0')));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('row-quantity-0')))
            .controller!
            .text,
        '0,5',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('row-rate-0')))
            .controller!
            .text,
        '4',
      );
      expect(find.text('kg'), findsOneWidget);
      expect(draft.rows.first.quantity!.unit, QuantityUnit.piece);
      await tester.drag(vertical, const Offset(0, 2500));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const Key('finding-0')));
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await target(tester, '2. BREAD (2,00)');
      expect(
        find.textContaining('Poista ensin aiemman kohdetuotteen'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('relationship-compared')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Sulje'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finding-1')));
      await tester.pumpAndSettle();
      await target(tester, '1. MILK (2,00)');
      expect(
        find.textContaining('Tuotteelle on jo kohdistettu toinen'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('relationship-note')),
        'Second source',
      );
      await tester.tap(find.byKey(const Key('relationship-replace')));
      await tester.tap(find.byKey(const Key('relationship-compared')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('relationship dialog fits narrow screen with enlarged text', (
    tester,
  ) async {
    final draft = ReceiptDraft(
      [FinancialRow(name: 'MILK', cents: BigInt.from(200))],
      BigInt.from(200),
      [ParseIssue.quantityWithoutProduct],
      [],
      parseReceiptDate('15.11.2026'),
      [],
      findings: [ParseFinding(ParseIssue.quantityWithoutProduct, words: words)],
    );
    await open(tester, draft);
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await visible(tester, find.byKey(const Key('finding-0')));
    await tester.tap(find.byKey(const Key('finding-0')));
    await tester.pumpAndSettle();
    expect(find.byType(RelationshipDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sulje'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'orphan attachment survives position changes and cannot follow a deleted target',
    (tester) async {
      final draft = ReceiptDraft(
        [
          FinancialRow(name: 'FIRST', cents: BigInt.from(100)),
          FinancialRow(name: 'SECOND', cents: BigInt.from(200)),
        ],
        BigInt.from(300),
        [ParseIssue.quantityWithoutProduct],
        [],
        parseReceiptDate('15.11.2026'),
        [],
        findings: [
          ParseFinding(
            ParseIssue.quantityWithoutProduct,
            words: words,
            quantityCandidate: QuantityRateCandidate(
              Quantity(BigInt.from(2), 0, QuantityUnit.piece),
              BigInt.from(1000000),
            ),
          ),
        ],
      );
      await open(tester, draft);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await target(tester, '2. SECOND (2,00)');
      await confirm(tester);
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsOneWidget);
      expect(draft.rows.last.quantity, isNull);
      await visible(tester, find.byKey(const Key('remove-row-0')));
      await tester.tap(find.byKey(const Key('remove-row-0')));
      await tester.pumpAndSettle();
      await tester.drag(vertical, const Offset(0, 2200));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const Key('finding-0')));
      expect(find.text('Avoin tarkistuskohta'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      expect(find.text('1. SECOND (2,00)'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('relationship-quantity')))
            .controller!
            .text,
        '2',
      );
      await tester.tap(find.byKey(const Key('relationship-replace')));
      await confirm(tester);
      await visible(tester, find.byKey(const Key('remove-row-0')));
      await tester.tap(find.byKey(const Key('remove-row-0')));
      await tester.pumpAndSettle();
      await tester.drag(vertical, const Offset(0, 2200));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const Key('finding-0')));
      expect(
        find.text('Alkuperäinen riviehdotus on poistettu'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<RelationshipTarget>>(
              find.byType(DropdownButtonFormField<RelationshipTarget>),
            )
            .initialValue,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'price explanation and receipt discount resolve separately without changing amounts',
    (tester) async {
      final draft = ReceiptDraft(
        [
          FinancialRow(name: 'MILK', cents: BigInt.from(200)),
          FinancialRow(
            name: 'ALE',
            cents: BigInt.from(-50),
            kind: LineKind.discount,
          ),
        ],
        BigInt.from(150),
        [ParseIssue.discountNeedsReview],
        [],
        parseReceiptDate('15.11.2026'),
        [],
        findings: [
          ParseFinding(
            ParseIssue.discountNeedsReview,
            words: words,
            discountKind: DiscountFindingKind.explanatoryPrice,
          ),
          ParseFinding(
            ParseIssue.discountNeedsReview,
            rowIndex: 1,
            words: words,
            discountKind: DiscountFindingKind.postedDiscount,
          ),
        ],
      );
      await open(tester, draft);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await target(tester, '1. MILK (2,00)');
      await confirm(tester);
      await tester.tap(find.byKey(const Key('finding-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('relationship-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Koko kuitin alennus').last);
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsNWidgets(2));
      expect(find.text('1,50'), findsOneWidget);
      await visible(tester, find.byKey(const Key('row-amount-1')));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('row-amount-1')))
            .controller!
            .text,
        '-0,50',
      );
      await tester.enterText(find.byKey(const Key('row-amount-1')), '0,50');
      await tester.pumpAndSettle();
      await tester.drag(vertical, const Offset(0, 2500));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const Key('finding-1')));
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsNothing);
      await tester.tap(find.byKey(const Key('finding-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('relationship-compared')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-relationship')))
            .onPressed,
        isNull,
      );
      expect(draft.rows.last.cents, BigInt.from(-50));
      expect(tester.takeException(), isNull);
    },
  );
}
