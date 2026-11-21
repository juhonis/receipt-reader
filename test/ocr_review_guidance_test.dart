import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import 'support/fake_store.dart';

class FreshStore extends FakeStore {
  @override
  Future<List<ReceiptBranch>> branches() async => [];
}

Future<void> reveal(WidgetTester t, String key) async {
  final list = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  final position = t.state<ScrollableState>(list).position;
  position.jumpTo(0);
  await t.pumpAndSettle();
  final target = find.byKey(ValueKey(key));
  for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
    position.jumpTo((position.pixels + 200).clamp(0, position.maxScrollExtent));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String key) async {
  await reveal(t, key);
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> open(
  WidgetTester t,
  FakeStore store, {
  bool compact = false,
}) async {
  t.view.physicalSize = compact ? const Size(320, 960) : const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  if (compact) {
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final data = jsonDecode(
    File('test/fixtures/synthetic_receipt_ocr.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final page = OcrPage(data['width'] as int, data['height'] as int, [
    for (final item in data['words'] as List)
      OcrWord(
        item['text'] as String,
        PixelBox(
          (item['left'] as num).toDouble(),
          (item['top'] as num).toDouble(),
          (item['right'] as num).toDouble(),
          (item['bottom'] as num).toDouble(),
        ),
      ),
  ]);
  final layout = proposeLayout(page);
  expect(layout.available, isTrue);
  final draft = parseReceipt(
    page,
    itemTop: layout.itemTop!,
    priceColumnLeft: layout.priceColumnLeft!,
  );
  expect(draft.rows.map((r) => r.cents), [BigInt.from(200), BigInt.from(300)]);
  final png = File('test/fixtures/synthetic_receipt.png').readAsBytesSync();
  expect(sha256.convert(png).toString(), data['sourceSha256']);
  final image = (await t.runAsync(() => ReceiptEvidence.decode(png)))!;
  await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await t.pumpAndSettle();
  Navigator.of(t.element(find.byKey(const Key('open-history')))).push(
    MaterialPageRoute<void>(
      builder: (_) => ReviewPage(draft: draft, evidence: image, store: store),
    ),
  );
  await t.pumpAndSettle();
}

bool saveEnabled(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('ocr-save'))).onPressed != null;

Future<void> chooseBranch(WidgetTester t, FakeStore store) async {
  await tap(t, 'ocr-branch');
  await t.tap(find.text(store.branch.name).last);
  await t.pumpAndSettle();
}

Future<void> guidedReview(WidgetTester t) async {
  await tap(t, 'review-page-evidence');
  expect(find.byKey(const Key('page-evidence-note')), findsNothing);
  expect(
    t
        .widget<FilledButton>(find.byKey(const Key('approve-page-evidence')))
        .onPressed,
    isNull,
  );
  for (final key in [
    'page-header',
    'page-footer',
    'page-layout',
    'page-complete-image',
  ]) {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }
  expect(
    t
        .widget<FilledButton>(find.byKey(const Key('approve-page-evidence')))
        .onPressed,
    isNotNull,
  );
  await t.ensureVisible(find.byKey(const Key('approve-page-evidence')));
  await t.tap(find.byKey(const Key('approve-page-evidence')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'fresh installation saves exact shipped sample with one final action',
    (t) async {
      final store = FreshStore();
      await open(t, store);
      await reveal(t, 'ocr-save');
      expect(saveEnabled(t), isFalse);
      await reveal(t, 'branch');
      expect(
        t.widget<TextField>(find.byKey(const Key('branch'))).enabled,
        isTrue,
      );
      await t.enterText(
        find.byKey(const Key('branch')),
        'SYNTHETIC TEST STORE',
      );
      await t.pumpAndSettle();
      await reveal(t, 'ocr-save');
      expect(saveEnabled(t), isTrue);
      expect(find.byKey(const Key('review-confirmation')), findsNothing);
      expect(find.byKey(const Key('ocr-branch-confirmation')), findsNothing);
      expect(find.text('Automaattiset tarkistukset läpäisty'), findsOneWidget);
      await tap(t, 'ocr-save');
      expect(find.byKey(const Key('ocr-confirm-save')), findsNothing);
      final document = store.saved.single.document;
      expect(document.snapshot.branch.name, 'SYNTHETIC TEST STORE');
      expect(document.snapshot.totalCents, BigInt.from(500));
      expect(document.snapshot.items.map((r) => r.name), ['MILK', 'BREAD']);
      expect(document.review.policyVersion, 3);
      expect(
        (document.review as OcrReviewRecord).receiptReviewMethod,
        ReceiptReviewMethod.quick,
      );
    },
  );

  testWidgets('existing branches require selection but no separate checkbox', (
    t,
  ) async {
    final store = FakeStore();
    await open(t, store);
    await reveal(t, 'ocr-save');
    expect(saveEnabled(t), isFalse);
    await chooseBranch(t, store);
    await reveal(t, 'ocr-save');
    expect(saveEnabled(t), isTrue);
    await tap(t, 'ocr-save');
    expect(store.saved.single.document.snapshot.branch.id, store.branch.id);
  });

  testWidgets(
    'optional guided review needs four checks, no note, and survives subsequent edits',
    (t) async {
      final store = FakeStore();
      await open(t, store);
      await chooseBranch(t, store);
      await guidedReview(t);
      expect(store.saved, isEmpty);
      await reveal(t, 'row-name-0');
      await t.enterText(find.byKey(const Key('row-name-0')), 'Corrected milk');
      await t.pumpAndSettle();
      await reveal(t, 'date');
      await t.enterText(find.byKey(const Key('date')), '19.11.2026');
      await t.pumpAndSettle();
      await reveal(t, 'ocr-save');
      expect(find.byKey(const Key('ocr-guided-completed')), findsOneWidget);
      expect(saveEnabled(t), isTrue);
      await tap(t, 'ocr-save');
      final document = store.saved.single.document;
      expect(document.snapshot.items.first.name, 'Corrected milk');
      expect(document.snapshot.date.day, 19);
      expect(
        (document.review as OcrReviewRecord).receiptReviewMethod,
        ReceiptReviewMethod.guided,
      );
    },
  );

  testWidgets(
    'closing optional checklist neither saves nor prevents quick save',
    (t) async {
      final store = FakeStore();
      await open(t, store);
      await chooseBranch(t, store);
      await tap(t, 'review-page-evidence');
      await t.tap(find.text('Sulje'));
      await t.pumpAndSettle();
      expect(store.saved, isEmpty);
      await tap(t, 'ocr-save');
      expect(
        (store.saved.single.document.review as OcrReviewRecord)
            .receiptReviewMethod,
        ReceiptReviewMethod.quick,
      );
    },
  );

  testWidgets(
    'guided checklist cannot bypass mismatched totals or invalid dates',
    (t) async {
      final store = FakeStore();
      await open(t, store);
      await chooseBranch(t, store);
      await reveal(t, 'total');
      await t.enterText(find.byKey(const Key('total')), '5,01');
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('total')))
            .decoration!
            .errorText,
        isNotNull,
      );
      await guidedReview(t);
      await reveal(t, 'ocr-save');
      expect(saveEnabled(t), isFalse);
      await tap(t, 'ocr-jump-total');
      expect(find.byKey(const Key('total')).hitTestable(), findsOneWidget);
      await t.enterText(find.byKey(const Key('total')), '5,00');
      await reveal(t, 'date');
      await t.enterText(find.byKey(const Key('date')), '31.02.2026');
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('date')))
            .decoration!
            .errorText,
        isNotNull,
      );
      await reveal(t, 'ocr-save');
      expect(saveEnabled(t), isFalse);
      expect(store.saved, isEmpty);
      await tap(t, 'ocr-jump-date');
      expect(find.byKey(const Key('date')).hitTestable(), findsOneWidget);
      await t.enterText(find.byKey(const Key('date')), '18.11.2026');
      await tap(t, 'ocr-save');
      expect(store.saved, hasLength(1));
    },
  );

  testWidgets(
    'quick review and optional checklist fit narrow enlarged-text screens',
    (t) async {
      await open(t, FreshStore(), compact: true);
      await reveal(t, 'ocr-save');
      expect(saveEnabled(t), isFalse);
      expect(t.takeException(), isNull);
      await guidedReview(t);
      expect(t.takeException(), isNull);
      await reveal(t, 'ocr-save');
      expect(saveEnabled(t), isFalse);
    },
  );
}
