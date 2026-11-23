import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

StoredReceiptDate day(String value) => StoredReceiptDate.parse(value);
SpendingDashboardQuery query(
  String anchor, {
  String today = '22.11.2026',
  SpendingPeriodUnit unit = SpendingPeriodUnit.month,
  DurableId? branch,
}) => SpendingDashboardQuery(
  unit: unit,
  anchor: day(anchor),
  today: day(today),
  branchId: branch,
);
(String, String) range(SpendingPeriod p) {
  String text(int n) {
    final d = purchaseCalendarDate(n);
    return '${d.day}.${d.month}.${d.year}';
  }

  return (text(p.firstDay), text(p.lastDay));
}

ReceiptSnapshot receipt(String date, int cents, {ReceiptBranch? branch}) =>
    ReceiptSnapshot(
      id: DurableId.generate(),
      branch: branch ?? ReceiptBranch(id: DurableId.generate(), name: 'TEST'),
      date: day(date),
      totalCents: BigInt.from(cents),
      items: [
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'TEST',
          kind: LineKind.product,
          cents: BigInt.from(cents),
        ),
      ],
    );

void main() {
  test('Monday weeks cross year and DST boundaries without UTC shifts', () {
    final year = query('1.1.2026', unit: SpendingPeriodUnit.week);
    expect(range(year.selected), ('29.12.2025', '4.1.2026'));
    expect(year.periods, hasLength(7));
    final dst = query('25.10.2026', unit: SpendingPeriodUnit.week);
    expect(range(dst.selected), ('19.10.2026', '25.10.2026'));
    expect(dst.selected.dayCount, 7);
  });
  test('unfinished week compares matching Monday through Wednesday', () {
    final q = query(
      '18.11.2026',
      today: '18.11.2026',
      unit: SpendingPeriodUnit.week,
    );
    expect(range(q.selected), ('16.11.2026', '18.11.2026'));
    expect(range(q.comparisonPrevious!), ('9.11.2026', '11.11.2026'));
    final b = SpendingDashboardBuilder(q)
      ..add(receipt('18.11.2026 23:59:59', 300))
      ..add(receipt('19.11.2026', 999))
      ..add(receipt('11.11.2026', 200))
      ..add(receipt('12.11.2026', 700));
    final result = b.build();
    expect(result.selected.totalCents, BigInt.from(300));
    expect(
      result.periods.fold(BigInt.zero, (sum, p) => sum + p.totals.totalCents),
      BigInt.from(300),
    );
    expect(result.changeCents, BigInt.from(100));
    expect(result.changeTenthsPercent, BigInt.from(500));
  });
  test('short previous month truncates both comparison windows, not selected total', () {
    final q = query('31.3.2025', today: '31.3.2025');
    expect(range(q.selected), ('1.3.2025', '31.3.2025'));
    expect(range(q.comparisonCurrent!), ('1.3.2025', '28.3.2025'));
    expect(range(q.comparisonPrevious!), ('1.2.2025', '28.2.2025'));
    final result =
        (SpendingDashboardBuilder(q)
              ..add(receipt('28.3.2025', 100))
              ..add(receipt('31.3.2025', 900))
              ..add(receipt('28.2.2025', 50)))
            .build();
    expect(result.selected.totalCents, BigInt.from(1000));
    expect(result.comparisonCurrent.totalCents, BigInt.from(100));
    expect(result.changeTenthsPercent, BigInt.from(1000));
    expect(result.selected.receiptCount, 2);
  });
  test('completed leap month compares whole calendar months', () {
    final q = query('29.2.2024');
    expect(q.selected.inProgress, isFalse);
    expect(range(q.selected), ('1.2.2024', '29.2.2024'));
    expect(range(q.comparisonPrevious!), ('1.1.2024', '31.1.2024'));
    expect(q.comparisonCurrent!.dayCount, 29);
  });
  test(
    '1970 lower boundary clips weeks and omits unsupported predecessors',
    () {
      final q = query('1.1.1970', unit: SpendingPeriodUnit.week);
      expect(q.periods, hasLength(4));
      expect(range(q.selected), ('1.1.1970', '4.1.1970'));
      expect(q.comparisonPrevious, isNull);
      expect(
        query('5.1.1970', unit: SpendingPeriodUnit.week).periods,
        hasLength(7),
      );
      expect(query('1.1.1970').comparisonPrevious, isNull);
    },
  );
  test(
    'missing, known zero and negative baselines do not invent percentages',
    () {
      final b = SpendingDashboardBuilder(query('1.11.2026'));
      expect(averageReceiptCents(b.build().selected), isNull);
      b.add(receipt('1.11.2026', 0));
      expect(b.build().selected.receiptCount, 1);
      expect(averageReceiptCents(b.build().selected), BigInt.zero);
      expect(b.build().changeTenthsPercent, isNull);
      b.add(receipt('1.10.2026', 0));
      expect(b.build().changeTenthsPercent, isNull);
      b.add(receipt('2.10.2026', -50));
      expect(b.build().changeCents, BigInt.from(50));
      expect(b.build().changeTenthsPercent, isNull);
    },
  );
  test(
    'signed totals and display rounding stay exact beyond double precision',
    () {
      final b = SpendingDashboardBuilder(query('1.11.2026'))
        ..add(receipt('1.11.2026', 9007199254740993))
        ..add(receipt('2.11.2026', 9007199254740994));
      expect(b.build().selected.totalCents, BigInt.parse('18014398509481987'));
      expect(
        averageReceiptCents(b.build().selected),
        BigInt.parse('9007199254740994'),
      );
      expect(roundSpendingRatio(BigInt.from(-3), BigInt.two), BigInt.from(-2));
      final negative =
          (SpendingDashboardBuilder(query('1.11.2026'))
                ..add(receipt('1.11.2026', -3))
                ..add(receipt('2.11.2026', 0)))
              .build();
      expect(averageReceiptCents(negative.selected), BigInt.from(-2));
    },
  );
  test('equal-name branches remain distinct and results are immutable', () {
    final one = ReceiptBranch(id: DurableId.generate(), name: 'SAME');
    final two = ReceiptBranch(id: DurableId.generate(), name: 'SAME');
    final b = SpendingDashboardBuilder(query('1.11.2026', branch: one.id))
      ..add(receipt('1.11.2026', 100, branch: one))
      ..add(receipt('1.11.2026', 500, branch: two));
    final saved = b.build();
    expect(saved.selected.totalCents, BigInt.from(100));
    expect(() => saved.periods.clear(), throwsUnsupportedError);
    expect(() => saved.query.periods.clear(), throwsUnsupportedError);
    b.add(receipt('2.11.2026', 100, branch: one));
    expect(saved.selected.receiptCount, 1);
  });
  test('future anchors and timestamp bounds are rejected', () {
    expect(() => query('23.11.2026'), throwsA(isA<ReceiptDataException>()));
    expect(
      () => query('1.11.2026 12:00'),
      throwsA(isA<ReceiptDataException>()),
    );
  });
  test(
    'whole year totals span all monthly buckets including leap February',
    () {
      final q = query('1.7.2024', unit: SpendingPeriodUnit.year);
      expect(range(q.selected), ('1.1.2024', '31.12.2024'));
      expect(range(q.comparisonPrevious!), ('1.1.2023', '31.12.2023'));
      expect(q.periods, hasLength(12));
      expect(range(q.periods[1]), ('1.2.2024', '29.2.2024'));
      final result =
          (SpendingDashboardBuilder(q)
                ..add(receipt('1.1.2024', 100))
                ..add(receipt('31.12.2024 23:59:59', 200))
                ..add(receipt('1.1.2023', 500)))
              .build();
      expect(result.selected.totalCents, BigInt.from(300));
      expect(result.periods.last.totals.totalCents, BigInt.from(200));
      expect(result.comparisonPrevious.totalCents, BigInt.from(500));
    },
  );
  test(
    'unfinished leap year compares equal day counts, not different dates',
    () {
      final q = query(
        '1.3.2024',
        today: '1.3.2024',
        unit: SpendingPeriodUnit.year,
      );
      expect(range(q.selected), ('1.1.2024', '1.3.2024'));
      expect(range(q.comparisonPrevious!), ('1.1.2023', '2.3.2023'));
      expect(q.periods, hasLength(3));
      expect(q.periods.last.inProgress, isTrue);
      expect(q.periods.last.dayCount, 1);
    },
  );
  SpendingDashboardQuery custom(
    String from,
    String through, {
    String today = '22.11.2026',
  }) => SpendingDashboardQuery(
    unit: SpendingPeriodUnit.custom,
    anchor: day(from),
    today: day(today),
    customFrom: day(from),
    customThrough: day(through),
  );
  test(
    'custom range and previous equal-length range use inclusive civil days',
    () {
      final q = custom('28.2.2024', '1.3.2024');
      expect(range(q.selected), ('28.2.2024', '1.3.2024'));
      expect(range(q.comparisonPrevious!), ('25.2.2024', '27.2.2024'));
      final result =
          (SpendingDashboardBuilder(q)
                ..add(receipt('28.2.2024', 200))
                ..add(receipt('29.2.2024', 100))
                ..add(receipt('1.3.2024 23:59:59', -50))
                ..add(receipt('2.3.2024', 999))
                ..add(receipt('27.2.2024', 100)))
              .build();
      expect(result.selected.totalCents, BigInt.from(250));
      expect(result.comparisonPrevious.totalCents, BigInt.from(100));
      expect(result.periods, hasLength(3));
      expect(
        result.periods.fold(BigInt.zero, (sum, p) => sum + p.totals.totalCents),
        BigInt.from(250),
      );
    },
  );
  test(
    'long custom range partitions all supported days into bounded intervals',
    () {
      final q = custom('1.1.1970', '31.12.2099', today: '31.12.2099');
      expect(q.periods, hasLength(24));
      expect(q.comparisonPrevious, isNull);
      expect(q.periods.first.firstDay, q.selected.firstDay);
      expect(q.periods.last.lastDay, q.selected.lastDay);
      expect(
        q.periods.fold(0, (sum, p) => sum + p.dayCount),
        q.selected.dayCount,
      );
      for (var i = 1; i < q.periods.length; i++) {
        expect(q.periods[i].firstDay, q.periods[i - 1].lastDay + 1);
      }
    },
  );
  test('one-day custom selection has no invented quantity or average', () {
    final q = custom('18.11.2026', '18.11.2026');
    expect(q.periods, hasLength(1));
    expect(range(q.comparisonPrevious!), ('17.11.2026', '17.11.2026'));
    expect(
      averageReceiptCents(SpendingDashboardBuilder(q).build().selected),
      isNull,
    );
  });
  test('custom bounds must both be day-precision, ordered and nonfuture', () {
    for (final dates in [
      ('19.11.2026', '18.11.2026'),
      ('18.11.2026', '23.11.2026'),
      ('18.11.2026 12:00', '19.11.2026'),
    ]) {
      expect(
        () => custom(dates.$1, dates.$2),
        throwsA(isA<ReceiptDataException>()),
      );
    }
    expect(
      () => SpendingDashboardQuery(
        unit: SpendingPeriodUnit.custom,
        anchor: day('18.11.2026'),
        today: day('18.11.2026'),
      ),
      throwsA(isA<ReceiptDataException>()),
    );
  });

  test('store nets reconcile selected totals; shares exclude zero and negative store nets', () {
    final a = ReceiptBranch(id: DurableId.generate(), name: 'A');
    final b = ReceiptBranch(id: DurableId.generate(), name: 'B');
    final c = ReceiptBranch(id: DurableId.generate(), name: 'C');
    final d = ReceiptBranch(id: DurableId.generate(), name: 'D');
    final result =
        (SpendingDashboardBuilder(query('18.11.2026'))
              ..add(receipt('18.11.2026', 1000, branch: a))
              ..add(receipt('18.11.2026', -200, branch: a))
              ..add(receipt('18.11.2026', 200, branch: b))
              ..add(receipt('18.11.2026', -100, branch: c))
              ..add(receipt('18.11.2026', 50, branch: d))
              ..add(receipt('18.11.2026', -50, branch: d))
              ..add(receipt('18.10.2026', 99999)))
            .build();
    expect(result.branches.map((b) => b.branch.name), ['A', 'B', 'D', 'C']);
    expect(result.branches.map((b) => b.totals.totalCents), [
      BigInt.from(800),
      BigInt.from(200),
      BigInt.zero,
      BigInt.from(-100),
    ]);
    expect(result.branches.map((b) => b.totals.receiptCount), [2, 1, 2, 1]);
    expect(result.branches.first.totals.negativeReceipts, 1);
    expect(result.selected.totalCents, BigInt.from(900));
    expect(result.positiveBranchNet, BigInt.from(1000));
    expect(result.negativeBranchNet, BigInt.from(-100));
    expect(
      result.positiveBranchNet + result.negativeBranchNet,
      result.selected.totalCents,
    );
    expect(
      result.branches.fold(0, (sum, b) => sum + b.totals.receiptCount),
      result.selected.receiptCount,
    );
    expect(() => result.branches.clear(), throwsUnsupportedError);
  });
  test('store identity, signed ranking and newest selected labels are deterministic', () {
    final id = DurableId.generate();
    ReceiptSnapshot named(int receiptId, String name, String date) {
      final row = ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'TEST',
        kind: LineKind.product,
        cents: BigInt.from(100),
      );
      return ReceiptSnapshot(
        id: DurableId.parse(
          '00000000-0000-4000-8000-${receiptId.toString().padLeft(12, '0')}',
        ),
        branch: ReceiptBranch(id: id, name: name),
        date: day(date),
        totalCents: row.cents,
        items: [row],
      );
    }

    final b = SpendingDashboardBuilder(query('18.11.2026'))
      ..add(named(99, 'SELECTED', '18.11.2026'))
      ..add(named(1, 'EARLIER TIE', '18.11.2026'))
      ..add(named(100, 'OLD', '1.11.2026'))
      ..add(named(101, 'FUTURE', '23.11.2026'))
      ..add(named(102, 'COMPARISON', '18.10.2026'));
    final before = b.build();
    expect(before.branches.single.branch.name, 'SELECTED');
    final other = ReceiptBranch(id: DurableId.generate(), name: 'SELECTED');
    b.add(receipt('18.11.2026', 300, branch: other));
    final after = b.build();
    expect(after.branches, hasLength(2));
    expect(
      after.branches.map((b) => b.branch.id.value),
      orderedEquals([id.value, other.id.value]..sort()),
    );
    expect(before.branches, hasLength(1));
  });
  test('store aggregation and share denominator remain exact beyond double precision', () {
    final a = ReceiptBranch(id: DurableId.generate(), name: 'A');
    final result =
        (SpendingDashboardBuilder(query('18.11.2026'))
              ..add(receipt('18.11.2026', 9007199254740993, branch: a))
              ..add(receipt('18.11.2026', 9007199254740994, branch: a))
              ..add(receipt('18.11.2026', -1)))
            .build();
    expect(result.positiveBranchNet, BigInt.parse('18014398509481987'));
    expect(result.negativeBranchNet, -BigInt.one);
    expect(result.branches.first.totals.totalCents, result.positiveBranchNet);
    expect(
      averageReceiptCents(result.branches.first.totals),
      BigInt.parse('9007199254740994'),
    );
  });
  test('only selected branches count toward the bound; a filtered store stays usable', () {
    final b = SpendingDashboardBuilder(query('18.11.2026'));
    for (var i = 0; i < 150; i++) {
      b.add(receipt('18.10.2026', 1));
    }
    for (var i = 0; i < 128; i++) {
      b.add(receipt('18.11.2026', 1));
    }
    expect(b.build().branches, hasLength(128));
    expect(
      () => b.add(receipt('18.11.2026', 1)),
      throwsA(
        isA<ReceiptDataException>().having((e) => e.code, 'code', 'groupLimit'),
      ),
    );
    final a = ReceiptBranch(id: DurableId.generate(), name: 'A');
    final selected = SpendingDashboardBuilder(
      query('18.11.2026', branch: a.id),
    );
    for (var i = 0; i < 150; i++) {
      selected.add(receipt('18.11.2026', 1));
    }
    selected.add(receipt('18.11.2026', -200, branch: a));
    expect(selected.build().branches.single.branch.id, a.id);
    expect(selected.build().positiveBranchNet, BigInt.zero);
    expect(selected.build().negativeBranchNet, BigInt.from(-200));
  });
}
