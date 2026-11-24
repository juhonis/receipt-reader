import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

SpendingDashboardQuery query({
  String today = '18.11.2026',
  DurableId? branch,
}) => SpendingDashboardQuery(
  unit: SpendingPeriodUnit.month,
  anchor: StoredReceiptDate.parse(today),
  today: StoredReceiptDate.parse(today),
  branchId: branch,
);

void add(
  SpendingDashboardBuilder builder,
  String date,
  List<(String?, BigInt)> values, {
  ReceiptBranch? branch,
}) {
  final rows = [
    for (var i = 0; i < values.length; i++)
      row(
        number: 100 + i,
        cents: values[i].$2,
        product: ReceiptProductLink(
          id: id(1000 + i),
          storeId: branch?.id ?? id(2),
          revision: RevisionId(id(9), BigInt.one),
        ),
      ),
  ];
  builder.add(
    receipt(
      date: date,
      branch: branch,
      items: rows,
      total: rows.fold<BigInt>(BigInt.zero, (sum, r) => sum + r.cents),
    ),
    productCategories: {
      for (var i = 0; i < values.length; i++) id(1000 + i): values[i].$1,
    },
  );
}

void main() {
  test(
    'matched categories exclude unmatched selected days and reconcile exactly',
    () {
      final b = SpendingDashboardBuilder(query(today: '31.3.2025'));
      add(b, '28.3.2025', [
        ('Food', BigInt.from(300)),
        ('New', BigInt.from(100)),
      ]);
      add(b, '31.3.2025', [('Food', BigInt.from(9000))]);
      add(b, '28.2.2025', [
        ('Food', BigInt.from(200)),
        ('Old', BigInt.from(50)),
      ]);
      final d = b.build();
      expect(d.selected.totalCents, BigInt.from(9400));
      expect(d.categoryCurrent.totalCents, BigInt.from(400));
      expect(d.categoryPrevious.totalCents, BigInt.from(250));
      expect(
        d.categoryChanges.fold(BigInt.zero, (sum, g) => sum + g.changeCents),
        d.changeCents,
      );
      final food = d.categoryChanges.singleWhere(
        (g) => g.category.name == 'Food',
      );
      expect(food.changeTenthsPercent, BigInt.from(500));
      final old = d.categoryChanges.singleWhere(
        (g) => g.category.name == 'Old',
      );
      expect(old.changeTenthsPercent, BigInt.from(-1000));
      expect(old.current.receiptCount, 0);
      expect(
        d.categoryChanges
            .singleWhere((g) => g.category.name == 'New')
            .changeTenthsPercent,
        isNull,
      );
    },
  );
  test('empty observation differs from observed zero, negative baselines omit percent', () {
    final b = SpendingDashboardBuilder(query());
    add(b, '18.11.2026', [('Food', BigInt.from(100))]);
    expect(b.build().comparisonAvailable, isFalse);
    expect(b.build().categoryChanges.single.changeTenthsPercent, isNull);
    add(b, '18.10.2026', [('Food', BigInt.zero), ('Return', BigInt.from(-50))]);
    final d = b.build();
    expect(d.comparisonAvailable, isTrue);
    expect(
      d.categoryChanges.every((g) => g.changeTenthsPercent == null),
      isTrue,
    );
  });
  test(
    'bounded union retains 128 groups with deterministic equal-delta ordering',
    () {
      final b = SpendingDashboardBuilder(query());
      add(b, '18.11.2026', [for (var i = 0; i < 64; i++) ('A$i', BigInt.one)]);
      add(b, '18.10.2026', [for (var i = 0; i < 64; i++) ('B$i', BigInt.one)]);
      final d = b.build();
      expect(d.categoryChanges, hasLength(128));
      expect(d.categoryChanges.first.category.name, 'A0');
      expect(d.categoryChanges[1].category.name, 'A1');
      expect(
        d.categoryChanges.fold(BigInt.zero, (sum, g) => sum + g.changeCents),
        BigInt.zero,
      );
    },
  );
  test(
    'signed special groups reconcile and cannot collide with user labels',
    () {
      final b = SpendingDashboardBuilder(query());
      add(b, '18.11.2026', [('Pantit', BigInt.from(100))]);
      b.add(
        receipt(
          date: '18.11.2026',
          total: BigInt.from(10),
          items: [
            row(number: 10, cents: BigInt.from(100)),
            row(
              number: 11,
              cents: BigInt.from(-30),
              kind: LineKind.discount,
              scope: DiscountScope.item,
              parent: id(10),
            ),
            row(
              number: 12,
              cents: BigInt.from(10),
              kind: LineKind.deposit,
              parent: id(10),
            ),
            row(
              number: 13,
              cents: BigInt.from(-50),
              kind: LineKind.discount,
              scope: DiscountScope.receipt,
            ),
            row(
              number: 14,
              cents: BigInt.from(-20),
              kind: LineKind.adjustment,
              reason: 'TEST',
            ),
          ],
        ),
      );
      add(b, '18.10.2026', [(null, BigInt.one)]);
      final d = b.build();
      expect(d.categoryChanges, hasLength(5));
      expect(
        d.categoryChanges.fold(BigInt.zero, (sum, g) => sum + g.changeCents),
        d.changeCents,
      );
      expect(
        d.categoryChanges.any(
          (g) => g.category == const ReceiptCategory.deposit(),
        ),
        isTrue,
      );
      expect(
        d.categoryChanges.any(
          (g) => g.category == ReceiptCategory.product('Pantit'),
        ),
        isTrue,
      );
    },
  );
  test('branch scope and exact amounts above double precision apply to both periods', () {
    final branch = ReceiptBranch(id: id(2), name: 'A');
    final b = SpendingDashboardBuilder(query(branch: branch.id));
    final large = BigInt.parse('9007199254740993');
    add(b, '18.11.2026', [('Food', large + BigInt.one)], branch: branch);
    add(b, '18.10.2026', [('Food', large)], branch: branch);
    add(b, '18.10.2026', [
      ('Food', BigInt.from(999)),
    ], branch: ReceiptBranch(id: id(3), name: 'B'));
    expect(b.build().categoryChanges.single.changeCents, BigInt.one);
    expect(b.build().categoryChanges.single.changeTenthsPercent, BigInt.zero);
  });
}
