import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import '../packages/receipt_parser/test/fixtures/finnish_receipts.dart';
import 'support/fake_store.dart';
import 'support/render_finnish_receipt.dart';

Future<void> reveal(WidgetTester t, String key) async {
  final scroll = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  final position = t.state<ScrollableState>(scroll).position;
  position.jumpTo(0);
  await t.pumpAndSettle();
  for (
    var i = 0;
    i < 120 && find.byKey(ValueKey(key)).evaluate().isEmpty;
    i++
  ) {
    position.jumpTo((position.pixels + 200).clamp(0, position.maxScrollExtent));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String key) async {
  await reveal(t, key);
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<FakeStore> open(WidgetTester t, String id) async {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final fixture = finnishReceiptFixtures.singleWhere((f) => f.id == id);
  final evidence = (await t.runAsync(
    () async => ReceiptEvidence.decode(await renderFinnishReceipt(fixture)),
  ))!;
  final draft = parseReceipt(
    fixture.page(),
    itemTop: 150,
    priceColumnLeft: 900,
  );
  final store = FakeStore();
  await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await t.pumpAndSettle();
  Navigator.of(t.element(find.byKey(const Key('open-history')))).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ReviewPage(draft: draft, evidence: evidence, store: store),
    ),
  );
  await t.pumpAndSettle();
  await tap(t, 'ocr-branch');
  await t.tap(find.text(store.branch.name).last);
  await t.pumpAndSettle();
  return store;
}

void main() {
  for (final id in [
    'euro_duplicates',
    'weighed_multiplication',
    'weighed_return',
  ]) {
    testWidgets('$id saves typed financial values through quick review', (
      t,
    ) async {
      final store = await open(t, id);
      final fixture = finnishReceiptFixtures.singleWhere((f) => f.id == id);
      await reveal(t, 'ocr-save');
      expect(
        t.widget<FilledButton>(find.byKey(const Key('ocr-save'))).onPressed,
        isNotNull,
      );
      await tap(t, 'ocr-save');
      final saved = store.saved.single.document;
      expect(saved.snapshot.totalCents, BigInt.from(fixture.total!));
      expect(saved.snapshot.items.map((r) => (r.name, r.cents, r.kind)), [
        for (final row in fixture.rows)
          (row.name, BigInt.from(row.cents), row.kind),
      ]);
      for (var i = 0; i < fixture.rows.length; i++) {
        final expected = fixture.rows[i], actual = saved.snapshot.items[i];
        expect(
          actual.quantityValue,
          expected.quantityMicros == null
              ? null
              : BigInt.from(expected.quantityMicros!),
        );
        expect(actual.quantityUnit, expected.unit);
        expect(
          actual.rateMicros,
          expected.rateMicros == null
              ? null
              : BigInt.from(expected.rateMicros!),
        );
      }
      expect(
        (saved.review as OcrReviewRecord).receiptReviewMethod,
        ReceiptReviewMethod.quick,
      );
      expect(find.byKey(const Key('ocr-confirm-save')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  for (final id in [
    'quantity_mismatch',
    'unknown_footer',
    'posted_discounts',
    'ocr_dash_sign',
    'quantity_decimal_whitespace',
  ]) {
    testWidgets(
      '$id cannot bypass required evidence review merely because totals match',
      (t) async {
        final store = await open(t, id);
        await reveal(t, 'ocr-save');
        expect(
          t.widget<FilledButton>(find.byKey(const Key('ocr-save'))).onPressed,
          isNull,
        );
        expect(
          find.byKey(const Key('ocr-blocker-openFindings')),
          findsOneWidget,
        );
        expect(store.saved, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('deposits still require explicit standalone or parent choices', (
    t,
  ) async {
    final store = await open(t, 'deposit_and_refund');
    await reveal(t, 'ocr-save');
    expect(
      t.widget<FilledButton>(find.byKey(const Key('ocr-save'))).onPressed,
      isNull,
    );
    for (final i in [1, 2]) {
      await tap(t, 'ocr-deposit-$i-null-false');
      await t.tap(find.text('Erillinen pantti tai pantin palautus').last);
      await t.pumpAndSettle();
    }
    await tap(t, 'ocr-save');
    final saved = store.saved.single.document.snapshot;
    expect(saved.totalCents, BigInt.from(114));
    expect(saved.items.map((r) => r.cents), [
      BigInt.from(119),
      BigInt.from(15),
      BigInt.from(-20),
    ]);
    expect(
      saved.items
          .skip(1)
          .every((r) => r.kind == LineKind.deposit && r.parentItemId == null),
      isTrue,
    );
    expect(t.takeException(), isNull);
  });
}
