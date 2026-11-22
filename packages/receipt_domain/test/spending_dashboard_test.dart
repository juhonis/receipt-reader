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
    expect(year.periods, hasLength(12));
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
      result.periods[result.periods.length - 2].totals.totalCents,
      BigInt.from(900),
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
      expect(q.periods, hasLength(1));
      expect(range(q.selected), ('1.1.1970', '4.1.1970'));
      expect(q.comparisonPrevious, isNull);
      expect(
        query('5.1.1970', unit: SpendingPeriodUnit.week).periods,
        hasLength(2),
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
}
