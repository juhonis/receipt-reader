import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/relationship_dialog.dart'
    show RelationshipTarget;
import 'package:receipt_reader/review_page.dart';

void main() {
  final vertical = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  ReceiptDraft draft({double slope = 0, bool overlap = false}) => parseReceipt(
    OcrPage(8, 12, [
      OcrWord('16.11.2026', PixelBox(.5, .5, 3, 1)),
      OcrWord('MILK', PixelBox(.5, 3, 3, 3.5)),
      if (overlap) OcrWord('MILK', PixelBox(.6, 3, 3.1, 3.5)),
      OcrWord('2,00', PixelBox(6, 3, 7.5, 3.5)),
      OcrWord('YHTEENSÄ', PixelBox(.5, 6, 3, 6.5)),
      OcrWord('2,00', PixelBox(6, 6, 7.5, 6.5)),
    ], baselineSlope: slope),
    itemTop: 2,
    priceColumnLeft: 5,
  );

  Future<void> visible(WidgetTester tester, Finder finder) async {
    tester.state<ScrollableState>(vertical).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 160, scrollable: vertical);
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, ReceiptDraft value) async {
    tester.view.physicalSize = const Size(1400, 2400);
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
        builder: (_) => ReviewPage(draft: value, evidence: evidence),
      ),
    );
    await tester.pumpAndSettle();
    await visible(tester, find.byKey(const Key('branch')));
    await tester.enterText(find.byKey(const Key('branch')), 'TEST BRANCH');
    await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
    await tester.pumpAndSettle();
  }

  Future<void> compareRow(WidgetTester tester) async {
    await visible(tester, find.byKey(const Key('row-image-compared-0')));
    await tester.tap(find.byKey(const Key('row-image-compared-0')));
    await tester.pumpAndSettle();
  }

  Future<void> pageChecks(WidgetTester tester) async {
    for (final key in [
      'page-header',
      'page-footer',
      'page-layout',
      'page-complete-image',
    ]) {
      await tester.tap(find.byKey(Key(key)));
    }
    await tester.enterText(
      find.byKey(const Key('page-evidence-note')),
      'Compared complete receipt and all fields',
    );
    await tester.pumpAndSettle();
  }

  Future<void> approvePage(WidgetTester tester) async {
    await visible(tester, find.byKey(const Key('review-page-evidence')));
    await tester.tap(find.byKey(const Key('review-page-evidence')));
    await tester.pumpAndSettle();
    await pageChecks(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('approve-page-evidence')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('approve-page-evidence')));
    await tester.pumpAndSettle();
  }

  Future<void> geometry(WidgetTester tester, int index) async {
    await visible(tester, find.byKey(ValueKey('geometry-review-$index')));
    await tester.tap(find.byKey(ValueKey('geometry-review-$index')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('geometry-evidence-note')),
      'Checked corrected associations and skew against source',
    );
    await tester.tap(find.byKey(const Key('geometry-evidence-compared')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'supported OCR review completes only after row/page/final confirmation and reopens on edit',
    (tester) async {
      await open(tester, draft());
      await visible(tester, find.byKey(const Key('review-page-evidence')));
      await tester.tap(find.byKey(const Key('review-page-evidence')));
      await tester.pumpAndSettle();
      await pageChecks(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('approve-page-evidence')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Sulje'));
      await tester.pumpAndSettle();
      await compareRow(tester);
      await approvePage(tester);
      expect(find.byKey(const Key('evidence-audit-ready')), findsOneWidget);
      expect(find.byKey(const Key('review-complete')), findsNothing);
      await tester.tap(find.byKey(const Key('review-confirmation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-complete')), findsOneWidget);
      expect(
        find.textContaining('Tietoja ei ole tallennettu.'),
        findsOneWidget,
      );
      await visible(tester, find.byKey(const Key('total')));
      await tester.enterText(find.byKey(const Key('total')), '2,01');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-complete')), findsNothing);
      await visible(tester, find.byKey(const Key('review-confirmation')));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('review-confirmation')),
            )
            .onChanged,
        isNull,
      );
      expect(find.byKey(const Key('evidence-audit-ready')), findsNothing);
    },
  );

  testWidgets(
    'skew requires page approval and explicit geometry decision; unchecking row reopens it',
    (tester) async {
      await open(tester, draft(slope: .01));
      await geometry(tester, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-geometry-evidence')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Sulje'));
      await tester.pumpAndSettle();
      await compareRow(tester);
      await approvePage(tester);
      expect(find.byKey(const Key('evidence-audit-ready')), findsNothing);
      await geometry(tester, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-geometry-evidence')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('confirm-geometry-evidence')));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const Key('review-confirmation')));
      await tester.tap(find.byKey(const Key('review-confirmation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-complete')), findsOneWidget);
      await compareRow(tester);
      await visible(tester, find.byKey(const Key('geometry-review-0')));
      expect(find.text('Käsitelty tässä tarkistuksessa'), findsNothing);
      expect(find.byKey(const Key('review-complete')), findsNothing);
    },
  );

  testWidgets(
    'overlap is resolved through separate word decisions and explicit geometry approval',
    (tester) async {
      final value = draft(overlap: true);
      await open(tester, value);
      await visible(tester, find.byKey(const Key('row-name-0')));
      await tester.enterText(find.byKey(const Key('row-name-0')), 'MILK');
      await tester.pumpAndSettle();
      final findings = reviewFindingsForDraft(value);
      for (var i = 0; i < findings.length; i++) {
        if (findings[i].issue != ParseIssue.geometrySource) continue;
        await visible(tester, find.byKey(ValueKey('finding-$i')));
        await tester.tap(find.byKey(ValueKey('finding-$i')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-evidence-kind')));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(
                i == 2 ? 'Saman tiedon ylimääräinen OCR-tunnistus' : 'Raharivi',
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byType(DropdownButtonFormField<RelationshipTarget>),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('1. MILK (2,00)').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('row-evidence-note')),
          'Compared this word with corrected row',
        );
        await tester.tap(find.byKey(const Key('row-evidence-compared')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-row-evidence')));
        await tester.pumpAndSettle();
      }
      await compareRow(tester);
      await approvePage(tester);
      await geometry(tester, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-geometry-evidence')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('confirm-geometry-evidence')));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const Key('review-confirmation')));
      await tester.tap(find.byKey(const Key('review-confirmation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-complete')), findsOneWidget);
      expect(value.rows.single.name, 'MILK MILK');
    },
  );

  testWidgets('whole-page evidence dialog fits enlarged narrow layout', (
    tester,
  ) async {
    await open(tester, draft());
    await visible(tester, find.byKey(const Key('review-page-evidence')));
    await tester.tap(find.byKey(const Key('review-page-evidence')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve-page-evidence')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sulje'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
