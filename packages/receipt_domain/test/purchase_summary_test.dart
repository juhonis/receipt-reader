import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  final store = DurableId.generate(),
      product = DurableId.generate(),
      origin = DurableId.generate();
  ProductPurchase observation({
    String date = '17.11.2026',
    int revision = 1,
    QuantityUnit unit = QuantityUnit.piece,
    bool quantified = true,
    int cents = 400,
    int quantity = 2,
    int discount = 0,
    bool warnings = false,
    DurableId? productId,
  }) {
    final row = ReceiptItemSnapshot(
      id: DurableId.generate(),
      name: 'TEST',
      kind: LineKind.product,
      cents: BigInt.from(cents),
      product: ReceiptProductLink(
        id: productId ?? product,
        storeId: store,
        revision: RevisionId(origin, BigInt.from(revision)),
      ),
      quantityValue: quantified ? BigInt.from(quantity) : null,
      quantityScale: quantified ? 0 : null,
      quantityUnit: quantified ? unit : null,
      rateMicros: quantified ? BigInt.from(cents ~/ quantity * 10000) : null,
    );
    final rows = [
      row,
      if (discount < 0)
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SALE',
          kind: LineKind.discount,
          cents: BigInt.from(discount),
          parentItemId: row.id,
          discountScope: DiscountScope.item,
        ),
      if (warnings) ...[
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(40),
          parentItemId: row.id,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'RECEIPT SALE',
          kind: LineKind.discount,
          cents: BigInt.from(-20),
          discountScope: DiscountScope.receipt,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'ADJUSTMENT',
          kind: LineKind.adjustment,
          cents: BigInt.one,
          adjustmentReason: 'Reviewed',
        ),
      ],
    ];
    return ProductPurchase.fromReceipt(
      ReceiptSnapshot(
        id: DurableId.generate(),
        branch: ReceiptBranch(id: store, name: 'TEST'),
        date: StoredReceiptDate.parse(date),
        totalCents: rows.fold(BigInt.zero, (s, r) => s + r.cents),
        items: rows,
      ),
      row.id,
    );
  }

  PurchaseSummaryBuilder builder(String from, String through) =>
      PurchaseSummaryBuilder(
        storeId: store,
        productId: product,
        firstDay: purchaseCalendarDay(StoredReceiptDate.parse(from)),
        lastDay: purchaseCalendarDay(StoredReceiptDate.parse(through)),
      );

  test('inclusive civil dates, open bounds, reversed bounds and times', () {
    final r = PurchaseDateRange(
      fromDate: StoredReceiptDate.parse('29.3.2026'),
      throughDate: StoredReceiptDate.parse('25.10.2026'),
    );
    expect(r.contains(StoredReceiptDate.parse('29.3.2026 04:00')), isTrue);
    expect(r.contains(StoredReceiptDate.parse('25.10.2026 04:00')), isTrue);
    expect(r.contains(StoredReceiptDate.parse('28.3.2026')), isFalse);
    expect(r.contains(StoredReceiptDate.parse('26.10.2026')), isFalse);
    expect(PurchaseDateRange().isEmpty, isTrue);
    expect(
      PurchaseDateRange(throughDate: r.throughDate)
          .contains(StoredReceiptDate.parse('1.1.1970')),
      isTrue,
    );
    expect(
      () => PurchaseDateRange(fromDate: r.throughDate, throughDate: r.fromDate),
      throwsA(isA<ReceiptDataException>()),
    );
    expect(
      () => PurchaseDateRange(
        fromDate: StoredReceiptDate.parse('17.11.2026 12:00'),
      ),
      throwsA(isA<ReceiptDataException>()),
    );
    final leap = StoredReceiptDate.parse('29.2.2024');
    expect(purchaseCalendarDate(purchaseCalendarDay(leap)).day, 29);
    expect(
      purchaseCalendarDay(StoredReceiptDate.parse('30.3.2026')) -
          purchaseCalendarDay(r.fromDate!),
      1,
    );
  });
  test('all rows partition into comparable, returns, missing and negative, with exact subtotals', () {
    final b = builder('17.11.2026', '17.11.2026');
    for (final p in [
      observation(discount: -100, warnings: true),
      observation(cents: -400, quantity: -2),
      observation(quantified: false),
      observation(discount: -401),
      observation(discount: -400),
    ]) {
      b.add(p);
    }
    final s = b.finish();
    expect(s.totalRows, 5);
    expect(s.comparableRows, 2);
    expect(s.returnRows, 1);
    expect(s.missingQuantityRows, 1);
    expect(s.negativeEffectiveRows, 1);
    expect(s.receiptDiscountRows, 1);
    expect(s.adjustmentRows, 1);
    expect(s.rawCents, BigInt.from(1200));
    expect(s.effectiveCents, BigInt.from(299));
    final group = s.groups.single;
    expect(group.minimum.euros, '0,0000');
    expect(group.maximum.euros, '1,5000');
    expect(group.count, 2);
    expect(group.receiptDiscountRows, 1);
    expect(group.buckets.single.count, 2);
    expect(() => s.groups.clear(), throwsUnsupportedError);
    expect(() => group.buckets.clear(), throwsUnsupportedError);
  });
  test('64 groups and 24 calendar buckets are bounded without losing any row or extrema', () {
    final b = builder('1.1.2026', '25.1.2026');
    for (var day = 1; day <= 25; day++) {
      b.add(observation(date: '${day}.1.2026', cents: day * 100, quantity: 1));
    }
    final group = b.finish().groups.single;
    expect(group.count, 25);
    expect(group.buckets, hasLength(24));
    expect(group.buckets.fold(0, (n, b) => n + b.count), 25);
    expect(group.buckets.first.count, 2);
    expect(group.buckets.first.minimum.euros, '1,0000');
    expect(group.buckets.first.maximum.euros, '2,0000');
    expect(group.minimum.euros, '1,0000');
    expect(group.maximum.euros, '25,0000');
    expect(purchaseCalendarDate(group.buckets.first.firstDay).day, 1);
    expect(purchaseCalendarDate(group.buckets.first.lastDay).day, 2);
    expect(purchaseCalendarDate(group.buckets.last.lastDay).day, 25);
    final many = builder('17.11.2026', '17.11.2026');
    for (var i = 1; i <= 64; i++) {
      many.add(observation(revision: i));
    }
    expect(many.finish().groups, hasLength(64));
    expect(
      () => many.add(observation(revision: 65)),
      throwsA(
        isA<ReceiptDataException>().having((e) => e.code, 'code', 'groupLimit'),
      ),
    );
  });
  test(
    'empty calendar gaps stay empty, units and piece revisions remain separate',
    () {
      final b = builder('1.1.2026', '31.12.2026');
      b.add(observation(date: '1.1.2026', unit: QuantityUnit.kg));
      b.add(
        observation(date: '31.12.2026', unit: QuantityUnit.kg, revision: 2),
      );
      b.add(observation(unit: QuantityUnit.litre));
      b.add(observation());
      b.add(observation(revision: 2));
      final s = b.finish();
      expect(s.groups, hasLength(4));
      final kg = s.groups.where((g) => g.unit == QuantityUnit.kg).single;
      expect(kg.count, 2);
      expect(kg.buckets, hasLength(2));
      expect(kg.buckets.first.lastDay < kg.buckets.last.firstDay - 1, isTrue);
    },
  );
  test('identity and outside-range observations fail, empty summary has no invented extent', () {
    final b = builder('17.11.2026', '17.11.2026');
    expect(
      () => b.add(observation(date: '16.11.2026')),
      throwsA(isA<ReceiptDataException>()),
    );
    expect(
      () => b.add(observation(productId: DurableId.generate())),
      throwsA(isA<ReceiptDataException>()),
    );
    expect(b.finish().totalRows, 0);
    final empty = PurchaseSummaryBuilder(
      storeId: store,
      productId: product,
      firstDay: null,
      lastDay: null,
    ).finish();
    expect(empty.firstDay, isNull);
    expect(empty.groups, isEmpty);
  });
  test('aggregate signed cents can exceed SQLite int64 without overflow', () {
    final b = builder('17.11.2026', '17.11.2026');
    for (var i = 0; i < 3; i++) {
      b.add(observation(cents: 9223372036854775807, quantified: false));
    }
    expect(b.finish().rawCents, sqliteInt64Max * BigInt.from(3));
    expect(b.finish().effectiveCents, sqliteInt64Max * BigInt.from(3));
    expect(b.finish().missingQuantityRows, 3);
  });
}
