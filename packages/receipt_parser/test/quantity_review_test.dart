import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  ReviewRowInput row(
    String quantity,
    String rate,
    String amount, [
    QuantityUnit unit = QuantityUnit.kg,
  ]) => ReviewRowInput(
    'TEST',
    amount,
    LineKind.product,
    quantity: quantity,
    rate: rate,
    unit: unit,
  );

  test(
    'quantity validation uses exact rounding and preserves signed returns',
    () {
      expect(
        row('0,125', '1,00', '0,13').quantityState,
        QuantityReviewState.matched,
      );
      expect(
        row('-0,125', '1,00', '-0,13').quantityState,
        QuantityReviewState.matched,
      );
      expect(
        row('0,125', '1,00', '0,12').quantityState,
        QuantityReviewState.mismatched,
      );
      expect(
        row('1,000001', '1,000001', '1,00').quantityState,
        QuantityReviewState.matched,
      );
      expect(formatFixed(BigInt.from(-125000), 6), '-0,125');
      expect(formatFixed(BigInt.from(1000000), 6), '1');
    },
  );

  test('missing, malformed and excessive-precision quantities cannot pass', () {
    for (final input in [
      row('', '1', '1,00'),
      row('1', '', '1,00'),
      row('0', '1', '0,00'),
      row('1', '-1', '-1,00'),
      row('1.0000001', '1', '1,00'),
      row('1', '1', '1,00', QuantityUnit.unknown),
    ]) {
      expect(input.quantityState, QuantityReviewState.invalid);
    }
    expect(
      const ReviewRowInput('TEST', '1,00', LineKind.product).quantityState,
      QuantityReviewState.absent,
    );
  });

  test('matching receipt sum cannot hide invalid quantity arithmetic', () {
    final result = ReviewValidation(
      branch: 'TEST',
      dateText: '15.11.2026',
      totalText: '1,00',
      rows: [row('2', '1', '1,00')],
      branchConfirmed: true,
      reviewed: true,
    );
    expect(result.totalsValid, isTrue);
    expect(result.quantitiesValid, isFalse);
    expect(result.complete, isFalse);
  });

  test('row evidence retains quantity words and is immutable', () {
    final words = [
      OcrWord('MILK', PixelBox(10, 100, 100, 120)),
      OcrWord('2,00', PixelBox(400, 100, 450, 120)),
      OcrWord('2 kpl 1,00 EUR/kpl', PixelBox(10, 130, 300, 150)),
      OcrWord('YHTEENSÄ', PixelBox(10, 200, 200, 220)),
      OcrWord('2,00', PixelBox(400, 200, 450, 220)),
    ];
    final draft = parseReceipt(
      OcrPage(500, 500, words),
      itemTop: 50,
      priceColumnLeft: 350,
    );
    expect(draft.rows.single.quantityMatches, isTrue);
    expect(draft.rowEvidence.single, words.take(3));
    expect(() => draft.rowEvidence.single.clear(), throwsUnsupportedError);
    expect(() => draft.rowEvidence.clear(), throwsUnsupportedError);
  });
}
