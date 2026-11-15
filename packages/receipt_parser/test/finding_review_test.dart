import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  test(
    'repeated categories retain separate evidence and original row indices',
    () {
      final page = OcrPage(500, 500, [
        OcrWord('FIRST', PixelBox(10, 100, 100, 120)),
        OcrWord('1, 00', PixelBox(400, 100, 460, 120)),
        OcrWord('SECOND', PixelBox(10, 150, 100, 170)),
        OcrWord('2, 00', PixelBox(400, 150, 460, 170)),
        OcrWord('YHTEENSÄ', PixelBox(10, 250, 200, 270)),
        OcrWord('3,00', PixelBox(400, 250, 460, 270)),
      ]);
      final draft = parseReceipt(page, itemTop: 50, priceColumnLeft: 350);
      final findings = draft.findings
          .where((f) => f.issue == ParseIssue.normalizedOcrAmount)
          .toList();
      expect(findings.length, 2);
      expect(findings.map((f) => f.rowIndex), [0, 1]);
      expect(findings[0].words.first.text, 'FIRST');
      expect(findings[1].words.first.text, 'SECOND');
      expect(() => findings[0].words.clear(), throwsUnsupportedError);
      expect(() => draft.findings.clear(), throwsUnsupportedError);
      expect(draft.issues, contains(ParseIssue.normalizedOcrAmount));
    },
  );

  test('resolution requires relevant valid fields and never clears unsupported types', () {
    final quantity = ParseFinding(ParseIssue.quantityMismatch, rowIndex: 0);
    expect(
      canResolveFinding(
        quantity,
        row: const ReviewRowInput('TEST', '2,00', LineKind.product),
      ),
      isFalse,
    );
    expect(
      canResolveFinding(
        quantity,
        row: const ReviewRowInput(
          'TEST',
          '2,00',
          LineKind.product,
          quantity: '2',
          rate: '1',
          unit: QuantityUnit.piece,
        ),
      ),
      isTrue,
    );
    expect(canResolveFinding(quantity), isFalse); // Removed row.
    final wrapped = ParseFinding(
      ParseIssue.wrappedNameNeedsReview,
      rowIndex: 0,
    );
    const row = ReviewRowInput('TEST', '2,00', LineKind.product);
    expect(canResolveFinding(wrapped, row: row), isFalse);
    expect(canResolveFinding(wrapped, row: row, nameHandled: true), isTrue);
    expect(
      canResolveFinding(ParseFinding(ParseIssue.missingTotal), total: '2'),
      isFalse,
    );
    expect(
      canResolveFinding(ParseFinding(ParseIssue.missingTotal), total: '2,00'),
      isTrue,
    );
    for (final issue in [
      ParseIssue.quantityWithoutProduct,
      ParseIssue.ambiguousGeometry,
      ParseIssue.discountNeedsReview,
      ParseIssue.unclassifiedRow,
      ParseIssue.invalidAmount,
    ]) {
      expect(
        canResolveFinding(
          ParseFinding(issue),
          row: row,
          total: '2,00',
          nameHandled: true,
        ),
        isFalse,
      );
    }
  });
}
