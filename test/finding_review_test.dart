import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show FilledButton, MaterialPageRoute;
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

void main() {
  testWidgets(
    'individual resolution requires evidence and reopens after an edit',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final evidence = (await tester.runAsync(
        () async => ReceiptEvidence.decode(
          await File('test/fixtures/rotated.jpg').readAsBytes(),
        ),
      ))!;
      final words = [OcrWord('TEST', PixelBox(1, 1, 6, 8))];
      final draft = ReceiptDraft(
        [
          FinancialRow(name: 'FIRST', cents: BigInt.from(100)),
          FinancialRow(name: 'SECOND', cents: BigInt.from(200)),
        ],
        BigInt.from(300),
        [ParseIssue.normalizedOcrAmount],
        [],
        parseReceiptDate('15.11.2026'),
        [],
        findings: [
          ParseFinding(
            ParseIssue.normalizedOcrAmount,
            rowIndex: 0,
            words: words,
          ),
          ParseFinding(
            ParseIssue.normalizedOcrAmount,
            rowIndex: 1,
            words: words,
          ),
        ],
      );
      await tester.pumpWidget(const ReceiptReaderApp());
      Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta')))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ReviewPage(draft: draft, evidence: evidence),
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('resolve-finding')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('finding-note')),
        'Compared decimal separator with source',
      );
      await tester.tap(find.byKey(const Key('finding-compared')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resolve-finding')));
      await tester.pumpAndSettle();
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsOneWidget);
      expect(find.text('Avoin tarkistuskohta'), findsOneWidget);
      expect(draft.findings.length, 2);
      await tester.enterText(find.byKey(const Key('total')), '3,01');
      await tester.pumpAndSettle();
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsNothing);
      expect(find.text('Avoin tarkistuskohta'), findsNWidgets(2));
      expect(
        find.text('Compared decimal separator with source'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review-complete')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
