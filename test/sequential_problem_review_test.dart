import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/finding_review.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import 'ocr_review_guidance_test.dart' show reveal;
import 'support/fake_store.dart';

Future<ReceiptDraft> _open(
  WidgetTester t,
  FakeStore store, {
  bool noisy = true,
  bool missing = false,
  bool boundary = false,
  bool normalizedItem = false,
}) async {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final evidence = (await t.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 600);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return ReceiptEvidence.decode(bytes!.buffer.asUint8List());
  }))!;
  addTearDown(evidence.dispose);
  OcrWord word(String text, double x, double y, double width) =>
      OcrWord(text, PixelBox(x, y, x + width, y + 16));
  final draft = parseReceipt(
    OcrPage(800, 600, [
      word(store.branch.name, 20, 20, 400),
      word('19.11.2026', 20, 60, 200),
      if (noisy) word('1 kpl 1,00 EUR/kpl', 20, 105, 350),
      word('TEST MILK', 20, 170, 200),
      word(normalizedItem ? '2, 00' : '2,00', 650, 170, 70),
      word('TEST BREAD', 20, 220, 200),
      word('3,00', 650, 220, 70),
      word('YHTEENSÄ', 20, 270, 200),
      word(
        boundary
            ? '5,00'
            : missing
            ? '6, 00'
            : noisy
            ? '5,00'
            : '5, 00',
        650,
        270,
        70,
      ),
      if (noisy || missing) ...[
        word('TEST', 20, 320, 50),
        word('FOOTER', 90, 320, 90),
        word('NOTE', 200, 320, 60),
      ],
      word('VISA', 20, 400, 100),
    ], baselineSlope: noisy ? .01 : 0),
    itemTop: boundary ? 180 : 90,
    priceColumnLeft: 600,
  );
  await t.pumpWidget(const ReceiptReaderApp());
  Navigator.of(t.element(find.text('Kokeile kuitin tarkistusta'))).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ReviewPage(draft: draft, evidence: evidence, store: store),
    ),
  );
  await t.pumpAndSettle();
  return draft;
}

Future<void> _tap(WidgetTester t, String key) async {
  await reveal(t, key);
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> _progress(WidgetTester t, int done, int total) async {
  await reveal(t, 'problem-progress');
  expect(find.text('Käsitelty $done/$total'), findsOneWidget);
}

Future<void> _save(WidgetTester t) async => _tap(t, 'ocr-save');
bool _canSave(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('ocr-save'))).onPressed != null;

void main() {
  test('groups source words on one printed line but retains original finding identities', () {
    final a = OcrWord('A', PixelBox(10, 10, 20, 26)),
        b = OcrWord('B', PixelBox(30, 10, 40, 26));
    final c = OcrWord('C', PixelBox(10, 50, 20, 66));
    final findings = [
      for (final w in [a, b, c])
        ParseFinding(
          ParseIssue.unassignedSource,
          scope: FindingScope.item,
          words: [w],
        ),
    ];
    final groups = groupReviewFindings(findings, OcrPage(100, 100, [a, b, c]));
    expect(groups.length, 2);
    expect(groups.first.indices, [0, 1]);
    expect(groups.first.finding.words, [a, b]);
    expect(findings.first.words, [a]);
  });
  runSequentialProblemReviewTests();
}

