import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  ReviewValidation validate({
    String date = '15.11.2026',
    String amount = '1,00',
    String total = '1,00',
    bool reviewed = true,
    bool branch = true,
    bool issues = false,
    List<ReviewRowInput>? rows,
  }) => ReviewValidation(
    branch: 'TEST BRANCH',
    branchConfirmed: branch,
    dateText: date,
    totalText: total,
    reviewed: reviewed,
    hasUnresolvedParserIssues: issues,
    rows: rows ?? [ReviewRowInput('TEST', amount, LineKind.product)],
  );
  test('reconciliation alone never completes review', () {
    expect(validate(reviewed: false).complete, isFalse);
    expect(validate(branch: false).complete, isFalse);
    expect(validate(issues: true).complete, isFalse);
    expect(validate().complete, isTrue);
  });
  test('malformed rows cannot hide behind a matching partial sum', () {
    final result = validate(
      rows: const [
        ReviewRowInput('TEST', '1,00', LineKind.product),
        ReviewRowInput('BAD', 'I,00', LineKind.product),
      ],
    );
    expect(result.totals.state, TotalState.matched);
    expect(result.totalsValid, isFalse);
    expect(result.complete, isFalse);
    expect(validate(rows: []).complete, isFalse);
    expect(validate(total: '1,01').totals.difference, BigInt.from(-1));
  });
  test('date ambiguity and positive discounts block completion', () {
    expect(validate(date: '25.10.2026 03:30').complete, isFalse);
    expect(validate(date: '29.3.2026 03:30').complete, isFalse);
    expect(validate(date: '31.2.2026').complete, isFalse);
    expect(
      validate(rows: const [ReviewRowInput('ALE', '1,00', LineKind.discount)])
          .complete,
      isFalse,
    );
    expect(
      validate(
        total: '-1,00',
        rows: const [ReviewRowInput('RETURN', '-1,00', LineKind.deposit)],
      ).complete,
      isTrue,
    );
  });
  test('format cents without float rounding', () {
    expect(formatCents(BigInt.from(-1)), '-0,01');
    expect(formatCents(BigInt.from(100)), '1,00');
  });
}
