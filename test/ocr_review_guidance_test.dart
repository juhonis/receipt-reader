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

bool finalEnabled(WidgetTester t) =>
    t
        .widget<CheckboxListTile>(find.byKey(const Key('review-confirmation')))
        .onChanged !=
    null;

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

Future<void> compareRows(WidgetTester t) async {
  for (var i = 0; i < 2; i++) {
    await tap(t, 'row-image-compared-$i');
  }
}

Future<void> pageChecks(WidgetTester t) async {
  for (final key in [
    'page-header',
    'page-footer',
    'page-layout',
    'page-complete-image',
  ]) {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }
}

Future<void> approvePage(WidgetTester t) async {
  await tap(t, 'review-page-evidence');
  await pageChecks(t);
  await t.ensureVisible(find.byKey(const Key('page-evidence-note')));
  await t.enterText(
    find.byKey(const Key('page-evidence-note')),
    'Compared synthetic receipt',
  );
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('approve-page-evidence')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'fresh installation names its first branch and completes all explicit checks before saving',
    (t) async {
      final store = FreshStore();
      await open(t, store);
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
      await tap(t, 'ocr-branch-confirmation');
      await reveal(t, 'review-confirmation');
      expect(finalEnabled(t), isFalse);
      expect(find.byKey(const Key('ocr-blocker-rowReview')), findsOneWidget);
      await compareRows(t);
      await reveal(t, 'review-confirmation');
      expect(finalEnabled(t), isFalse);
      expect(find.byKey(const Key('ocr-blocker-rowReview')), findsNothing);
      expect(find.byKey(const Key('ocr-blocker-pageReview')), findsOneWidget);
      await tap(t, 'review-page-evidence');
      await pageChecks(t);
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('approve-page-evidence')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('page-note-required')), findsOneWidget);
      expect(find.text('Tarkistusmuistiinpano (pakollinen)'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('page-evidence-note')));
      await t.enterText(
        find.byKey(const Key('page-evidence-note')),
        'Compared source image',
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('approve-page-evidence')),
            )
            .onPressed,
        isNotNull,
      );
      await t.tap(find.byKey(const Key('approve-page-evidence')));
      await t.pumpAndSettle();
      await reveal(t, 'review-confirmation');
      expect(finalEnabled(t), isTrue);
      expect(find.byKey(const Key('ocr-final-review-pending')), findsNothing);
      expect(store.saved, isEmpty);
      await tap(t, 'review-confirmation');
      await tap(t, 'ocr-save');
      for (final key in ['ocr-save-date', 'ocr-save-total']) {
        await t.tap(find.byKey(ValueKey(key)));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const Key('ocr-confirm-save')));
      await t.pumpAndSettle();
      expect(store.saved, hasLength(1));
      final receipt = store.saved.single.document.snapshot;
      expect(receipt.branch.name, 'SYNTHETIC TEST STORE');
      expect(receipt.totalCents, BigInt.from(500));
      expect(receipt.items.map((r) => r.name), ['MILK', 'BREAD']);
    },
  );
  testWidgets(
    'existing branches require an explicit choice and later edits reopen review with reasons',
    (t) async {
      final store = FakeStore();
      await open(t, store);
      await reveal(t, 'branch');
      expect(
        t.widget<TextField>(find.byKey(const Key('branch'))).enabled,
        isFalse,
      );
      await tap(t, 'ocr-branch');
      await t.tap(find.text(store.branch.name).last);
      await t.pumpAndSettle();
      await tap(t, 'ocr-branch-confirmation');
      await compareRows(t);
      await approvePage(t);
      await reveal(t, 'review-confirmation');
      expect(finalEnabled(t), isTrue);
      await reveal(t, 'date');
      await t.enterText(find.byKey(const Key('date')), '19.11.2026');
      await t.pumpAndSettle();
      await reveal(t, 'review-confirmation');
      expect(finalEnabled(t), isFalse);
      expect(find.byKey(const Key('ocr-final-review-pending')), findsOneWidget);
      expect(find.byKey(const Key('ocr-blocker-rowReview')), findsOneWidget);
      expect(find.byKey(const Key('ocr-blocker-pageReview')), findsOneWidget);
      expect(store.saved, isEmpty);
    },
  );
  testWidgets(
    'pending review instructions and required note fit narrow enlarged-text screens',
    (t) async {
      await open(t, FreshStore(), compact: true);
      await reveal(t, 'review-confirmation');
      expect(finalEnabled(t), isFalse);
      expect(t.takeException(), isNull);
      await tap(t, 'review-page-evidence');
      await pageChecks(t);
      await t.ensureVisible(find.byKey(const Key('page-evidence-note')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('page-note-required')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
