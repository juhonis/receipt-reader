import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  final store = DurableId.generate(),
      product = DurableId.generate(),
      origin = DurableId.generate();
  ProductPurchase purchase({
    String date = '1.11.2026',
    int revision = 1,
    QuantityUnit unit = QuantityUnit.kg,
    int scale = 0,
    BigInt? quantity,
    int rate = 1000000,
    int discount = 0,
    bool quantified = true,
    int? cents,
    bool extras = false,
  }) {
    final q = quantity ?? BigInt.one;
    final amount = cents == null
        ? extendedCents(Quantity(q, scale, unit), BigInt.from(rate))
        : BigInt.from(cents);
    final row = ReceiptItemSnapshot(
      id: DurableId.generate(),
      name: 'SYNTHETIC',
      kind: LineKind.product,
      cents: amount,
      product: ReceiptProductLink(
        id: product,
        storeId: store,
        revision: RevisionId(origin, BigInt.from(revision)),
      ),
      quantityValue: quantified ? q : null,
      quantityScale: quantified ? scale : null,
      quantityUnit: quantified ? unit : null,
      rateMicros: quantified ? BigInt.from(rate) : null,
    );
    final rows = [
      row,
      if (discount < 0)
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'DISCOUNT',
          kind: LineKind.discount,
          cents: BigInt.from(discount),
          parentItemId: row.id,
          discountScope: DiscountScope.item,
        ),
      if (extras) ...[
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(40),
          parentItemId: row.id,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'RECEIPT DISCOUNT',
          kind: LineKind.discount,
          cents: BigInt.from(-20),
          discountScope: DiscountScope.receipt,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'ADJUSTMENT',
          kind: LineKind.adjustment,
          cents: BigInt.one,
          adjustmentReason: 'SYNTHETIC CHECKED',
        ),
      ],
    ];
    return ProductPurchase.fromReceipt(
      ReceiptSnapshot(
        id: DurableId.generate(),
        branch: ReceiptBranch(id: store, name: 'SYNTHETIC'),
        date: StoredReceiptDate.parse(date),
        totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
        items: rows,
      ),
      row.id,
    );
  }

  PurchaseSummary summary(
    List<ProductPurchase> purchases, {
    String from = '1.11.2026',
    String through = '3.11.2026',
  }) {
    final b = PurchaseSummaryBuilder(
      storeId: store,
      productId: product,
      firstDay: purchaseCalendarDay(StoredReceiptDate.parse(from)),
      lastDay: purchaseCalendarDay(StoredReceiptDate.parse(through)),
    );
    for (final p in purchases) {
      b.add(p);
    }
    return b.finish();
  }

  test(
    'weighted means use purchased quantity, not an average of row prices',
    () {
      final g = summary([
        purchase(),
        purchase(quantity: BigInt.from(3), rate: 3000000),
      ]).groups.single;
      expect(g.weightedMean.euros, '2,5000');
      expect(g.buckets.single.weightedMean.euros, '2,5000');
      expect(g.minimum.euros, '1,0000');
      expect(g.maximum.euros, '3,0000');
    },
  );
  test('mixed fixed quantity scales combine exactly in the same unit', () {
    final g = summary([
      purchase(quantity: BigInt.from(15), scale: 1),
      purchase(quantity: BigInt.from(500), scale: 3, rate: 2000000),
    ]).groups.single;
    expect(g.weightedMean.euros, '1,2500');
  });
  test('first/latest days include all same-day purchases independent of arrival order', () {
    final rows = [
      purchase(date: '3.11.2026 23:59', quantity: BigInt.two, rate: 3000000),
      purchase(date: '1.11.2026 00:00'),
      purchase(date: '2.11.2026', rate: 9000000),
      purchase(date: '1.11.2026', quantity: BigInt.from(3), rate: 3000000),
      purchase(date: '3.11.2026', quantity: BigInt.two),
    ];
    for (final ordered in [rows, rows.reversed.toList()]) {
      final g = summary(ordered).groups.single;
      expect(g.firstPurchaseDay.count, 2);
      expect(g.lastPurchaseDay.count, 2);
      expect(g.firstPurchaseDay.weightedMean.euros, '2,5000');
      expect(g.lastPurchaseDay.weightedMean.euros, '2,0000');
      expect(g.changeTenthsPercent, BigInt.from(-200));
    }
  });
  test(
    'single-day and zero-baseline comparisons do not invent a percentage',
    () {
      expect(
        summary([purchase(), purchase(rate: 2000000)])
            .groups
            .single
            .changeTenthsPercent,
        isNull,
      );
      final g = summary([purchase(rate: 0), purchase(date: '3.11.2026')])
          .groups
          .single;
      expect(g.firstPurchaseDay.weightedMean.euros, '0,0000');
      expect(g.changeTenthsPercent, isNull);
      final free = summary([purchase(), purchase(date: '3.11.2026', rate: 0)])
          .groups
          .single;
      expect(free.changeTenthsPercent, BigInt.from(-1000));
    },
  );
  test('percentage uses exact prices even when both displayed values round to zero', () {
    final g = summary([
      purchase(quantity: BigInt.from(10000), rate: 1),
      purchase(quantity: BigInt.from(10000), rate: 2, date: '3.11.2026'),
    ]).groups.single;
    expect(g.firstPurchaseDay.weightedMean.euros, '0,0000');
    expect(g.lastPurchaseDay.weightedMean.euros, '0,0000');
    expect(g.changeTenthsPercent, BigInt.from(1000));
  });
  test('percentage rounds exact positive and negative halfway values once', () {
    UnitPrice price(int cents) =>
        UnitPrice.fromLine(BigInt.from(cents), BigInt.one, 0);
    expect(price(2001).changeTenthsPercentFrom(price(2000)), BigInt.one);
    expect(price(1999).changeTenthsPercentFrom(price(2000)), -BigInt.one);
    expect(price(2000).changeTenthsPercentFrom(price(2000)), BigInt.zero);
    expect(price(1).changeTenthsPercentFrom(price(0)), isNull);
  });
  test('spending includes returns, unknown quantities and negative nets, excludes receipt extras', () {
    final s = summary([
      purchase(discount: -25, extras: true),
      purchase(date: '2.11.2026', quantity: -BigInt.two),
      purchase(date: '3.11.2026', quantified: false, cents: 250),
      purchase(date: '3.11.2026', discount: -101),
    ]);
    expect(s.spendingBuckets.map((b) => b.effectiveCents), [
      BigInt.from(75),
      BigInt.from(-200),
      BigInt.from(249),
    ]);
    expect(s.spendingBuckets.map((b) => b.count), [1, 1, 2]);
    expect(s.spendingBuckets.map((b) => b.returnRows), [0, 1, 0]);
    expect(
      s.spendingBuckets.fold(BigInt.zero, (sum, b) => sum + b.effectiveCents),
      s.effectiveCents,
    );
    expect(s.groups.single.weightedMean.euros, '0,7500');
  });
  test('observed zero spend and empty intervals remain distinguishable and immutable', () {
    final s = summary([purchase(rate: 0)]);
    expect(s.spendingBuckets.map((b) => b.count), [1, 0, 0]);
    expect(
      s.spendingBuckets.every((b) => b.effectiveCents == BigInt.zero),
      isTrue,
    );
    expect(() => s.spendingBuckets.clear(), throwsUnsupportedError);
  });
  test('units and piece revisions cannot blend into a price comparison', () {
    final s = summary([
      purchase(),
      purchase(unit: QuantityUnit.litre, rate: 2000000),
      purchase(unit: QuantityUnit.piece),
      purchase(unit: QuantityUnit.piece, revision: 2, rate: 3000000),
    ]);
    expect(s.groups.length, 4);
    expect(s.groups.every((g) => g.changeTenthsPercent == null), isTrue);
    expect(s.spendingBuckets.first.count, 4);
  });
  test('weighted quantities and signed totals safely exceed int64', () {
    final q = BigInt.parse('9000000000000000000');
    final rows = [for (var i = 0; i < 3; i++) purchase(quantity: q, scale: 6)];
    final s = summary(rows);
    expect(s.groups.single.weightedMean.euros, '1,0000');
    expect(s.groups.single.weightedMean.denominator, q * BigInt.from(3));
    final huge = summary([
      for (var i = 0; i < 3; i++)
        purchase(quantified: false, cents: 9223372036854775807),
    ]);
    expect(
      huge.spendingBuckets.first.effectiveCents,
      sqliteInt64Max * BigInt.from(3),
    );
  });
  test('24 intervals partition leap/calendar boundaries without missing or duplicated days', () {
    final s = summary(
      [purchase(date: '29.2.2024'), purchase(date: '31.12.2024')],
      from: '1.1.2024',
      through: '31.12.2024',
    );
    expect(s.spendingBuckets.length, 24);
    for (var i = 1; i < 24; i++) {
      expect(
        s.spendingBuckets[i].firstDay,
        s.spendingBuckets[i - 1].lastDay + 1,
      );
    }
    expect(s.spendingBuckets.map((b) => b.count).fold(0, (a, b) => a + b), 2);
    expect(s.groups.single.buckets.length, 2);
  });
}
