import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  final words = [OcrWord('SOURCE', PixelBox(1, 1, 80, 20))];
  const product = ReviewRowInput(
    'MILK',
    '2,00',
    LineKind.product,
    quantity: '2',
    rate: '1',
    unit: QuantityUnit.piece,
  );
  const discount = ReviewRowInput('ALE', '-0,50', LineKind.discount);

  test('orphan quantity requires an explicit valid product with matched arithmetic', () {
    final finding = ParseFinding(
      ParseIssue.quantityWithoutProduct,
      words: words,
    );
    expect(
      canResolveRelationship(
        finding,
        ReviewRelationshipKind.quantity,
        target: product,
      ),
      isTrue,
    );
    for (final target in [
      null,
      discount,
      const ReviewRowInput('MILK', '2,00', LineKind.product),
      const ReviewRowInput(
        'MILK',
        '2,00',
        LineKind.product,
        quantity: '3',
        rate: '1',
        unit: QuantityUnit.piece,
      ),
      const ReviewRowInput(
        '',
        '2,00',
        LineKind.product,
        quantity: '2',
        rate: '1',
        unit: QuantityUnit.piece,
      ),
    ]) {
      expect(
        canResolveRelationship(
          finding,
          ReviewRelationshipKind.quantity,
          target: target,
        ),
        isFalse,
      );
    }
    expect(
      canResolveRelationship(
        ParseFinding(ParseIssue.quantityWithoutProduct),
        ReviewRelationshipKind.quantity,
        target: product,
      ),
      isFalse,
    );
  });

  test('explanatory prices cannot become posted discount relationships', () {
    final finding = ParseFinding(
      ParseIssue.discountNeedsReview,
      words: words,
      discountKind: DiscountFindingKind.explanatoryPrice,
    );
    expect(
      canResolveRelationship(
        finding,
        ReviewRelationshipKind.explanatoryPrice,
        target: product,
      ),
      isTrue,
    );
    expect(
      canResolveRelationship(
        finding,
        ReviewRelationshipKind.explanatoryPrice,
        target: discount,
      ),
      isFalse,
    );
    expect(
      canResolveRelationship(
        finding,
        ReviewRelationshipKind.productDiscount,
        source: discount,
        target: product,
      ),
      isFalse,
    );
    expect(
      canResolveRelationship(
        finding,
        ReviewRelationshipKind.receiptDiscount,
        source: discount,
      ),
      isFalse,
    );
  });

  test(
    'posted discount preserves signed contribution and requires valid scope',
    () {
      final finding = ParseFinding(
        ParseIssue.discountNeedsReview,
        rowIndex: 1,
        words: words,
        discountKind: DiscountFindingKind.postedDiscount,
      );
      expect(
        canResolveRelationship(
          finding,
          ReviewRelationshipKind.productDiscount,
          source: discount,
          target: product,
        ),
        isTrue,
      );
      expect(
        canResolveRelationship(
          finding,
          ReviewRelationshipKind.receiptDiscount,
          source: discount,
        ),
        isTrue,
      );
      expect(
        canResolveRelationship(
          finding,
          ReviewRelationshipKind.receiptDiscount,
          source: discount,
          target: product,
        ),
        isFalse,
      );
      for (final source in [
        null,
        product,
        const ReviewRowInput('ALE', '0,50', LineKind.discount),
        const ReviewRowInput('ALE', '0,00', LineKind.discount),
      ]) {
        expect(
          canResolveRelationship(
            finding,
            ReviewRelationshipKind.productDiscount,
            source: source,
            target: product,
          ),
          isFalse,
        );
      }
      expect(
        canResolveRelationship(
          finding,
          ReviewRelationshipKind.productDiscount,
          source: discount,
        ),
        isFalse,
      );
    },
  );

  test(
    'parser preserves orphan candidate and separates both kinds of price text',
    () {
      final page = OcrPage(500, 500, [
        OcrWord('2 kpl 1,00 EUR/kpl', PixelBox(10, 60, 280, 80)),
        OcrWord('MILK', PixelBox(10, 100, 120, 120)),
        OcrWord('2,00', PixelBox(400, 100, 480, 120)),
        OcrWord('NORM.', PixelBox(10, 150, 120, 170)),
        OcrWord('2,50', PixelBox(400, 150, 480, 170)),
        OcrWord('ALE', PixelBox(10, 200, 120, 220)),
        OcrWord('-0,50', PixelBox(400, 200, 480, 220)),
        OcrWord('YHTEENSÄ', PixelBox(10, 300, 250, 320)),
        OcrWord('1,50', PixelBox(400, 300, 480, 320)),
      ]);
      final draft = parseReceipt(page, itemTop: 40, priceColumnLeft: 350);
      expect(draft.totals.state, TotalState.matched);
      expect(draft.rows.map((r) => r.cents), [
        BigInt.from(200),
        BigInt.from(-50),
      ]);
      expect(draft.rows.first.quantity, isNull);
      final orphan = draft.findings.first;
      expect(orphan.issue, ParseIssue.quantityWithoutProduct);
      expect(orphan.rowIndex, isNull);
      expect(orphan.quantityCandidate!.quantity.value, BigInt.from(2000000));
      expect(orphan.quantityCandidate!.quantity.unit, QuantityUnit.piece);
      expect(orphan.quantityCandidate!.rateMicros, BigInt.from(1000000));
      final discounts = draft.findings
          .where((f) => f.issue == ParseIssue.discountNeedsReview)
          .toList();
      expect(discounts.map((f) => f.discountKind), [
        DiscountFindingKind.explanatoryPrice,
        DiscountFindingKind.postedDiscount,
      ]);
      expect(discounts.map((f) => f.rowIndex), [null, 1]);
      expect(discounts.first.words.map((w) => w.text), ['NORM.', '2,50']);
    },
  );
}
