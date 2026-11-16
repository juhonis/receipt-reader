import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/relationship_dialog.dart'
    show RelationshipTarget;
import 'package:receipt_reader/review_page.dart';
import 'package:receipt_reader/row_evidence_dialog.dart';

void main() {
  final source = [OcrWord('UNPARSED SOURCE', PixelBox(1, 1, 6, 8))];
  final vertical = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  ReceiptDraft draft({
    List<FinancialRow> rows = const [],
    ParseFinding? finding,
  }) => ReceiptDraft(
    rows,
    BigInt.from(200),
    [finding?.issue ?? ParseIssue.invalidAmount],
    [],
    parseReceiptDate('15.11.2026'),
    [],
    findings: [
      finding ??
          ParseFinding(
            ParseIssue.invalidAmount,
            scope: FindingScope.item,
            words: source,
          ),
    ],
  );

  Future<void> open(
    WidgetTester tester,
    ReceiptDraft value, {
    bool image = true,
    bool review = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final evidence = image
        ? (await tester.runAsync(
            () async => ReceiptEvidence.decode(
              await File('test/fixtures/rotated.jpg').readAsBytes(),
            ),
          ))!
        : null;
    await tester.pumpWidget(const ReceiptReaderApp());
    Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewPage(draft: value, evidence: evidence),
      ),
    );
    await tester.pumpAndSettle();
    if (review) {
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> action(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('row-evidence-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-row-evidence')))
          .onPressed !=
      null;

  Future<void> compare(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('row-evidence-note')),
      'Transcribed and compared with source',
    );
    await tester.tap(find.byKey(const Key('row-evidence-compared')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cancel creates nothing and confirmed missing row is added exactly once',
    (tester) async {
      final original = draft();
      await open(tester, original);
      await action(tester, 'Raharivi');
      await tester.tap(find.byKey(const Key('row-evidence-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('row-evidence-name')),
        'MILK',
      );
      await tester.enterText(
        find.byKey(const Key('row-evidence-amount')),
        'I,00',
      );
      await compare(tester);
      expect(enabled(tester), isFalse);
      await tester.tap(find.text('Sulje'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row-name-0')), findsNothing);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await action(tester, 'Raharivi');
      await tester.tap(find.byKey(const Key('row-evidence-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('row-evidence-name')),
        'MILK',
      );
      await tester.enterText(
        find.byKey(const Key('row-evidence-amount')),
        '2,00',
      );
      await compare(tester);
      expect(enabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('confirm-row-evidence')));
      await tester.pumpAndSettle();
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsOneWidget);
      expect(find.byKey(const Key('row-name-0')), findsOneWidget);
      expect(find.byKey(const Key('row-name-1')), findsNothing);
      expect(original.rows, isEmpty);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      expect(find.text('1. MILK (2,00)'), findsOneWidget);
      await compare(tester);
      await tester.tap(find.byKey(const Key('confirm-row-evidence')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row-name-1')), findsNothing);
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await action(tester, 'Selittävä teksti');
      expect(
        find.textContaining('Tästä tekstistä lisätty raharivi on yhä mukana'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('row-evidence-non-financial')));
      await compare(tester);
      expect(enabled(tester), isFalse);
      expect(find.byKey(const Key('review-complete')), findsNothing);
    },
  );

  for (final image in [true, false]) {
    testWidgets(
      'nonfinancial classification requires explicit choice and image=$image',
      (tester) async {
        await open(tester, draft(), image: image);
        await action(tester, 'Maksu- tai verotieto');
        await compare(tester);
        expect(enabled(tester), isFalse);
        await tester.tap(find.byKey(const Key('row-evidence-non-financial')));
        await tester.pumpAndSettle();
        expect(enabled(tester), image);
        if (image) {
          await tester.tap(find.byKey(const Key('confirm-row-evidence')));
          await tester.pumpAndSettle();
          expect(find.text('Käsitelty tässä tarkistuksessa'), findsOneWidget);
          expect(find.byKey(const Key('row-name-0')), findsNothing);
          expect(find.text('2,00'), findsOneWidget); // Printed total unchanged.
        }
      },
    );
  }

  testWidgets(
    'description link preserves values and reopens when target is removed',
    (tester) async {
      await open(
        tester,
        draft(
          rows: [FinancialRow(name: 'MILK', cents: BigInt.from(200))],
          finding: ParseFinding(
            ParseIssue.unclassifiedRow,
            scope: FindingScope.item,
            words: source,
          ),
        ),
      );
      await action(tester, 'Tuotteen kuvauksen jatko');
      await tester.tap(
        find.byType(DropdownButtonFormField<RelationshipTarget>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. MILK (2,00)').last);
      await tester.pumpAndSettle();
      await compare(tester);
      await tester.tap(find.byKey(const Key('confirm-row-evidence')));
      await tester.pumpAndSettle();
      expect(find.text('MILK'), findsNWidgets(2)); // Summary and editable name.
      await tester.scrollUntilVisible(
        find.byKey(const Key('remove-row-0')),
        180,
        scrollable: vertical,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('remove-row-0')));
      await tester.tap(find.byKey(const Key('remove-row-0')));
      await tester.pumpAndSettle();
      await tester.drag(vertical, const Offset(0, 2500));
      await tester.pumpAndSettle();
      expect(find.text('Avoin tarkistuskohta'), findsOneWidget);
      expect(
        find.text('Alkuperäinen riviehdotus on poistettu'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('finding-0')));
      await tester.pumpAndSettle();
      await compare(tester);
      expect(enabled(tester), isFalse);
    },
  );

  testWidgets('invalid total uses total review and edits reopen it', (
    tester,
  ) async {
    await open(
      tester,
      draft(
        finding: ParseFinding(
          ParseIssue.invalidAmount,
          scope: FindingScope.total,
          words: source,
        ),
      ),
    );
    expect(find.byType(RowEvidenceDialog), findsNothing);
    await tester.enterText(
      find.byKey(const Key('finding-note')),
      'Checked printed total',
    );
    await tester.tap(find.byKey(const Key('finding-compared')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('resolve-finding')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('resolve-finding')));
    await tester.pumpAndSettle();
    expect(find.text('Käsitelty tässä tarkistuksessa'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('total')), '2,01');
    await tester.pumpAndSettle();
    expect(find.text('Avoin tarkistuskohta'), findsOneWidget);
    expect(find.byKey(const Key('review-complete')), findsNothing);
  });

  testWidgets(
    'coverage inventory exposes unassigned words and their image evidence',
    (tester) async {
      final value = ReceiptDraft(
        [],
        BigInt.from(200),
        [],
        [],
        parseReceiptDate('15.11.2026'),
        [],
        evidenceCoverage: ReceiptEvidenceCoverage(
          sourceWords: source,
          header: [],
          rows: [],
          findings: [],
          totals: [],
          footer: [],
        ),
      );
      await open(tester, value, review: false);
      expect(
        find.textContaining('Käsittelyn ulkopuolelle jääneitä: 1.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('evidence-coverage')));
      await tester.pumpAndSettle();
      expect(find.text('UNPARSED SOURCE'), findsOneWidget);
      await tester.tap(
        find.text('Näytä käsittelyn ulkopuolelle jäänyt teksti'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row-evidence-crop')), findsOneWidget);
      expect(find.byKey(const Key('review-complete')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unparsed row dialog fits enlarged narrow layout', (
    tester,
  ) async {
    await open(tester, draft());
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.byType(RowEvidenceDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sulje'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