/// Synthetic geometry/pixels and fake persistence; portable native UI checks.
void runSequentialProblemReviewTests() {
  testWidgets(
    'ignore, categorize and accept move through the queue without comments',
    (t) async {
      final store = FakeStore();
      final draft = await _open(t, store);
      await _progress(t, 0, 3);
      await _tap(t, 'problem-dismiss');
      await _progress(t, 1, 3);
      expect(find.text('TEST FOOTER NOTE'), findsOneWidget);
      await _tap(t, 'problem-category-paymentOrTax');
      await _progress(t, 2, 3);
      await _tap(t, 'problem-accept');
      await _progress(t, 3, 3);
      expect(find.text('Valmis — tämä kohta on käsitelty'), findsOneWidget);
      expect(store.saved, isEmpty);
      await _tap(t, 'problem-finish');
      await _save(t);
      final saved = store.saved.single.document;
      expect(
        saved.snapshot.items.map((r) => r.name),
        draft.rows.map((r) => r.name),
      );
      expect(saved.snapshot.totalCents, BigInt.from(500));
      final review = saved.review as OcrReviewRecord;
      expect(
        review.decisions.any(
          (d) =>
              d.issue == ParseIssue.quantityWithoutProduct &&
              d.rowKind == RowEvidenceKind.explanatoryText,
        ),
        isTrue,
      );
      expect(
        review.decisions
            .where((d) => d.rowKind == RowEvidenceKind.paymentOrTax)
            .length,
        3,
      );
      expect(
        ReceiptDocumentCodec.decode(ReceiptDocumentCodec.encode(saved))
            .snapshot
            .totalCents,
        BigInt.from(500),
      );
    },
  );

  testWidgets(
    'Next does not silently dismiss problems and completed items stay inspectable',
    (t) async {
      final store = FakeStore();
      await _open(t, store);
      await _tap(t, 'problem-next');
      await _progress(t, 0, 3);
      await _tap(t, 'problem-category-explanatoryText');
      await _progress(t, 1, 3);
      await _tap(t, 'problem-next');
      expect(find.textContaining('Selittävä teksti'), findsOneWidget);
      expect(find.text('Valmis — tämä kohta on käsitelty'), findsOneWidget);
      await reveal(t, 'ocr-save');
      expect(_canSave(t), isFalse);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'unrelated edits retain text classifications while financial mismatches still block saving',
    (t) async {
      final store = FakeStore();
      await _open(t, store);
      await _tap(t, 'problem-dismiss');
      await _tap(t, 'problem-dismiss');
      await _progress(t, 2, 3);
      await _tap(t, 'problem-accept');
      await _progress(t, 3, 3);
      await reveal(t, 'row-name-0');
      await t.enterText(find.byKey(const Key('row-name-0')), 'Corrected milk');
      await t.pumpAndSettle();
      await _progress(t, 2, 3);
      await reveal(t, 'row-amount-0');
      await t.enterText(find.byKey(const Key('row-amount-0')), '2,01');
      await t.pumpAndSettle();
      await _progress(t, 2, 3);
      await reveal(t, 'ocr-save');
      expect(_canSave(t), isFalse);
    },
  );

  testWidgets('field approvals reopen only when their relevant values change', (
    t,
  ) async {
    await _open(t, FakeStore(), noisy: false);
    await _progress(t, 0, 1);
    await _tap(t, 'problem-accept');
    await _progress(t, 1, 1);
    await reveal(t, 'row-name-0');
    await t.enterText(find.byKey(const Key('row-name-0')), 'Corrected milk');
    await t.pumpAndSettle();
    await _progress(t, 1, 1);
    await reveal(t, 'total');
    await t.enterText(find.byKey(const Key('total')), '5,01');
    await t.pumpAndSettle();
    await _progress(t, 0, 1);
    await reveal(t, 'ocr-save');
    expect(_canSave(t), isFalse);
  });

  testWidgets(
    'a grouped missing row can be added once without notes or comparison checkboxes',
    (t) async {
      final store = FakeStore();
      await _open(t, store, noisy: false, missing: true);
      // First accept normalization of the printed total.
      await _tap(t, 'problem-accept');
      await _progress(t, 1, 2);
      final panel = t.widget<FindingReviewPanel>(
        find.byType(FindingReviewPanel),
      );
      await _tap(t, 'finding-${panel.group.indices.first}');
      await t.tap(find.byKey(const Key('row-evidence-kind')));
      await t.pumpAndSettle();
      await t.tap(find.text('Raharivi').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('row-evidence-create')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('row-evidence-name')),
        'TEST ADDED ITEM',
      );
      await t.enterText(find.byKey(const Key('row-evidence-amount')), '1,00');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('row-evidence-compared')), findsNothing);
      await t.tap(find.byKey(const Key('confirm-row-evidence')));
      await t.pumpAndSettle();
      await _progress(t, 2, 2);
      await _save(t);
      expect(store.saved.single.document.snapshot.items.length, 3);
      expect(store.saved.single.document.snapshot.totalCents, BigInt.from(600));
    },
  );

  testWidgets(
    'one-at-a-time review and optional comments fit a compact enlarged-text screen',
    (t) async {
      await _open(t, FakeStore());
      t.view.physicalSize = const Size(320, 960);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      await _tap(t, 'problem-dismiss');
      await _progress(t, 1, 3);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'linking quantity values reopens an earlier approval of that row',
    (t) async {
      final store = FakeStore();
      await _open(t, store, normalizedItem: true);
      await _tap(t, 'problem-next');
      await _tap(t, 'problem-accept');
      await _progress(t, 1, 4);
      await _tap(t, 'problem-previous');
      await _tap(t, 'problem-previous');
      final panel = t.widget<FindingReviewPanel>(
        find.byType(FindingReviewPanel),
      );
      expect(panel.group.finding.issue, ParseIssue.quantityWithoutProduct);
      await _tap(t, 'finding-${panel.group.indices.first}');
      final target = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField &&
            w.key.toString().contains('relationship-target'),
      );
      await t.tap(target);
      await t.pumpAndSettle();
      await t.tap(find.text('1. TEST MILK (2,00)').last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('relationship-quantity')), '2');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('relationship-compared')), findsNothing);
      await t.tap(find.byKey(const Key('confirm-relationship')));
      await t.pumpAndSettle();
      await _progress(t, 1, 4);
      expect(
        t
            .widget<FindingReviewPanel>(find.byType(FindingReviewPanel))
            .group
            .finding
            .issue,
        ParseIssue.normalizedOcrAmount,
      );
      await _tap(t, 'problem-accept');
      await _tap(t, 'problem-category-paymentOrTax');
      await _tap(t, 'problem-accept');
      await _progress(t, 4, 4);
      await _save(t);
      final document = store.saved.single.document;
      expect(document.snapshot.items.first.quantityValue, BigInt.from(2000000));
      expect(
        (document.review as OcrReviewRecord).decisions.any(
          (d) => d.relationshipKind == ReviewRelationshipKind.quantity,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'optional comments do not complete a problem or enter saved receipt data',
    (t) async {
      final store = FakeStore();
      await _open(t, store, noisy: false);
      await reveal(t, 'problem-progress');
      await t.tap(find.text('Lisää kommentti (vapaaehtoinen)'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('problem-note')),
        'PRIVATE REVIEW NOTE',
      );
      await _progress(t, 0, 1);
      await _tap(t, 'problem-accept');
      await _progress(t, 1, 1);
      await _save(t);
      expect(
        ReceiptDocumentCodec.encode(store.saved.single.document),
        isNot(contains('PRIVATE REVIEW NOTE')),
      );
    },
  );

  testWidgets(
    'a boundary warning can be accepted after every cut word is explicitly accounted for',
    (t) async {
      final store = FakeStore();
      await _open(t, store, noisy: false, boundary: true);
      await _progress(t, 0, 2);
      expect(find.byKey(const Key('problem-accept')), findsNothing);
      final panel = t.widget<FindingReviewPanel>(
        find.byType(FindingReviewPanel),
      );
      await _tap(t, 'finding-${panel.group.indices.first}');
      await t.tap(find.byKey(const Key('row-evidence-kind')));
      await t.pumpAndSettle();
      await t.tap(find.text('Raharivi').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('row-evidence-create')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('row-evidence-name')),
        'TEST MILK',
      );
      await t.enterText(find.byKey(const Key('row-evidence-amount')), '2,00');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-row-evidence')));
      await t.pumpAndSettle();
      await _progress(t, 1, 2);
      await _tap(t, 'problem-accept');
      await _progress(t, 2, 2);
      await _save(t);
      final document = store.saved.single.document;
      expect(document.snapshot.totalCents, BigInt.from(500));
      expect(document.snapshot.items.length, 2);
      expect(
        (document.review as OcrReviewRecord).decisions.any(
          (d) => d.geometryKind == GeometryFindingKind.sectionBoundary,
        ),
        isTrue,
      );
      expect(
        ReceiptDocumentCodec.decode(ReceiptDocumentCodec.encode(document))
            .snapshot
            .items
            .length,
        2,
      );
    },
  );
}
