import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

// Reuse invented domain snapshots; duplicate matching never changes either one.
void main() {
  ReceiptSnapshot receipt(
    int number,
    String date, {
    String branch = 'TEST BRANCH',
    int cents = 200,
  }) => ReceiptSnapshot(
    id: id(number),
    branch: ReceiptBranch(id: id(number + 100), name: branch),
    date: StoredReceiptDate.parse(date),
    totalCents: BigInt.from(cents),
    items: [
      ReceiptItemSnapshot(
        id: id(number + 200),
        name: 'TEST ITEM',
        kind: LineKind.product,
        cents: BigInt.from(cents),
      ),
    ],
  );
  test('same printed minute warns despite changed store, total or seconds', () {
    final a = receipt(1, '19.11.2026 12:34:05');
    expect(
      receiptDuplicateReason(
        a,
        receipt(2, '19.11.2026 12:34:59', branch: 'OTHER BRANCH', cents: 300),
      ),
      ReceiptDuplicateReason.sameMinute,
    );
    expect(receiptDuplicateReason(a, receipt(2, '19.11.2026 12:35')), isNull);
    expect(receiptDuplicateReason(a, receipt(2, '20.11.2026 12:34')), isNull);
    expect(receiptDuplicateReason(a, a), isNull);
  });
  test('missing time requires the same branch and amount, with conservative name normalization', () {
    final a = receipt(1, '19.11.2026');
    expect(
      receiptDuplicateReason(
        a,
        receipt(2, '19.11.2026', branch: 'test   branch'),
      ),
      ReceiptDuplicateReason.sameDayBranchTotal,
    );
    expect(
      receiptDuplicateReason(a, receipt(2, '19.11.2026 12:34')),
      ReceiptDuplicateReason.sameDayBranchTotal,
    );
    expect(
      receiptDuplicateReason(
        a,
        receipt(2, '19.11.2026', branch: 'OTHER BRANCH'),
      ),
      isNull,
    );
    expect(
      receiptDuplicateReason(a, receipt(2, '19.11.2026', cents: 300)),
      isNull,
    );
    expect(
      receiptDuplicateReason(
        a,
        receipt(2, '19.11.2026', branch: 'TEST-BRANCH'),
      ),
      isNull,
    );
  });
}
