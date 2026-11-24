import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final branch = ReceiptBranch(id: id(2), name: 'SYNTHETIC BRANCH');
  ReceiptProductLink link(int n, {DurableId? store}) => ReceiptProductLink(
    id: id(n),
    storeId: store ?? branch.id,
    revision: RevisionId(id(999), BigInt.one),
  );
  ReceiptSnapshot sample(
    List<ReceiptItemSnapshot> rows, {
    int n = 1,
    ReceiptBranch? at,
    String date = '17.11.2026',
  }) => receipt(
    number: n,
    branch: at ?? branch,
    date: date,
    items: rows,
    total: rows.fold<BigInt>(BigInt.zero, (sum, r) => sum + r.cents),
  );
  ProductSpendingSummary build(
    Iterable<ReceiptSnapshot> receipts, {
    Map<DurableId, ProductSnapshot> products = const {},
  }) {
    final b = ProductSpendingBuilder();
    for (final r in receipts) {
      b.add(r, products);
    }
    return b.build();
  }

  test('all rows reconcile; item discounts follow products and duplicate rows count one receipt', () {
    final value = sample([
      row(number: 3, cents: BigInt.from(300), product: link(10)),
      row(number: 4, cents: BigInt.from(200), product: link(10)),
      row(
        number: 5,
        cents: BigInt.from(-50),
        kind: LineKind.discount,
        parent: id(3),
        scope: DiscountScope.item,
      ),
      row(number: 6, cents: BigInt.from(-100), product: link(11)),
      row(number: 7, cents: BigInt.from(400)),
      row(
        number: 8,
        cents: BigInt.from(-25),
        kind: LineKind.discount,
        parent: id(7),
        scope: DiscountScope.item,
      ),
      row(
        number: 9,
        cents: BigInt.from(40),
        kind: LineKind.deposit,
        parent: id(3),
      ),
      row(
        number: 12,
        cents: BigInt.from(-10),
        kind: LineKind.discount,
        scope: DiscountScope.receipt,
      ),
      row(
        number: 13,
        cents: BigInt.from(5),
        kind: LineKind.adjustment,
        reason: 'SYNTHETIC CHECKED',
      ),
    ]);
    final s = build([value]);
    expect(s.groups.map((g) => g.totalCents), [
      BigInt.from(450),
      BigInt.from(-100),
    ]);
    expect(s.groups.first.rowCount, 2);
    expect(s.groups.first.receiptCount, 1);
    expect(s.groups.last.returnRows, 1);
    expect(s.groups.last.returnCents, BigInt.from(-100));
    expect(s.productRows, 4);
    expect(s.linkedRows, 3);
    expect(s.linkedCents, BigInt.from(350));
    expect(s.unlinkedCents, BigInt.from(375));
    expect(s.depositCents, BigInt.from(40));
    expect(s.receiptDiscountCents, BigInt.from(-10));
    expect(s.adjustmentCents, BigInt.from(5));
    expect(s.receiptTotalCents, value.totalCents);
    expect(() => s.groups.clear(), throwsUnsupportedError);
  });
  test('equal product/branch names never merge distinct identities', () {
    final other = ReceiptBranch(id: id(20), name: branch.name);
    final s = build([
      sample([row(product: link(10)), row(number: 4, product: link(11))]),
      sample(
        [row(number: 21, product: link(22, store: other.id))],
        n: 23,
        at: other,
      ),
    ]);
    expect(s.groups.length, 3);
    expect(s.groups.map((g) => g.productId).toSet(), {id(10), id(11), id(22)});
    expect(s.groups.map((g) => g.branch.id).toSet(), {branch.id, other.id});
  });
  test('spending combines revisions of one identity without inferring quantity or price equivalence', () {
    final a = sample([row(product: link(10))]);
    final b = sample([
      row(
        number: 4,
        product: ReceiptProductLink(
          id: id(10),
          storeId: branch.id,
          revision: RevisionId(id(999), BigInt.two),
        ),
      ),
    ], n: 5);
    final s = build([a, b]);
    expect(s.groups.single.totalCents, BigInt.from(400));
    expect(s.groups.single.rowCount, 2);
    expect(s.groups.single.receiptCount, 2);
  });
  test(
    'current canonical labels change no original receipt fields or net amounts',
    () {
      final r = sample([row(name: 'ORIGINAL ALIAS', product: link(10))]);
      final bytes = ReceiptSnapshotCodec.encode(r);
      final s = build(
        [r],
        products: {
          id(10): ProductSnapshot(
            id: id(10),
            storeId: branch.id,
            canonicalName: 'CURRENT CANONICAL',
            category: 'Other',
          ),
        },
      );
      expect(s.groups.single.name, 'CURRENT CANONICAL');
      expect(s.groups.single.totalCents, BigInt.from(200));
      expect(ReceiptSnapshotCodec.encode(r), bytes);
    },
  );
  test('signed ordering keeps free and refund-only products, stable identity tie breaks', () {
    final values = [
      sample([row(product: link(11))]),
      sample([row(number: 4, product: link(10))], n: 2),
      sample([row(number: 5, cents: BigInt.zero, product: link(12))], n: 3),
      sample([
        row(number: 6, cents: BigInt.from(-200), product: link(13)),
      ], n: 4),
    ];
    final a = build(values), b = build(values.reversed);
    expect(a.groups.map((g) => g.productId), [id(10), id(11), id(12), id(13)]);
    expect(b.groups.map((g) => g.productId), a.groups.map((g) => g.productId));
  });
  test(
    'fallback label uses latest day then stable receipt/name tie breaks',
    () {
      final a = sample(
        [row(name: 'OLDER', product: link(10))],
        n: 4,
        date: '16.11.2026',
      );
      final b = sample([
        row(number: 5, name: 'NEW Z', product: link(10)),
      ], n: 3);
      final c = sample([
        row(number: 6, name: 'NEW A', product: link(10)),
        row(number: 7, name: 'NEW B', product: link(10)),
      ], n: 2);
      expect(build([a, b, c]).groups.single.name, 'NEW A');
      expect(build([c, b, a]).groups.single.name, 'NEW A');
      expect(build([a, b, c]).groups.single.receiptCount, 3);
    },
  );
  test('negative net from a discount is retained without pretending it is a return', () {
    final s = build([
      sample([
        row(product: link(10)),
        row(
          number: 4,
          kind: LineKind.discount,
          cents: BigInt.from(-250),
          parent: id(3),
          scope: DiscountScope.item,
        ),
      ]),
    ]);
    expect(s.groups.single.totalCents, BigInt.from(-50));
    expect(s.groups.single.returnRows, 0);
  });
  test('unlinked-only and empty summaries do not invent ranked products', () {
    final empty = build([]);
    expect(empty.groups, isEmpty);
    expect(empty.receiptTotalCents, BigInt.zero);
    final unlinked = build([
      sample([row()]),
    ]);
    expect(unlinked.groups, isEmpty);
    expect(unlinked.productRows, 1);
    expect(unlinked.linkedRows, 0);
    expect(unlinked.unlinkedCents, BigInt.from(200));
  });
  test('wrong catalog identity or branch is rejected', () {
    final r = sample([row(product: link(10))]);
    for (final meta in [
      ProductSnapshot(id: id(11), storeId: branch.id, canonicalName: 'WRONG'),
      ProductSnapshot(id: id(10), storeId: id(20), canonicalName: 'WRONG'),
    ]) {
      expect(
        () => build([r], products: {id(10): meta}),
        throwsA(isA<ReceiptDataException>()),
      );
    }
  });
  test('net totals beyond int64 remain exact without unit or quantity prerequisites', () {
    final r = sample([row(cents: sqliteInt64Max, product: link(10))]);
    final s = build([r, r, r]);
    expect(s.groups.single.totalCents, sqliteInt64Max * BigInt.from(3));
    expect(s.linkedCents, s.receiptTotalCents);
  });
  test('overflow withholds the complete ranking but retains all financial and coverage totals', () {
    final b = ProductSpendingBuilder();
    for (var i = 0; i < ProductSpendingBuilder.maxGroups; i++) {
      b.add(
        sample([
          row(number: 20000 + i, cents: BigInt.one, product: link(10000 + i)),
        ], n: 30000 + i),
        const {},
      );
    }
    expect(b.build().groups.length, ProductSpendingBuilder.maxGroups);
    expect(b.build().limitExceeded, isFalse);
    b.add(
      sample([
        row(number: 50000, cents: BigInt.from(7), product: link(50001)),
        row(number: 50002, cents: BigInt.from(-2)),
      ], n: 50003),
      const {},
    );
    b.add(
      sample([
        row(number: 50004, cents: BigInt.from(3), product: link(10000)),
      ], n: 50005),
      const {},
    );
    final s = b.build();
    expect(s.limitExceeded, isTrue);
    expect(s.groups, isEmpty);
    expect(s.linkedRows, ProductSpendingBuilder.maxGroups + 2);
    expect(s.linkedCents, BigInt.from(ProductSpendingBuilder.maxGroups + 10));
    expect(s.unlinkedCents, BigInt.from(-2));
    expect(
      s.receiptTotalCents,
      BigInt.from(ProductSpendingBuilder.maxGroups + 8),
    );
  });
  test('dashboard ranks only selected dates and branches, including custom inclusive days', () {
    final other = ReceiptBranch(id: id(20), name: 'OTHER');
    for (final unit in SpendingPeriodUnit.values) {
      final query = SpendingDashboardQuery(
        unit: unit,
        anchor: StoredReceiptDate.parse('17.11.2026'),
        today: StoredReceiptDate.parse('18.11.2026'),
        branchId: branch.id,
        customFrom: unit == SpendingPeriodUnit.custom
            ? StoredReceiptDate.parse('17.11.2026')
            : null,
        customThrough: unit == SpendingPeriodUnit.custom
            ? StoredReceiptDate.parse('17.11.2026')
            : null,
      );
      final b = SpendingDashboardBuilder(query);
      b.add(sample([row(product: link(10))], date: '17.11.2026 23:59:59'));
      b.add(
        sample([row(number: 4, product: link(11))], n: 40, date: '19.11.2026'),
      );
      b.add(
        sample(
          [row(number: 5, product: link(22, store: other.id))],
          n: 50,
          at: other,
        ),
      );
      b.add(
        sample([row(number: 6, product: link(10))], n: 60, date: '1.1.2025'),
      );
      final data = b.build();
      expect(data.products.groups.single.productId, id(10));
      expect(data.products.receiptTotalCents, data.selected.totalCents);
    }
  });
}
