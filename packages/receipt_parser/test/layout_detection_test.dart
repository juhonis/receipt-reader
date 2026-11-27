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

// Invented amounts and coordinates. Exercise OCR tokenization without using
// private receipt text, prices or geometry as a public fixture.
OcrPage fragmentedPage({int style = 0, bool distant = false}) {
  final original = page();
  final words = <OcrWord>[];
  for (final word in original.words) {
    if (!RegExp(r'^\d,00$').hasMatch(word.text)) {
      words.add(word);
      continue;
    }
    final digit = word.text[0], y = word.box.top;
    final parts = switch (style) {
      1 => [(digit, 400.0, 410.0), (',00', 415.0, 440.0)],
      2 => [(digit, 400.0, 409.0), (',', 412.0, 418.0), ('00', 423.0, 440.0)],
      _ => [
        ('$digit,', 400.0, 418.0),
        ('00', distant ? 455.0 : 423.0, 440.0 + (distant ? 32 : 0)),
      ],
    };
    for (final (text, left, right) in parts) {
      words.add(OcrWord(text, PixelBox(left, y, right, y + 12)));
    }
  }
  return OcrPage(500, 500, words.reversed);
}

OcrPage multilinePage({bool interrupted = false, bool mismatch = false}) {
  final words = <OcrWord>[];
  const slope = -.04;
  void word(String text, double x, double y, double width) {
    final skew = slope * (x + width / 2 - 550);
    words.add(OcrWord(text, PixelBox(x, y + skew, x + width, y + skew + 20)));
  }

  void amount(String integer, String fraction, double y) {
    word('$integer,', 620, y, 18);
    word(fraction, 644, y, 22);
  }

  word('18.11.2026', 230, 40, 120);
  word('09:15', 390, 40, 65);
  word('TEST WRAPPED', 230, 85, 170);
  word('PACKS 8KPL', 230, 115, 160);
  amount('3', '60', 115);
  word('3', 250, 147, 15);
  word('KPL', 275, 147, 40);
  word('1,', 420, 147, 18);
  word('20', 444, 147, 22);
  word('€/KPL', 480, 147, 70);
  word('TEST ROOTS 400G', 230, 195, 220);
  amount('1', mismatch ? '09' : '08', 195);
  if (interrupted) word('UNPRICED OTHER PRODUCT', 230, 226, 280);
  final continuationY = interrupted ? 259.0 : 227.0;
  word('0,', 250, continuationY, 18);
  word('450', 274, continuationY, 35);
  word('KG', 320, continuationY, 30);
  word('2,', 420, continuationY, 18);
  word('40', 444, continuationY, 22);
  word('€/KG', 480, continuationY, 60);
  word('YHTEENSÄ', 230, 320, 150);
  amount('4', mismatch ? '69' : '68', 320);
  word('VISA', 230, 360, 65);
  amount('4', '68', 360);
  return OcrPage(1100, 800, words.reversed, baselineSlope: slope);
}

ReceiptDraft proposedDraft(OcrPage input) {
  final proposal = proposeLayout(input);
  expect(proposal.available, isTrue);
  return parseReceipt(
    input,
    itemTop: proposal.itemTop!,
    priceColumnLeft: proposal.priceColumnLeft!,
  );
}

