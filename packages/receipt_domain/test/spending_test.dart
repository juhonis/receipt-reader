import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  ReceiptSnapshot receipt({
    ReceiptBranch? branch,
    String date = '29.2.2024',
    int cents = 100,
  }) => ReceiptSnapshot(
    id: DurableId.generate(),
    branch: branch ?? ReceiptBranch(id: DurableId.generate(), name: 'TEST'),
    date: StoredReceiptDate.parse(date),
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
  test('empty and immutable output, leap days and civil month boundaries', () {
    final builder = SpendingSummaryBuilder();
    expect(builder.build().totals.totalCents, BigInt.zero);
    final branch = ReceiptBranch(id: DurableId.generate(), name: 'OLD');
    builder.add(receipt(branch: branch));
    builder.add(
      receipt(
        branch: ReceiptBranch(id: branch.id, name: 'NEW'),
        date: '1.3.2024 00:00:00',
        cents: -50,
      ),
    );
    final result = builder.build();
    expect(result.totals.receiptCount, 2);
    expect(result.totals.totalCents, BigInt.from(50));
    expect(result.totals.negativeReceipts, 1);
    expect(result.branches.single.branch.name, 'NEW');
    expect(result.months.map((m) => m.month), [3, 2]);
    expect(() => result.months.clear(), throwsUnsupportedError);
    builder.add(receipt(branch: branch, date: '1.1.2024', cents: 0));
    expect(result.totals.receiptCount, 2);
    expect(builder.build().branches.single.branch.name, 'NEW');
  });
  test('branch limit fails explicitly rather than dropping receipts', () {
    final builder = SpendingSummaryBuilder();
    for (var i = 0; i < 128; i++) {
      builder.add(receipt());
    }
    expect(
      () => builder.add(receipt()),
      throwsA(
        isA<ReceiptDataException>().having((e) => e.code, 'code', 'groupLimit'),
      ),
    );
  });
}
