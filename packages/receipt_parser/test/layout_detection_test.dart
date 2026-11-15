import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

OcrPage page({
  bool date = true,
  bool total = true,
  bool extraTotal = false,
  bool extraPrice = false,
}) {
  OcrWord word(String text, double x, double y, double width) =>
      OcrWord(text, PixelBox(x, y, x + width, y + 12));
  return OcrPage(500, 500, [
    if (date) word('15.11.2026', 20, 20, 100),
    word('MISSING PRICE PRODUCT', 20, 55, 200),
    word('TEST ONE', 20, 80, 150),
    word('1,00', 400, 80, 40),
    if (extraPrice) word('0,50', 300, 80, 40),
    word('TEST TWO', 20, 110, 150),
    word('2,00', 400, 110, 40),
    if (total) ...[word('YHTEENSÄ', 20, 150, 100), word('3,00', 400, 150, 40)],
    if (extraTotal) ...[
      word('YHTEENSA', 20, 175, 100),
      word('4,00', 400, 175, 40),
    ],
    word('BONUSTA', 20, 200, 100),
    word('3,00', 400, 200, 40),
    word('YHTEENSÄ', 20, 230, 100),
    word('3,00', 400, 230, 40),
  ]);
}

void main() {
  test('reconstructs a date split across OCR words', () {
    final original = page();
    final input = OcrPage(500, 500, [
      ...original.words.where((w) => w.text != '15.11.2026'),
      OcrWord('15.11.', PixelBox(20, 20, 75, 32)),
      OcrWord('2026', PixelBox(80, 20, 120, 32)),
    ]);
    expect(proposeLayout(input).available, isTrue);
  });
  test('proposes boundaries without dropping an unpriced first row', () {
    final input = page();
    final proposal = proposeLayout(input);
    expect(proposal.available, isTrue);
    expect(proposal.requiresReview, isTrue);
    expect(proposal.itemTop, lessThan(55));
    expect(proposal.priceColumnLeft, lessThan(400));
    final draft = parseReceipt(
      input,
      itemTop: proposal.itemTop!,
      priceColumnLeft: proposal.priceColumnLeft!,
    );
    expect(draft.rows, hasLength(2));
    expect(draft.notes, contains('MISSING PRICE PRODUCT'));
    expect(draft.issues, contains(ParseIssue.unclassifiedRow));
    expect(draft.totals.state, TotalState.matched);
  });
  test(
    'abstains on absent anchors, competing totals, and extra decimal columns',
    () {
      expect(
        proposeLayout(page(date: false)).issues,
        contains(LayoutIssue.missingHeaderDate),
      );
      expect(
        proposeLayout(page(total: false)).issues,
        contains(LayoutIssue.missingTotal),
      );
      expect(
        proposeLayout(page(extraTotal: true)).issues,
        contains(LayoutIssue.ambiguousTotal),
      );
      expect(
        proposeLayout(page(extraPrice: true)).issues,
        contains(LayoutIssue.ambiguousColumn),
      );
    },
  );
  test('amount values never determine geometry proposals', () {
    final original = page();
    final changed = OcrPage(
      500,
      500,
      original.words.map(
        (w) => OcrWord(w.text == '3,00' ? '9,99' : w.text, w.box),
      ),
    );
    final a = proposeLayout(original), b = proposeLayout(changed);
    expect(a.itemTop, b.itemTop);
    expect(a.priceColumnLeft, b.priceColumnLeft);
  });
}