void main() {
  for (final style in [0, 1, 2]) {
    test(
      'split item and total decimals propose and parse consistently: $style',
      () {
        final input = fragmentedPage(style: style);
        final draft = proposedDraft(input);
        expect(draft.rows.map((r) => r.cents.toInt()), [100, 200]);
        expect(draft.printedTotal, BigInt.from(300));
        expect(draft.evidenceCoverage!.complete, isTrue);
        expect(draft.notes, contains('MISSING PRICE PRODUCT'));
        expect(
          draft.rowEvidence.expand((r) => r).every(input.words.contains),
          isTrue,
        );
      },
    );
  }
  test('a separated currency suffix does not move the amount alignment', () {
    final source = fragmentedPage();
    final input = OcrPage(500, 500, [
      ...source.words,
      OcrWord('€', PixelBox(465, 150, 477, 162)),
    ]);
    expect(
      proposeLayout(input).priceColumnLeft,
      proposeLayout(source).priceColumnLeft,
    );
    expect(proposedDraft(input).printedTotal, BigInt.from(300));
  });
  test('distant fragments and corrupted digits cannot anchor a layout', () {
    expect(proposeLayout(fragmentedPage(distant: true)).available, isFalse);
    final source = fragmentedPage();
    final corrupt = OcrPage(
      500,
      500,
      source.words.map(
        (w) => OcrWord(w.text == '1,' || w.text == '2,' ? 'I,' : w.text, w.box),
      ),
    );
    expect(proposeLayout(corrupt).available, isFalse);
  });
  test('split decimals in a second column remain ambiguous', () {
    final source = fragmentedPage();
    final input = OcrPage(500, 500, [
      ...source.words,
      OcrWord('0,', PixelBox(300, 80, 318, 92)),
      OcrWord('50', PixelBox(323, 80, 340, 92)),
    ]);
    expect(proposeLayout(input).issues, contains(LayoutIssue.ambiguousColumn));
  });
  test('split amounts do not use reconciliation to select a layout', () {
    final source = fragmentedPage();
    final changed = OcrPage(
      500,
      500,
      source.words.map((w) => OcrWord(w.text == '3,' ? '9,' : w.text, w.box)),
    );
    final originalLayout = proposeLayout(source),
        changedLayout = proposeLayout(changed);
    expect(changedLayout.itemTop, originalLayout.itemTop);
    expect(changedLayout.priceColumnLeft, originalLayout.priceColumnLeft);
    expect(proposedDraft(changed).totals.state, TotalState.mismatched);
  });
  for (final sign in ['-', '−', '—']) {
    test('a separate printed sign stays inside the amount column: $sign', () {
      final source = fragmentedPage();
      final input = OcrPage(500, 500, [
        ...source.words.map(
          (w) => OcrWord(w.text == '3,' ? '1,' : w.text, w.box),
        ),
        OcrWord(sign, PixelBox(387, 80, 395, 92)),
      ]);
      expect(proposeLayout(input).priceColumnLeft, lessThan(387));
      final draft = proposedDraft(input);
      expect(draft.rows.map((r) => r.cents.toInt()), [-100, 200]);
      expect(draft.totals.state, TotalState.matched);
      expect(draft.rows.first.name, 'TEST ONE');
      expect(draft.rowEvidence.first.map((w) => w.text), contains(sign));
      if (sign == '—')
        expect(draft.issues, contains(ParseIssue.normalizedOcrAmount));
    });
  }
  test(
    'automatic layout preserves multiline identities, rates and source words',
    () {
      final input = multilinePage();
      final proposal = proposeLayout(input);
      expect(proposal.priceColumnLeft, lessThan(620));
      expect(proposal.priceColumnLeft, greaterThan(550));
      final draft = proposedDraft(input);
      expect(draft.rows.map((r) => (r.name, r.cents.toInt())), [
        ('PACKS 8KPL', 360),
        ('TEST ROOTS 400G', 108),
      ]);
      expect(draft.wrappedNames.single.proposedName, 'TEST WRAPPED PACKS 8KPL');
      expect(draft.issues, contains(ParseIssue.wrappedNameNeedsReview));
      expect(draft.rows.map((r) => r.quantity!.value.toInt()), [
        3000000,
        450000,
      ]);
      expect(draft.rows.map((r) => r.quantity!.unit), [
        QuantityUnit.piece,
        QuantityUnit.kg,
      ]);
      expect(draft.rows.map((r) => r.rateMicros!.toInt()), [1200000, 2400000]);
      expect(draft.rows.map((r) => r.quantityMatches), [true, true]);
      expect(draft.totals.state, TotalState.matched);
      expect(draft.date.state, ReceiptDateState.valid);
      expect(
        draft.rowEvidence[0].map((w) => w.text),
        containsAll(['TEST WRAPPED', '3', '€/KPL']),
      );
      expect(
        draft.rowEvidence[1].map((w) => w.text),
        containsAll(['450', '€/KG']),
      );
      expect(
        draft.rowEvidence.expand((r) => r).every(input.words.contains),
        isTrue,
      );
      expect(draft.evidenceCoverage!.complete, isTrue);
    },
  );
  test(
    'unpriced intervening products prevent cross-product quantity attachment',
    () {
      final draft = proposedDraft(multilinePage(interrupted: true));
      expect(draft.rows.first.quantityMatches, isTrue);
      expect(draft.rows.last.quantity, isNull);
      expect(draft.issues, contains(ParseIssue.quantityWithoutProduct));
      expect(draft.notes, contains('UNPRICED OTHER PRODUCT'));
      expect(draft.rows, hasLength(2));
    },
  );
  test('a matching sum cannot hide a second-line quantity mismatch', () {
    final draft = proposedDraft(multilinePage(mismatch: true));
    expect(draft.totals.state, TotalState.matched);
    expect(draft.rows.last.cents, BigInt.from(109));
    expect(draft.rows.last.quantityMatches, isFalse);
    expect(draft.issues, contains(ParseIssue.quantityMismatch));
  });
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
