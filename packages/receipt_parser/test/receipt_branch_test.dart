import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

OcrWord word(String text, double x, double y, {double width = 200}) =>
    OcrWord(text, PixelBox(x, y, x + width, y + 16));

ReceiptDraft draft(List<OcrWord> header, {double slope = 0}) => parseReceipt(
  OcrPage(
    800,
    600,
    [
      ...header,
      word('19.11.2026', 20, 200),
      word('TEST PRODUCT', 20, 250),
      word('2,00', 650, 250, width: 70),
      word('YHTEENSÄ', 20, 300),
      word('2,00', 650, 300, width: 70),
      word('VISA', 20, 360),
      word('FOOTER STORE', 20, 400),
    ].reversed,
    baselineSlope: slope,
  ),
  itemTop: 230,
  priceColumnLeft: 600,
);

void main() {
  test(
    'reconstructs header words in geometry order with original evidence',
    () {
      final name = [
        word('TEST', 20, 20, width: 50),
        word('MARKET', 80, 20, width: 80),
        word('NORTH', 170, 20, width: 70),
      ];
      final parsed = draft(name);
      final candidate = parsed.branchCandidates.single;
      expect(candidate.name, 'TEST MARKET NORTH');
      expect(candidate.words, name);
      expect(() => candidate.words.clear(), throwsUnsupportedError);
      expect(() => parsed.branchCandidates.clear(), throwsUnsupportedError);
      expect(parsed.rows.single.name, 'TEST PRODUCT');
      expect(parsed.printedTotal, BigInt.from(200));
      expect(parsed.date.state, ReceiptDateState.valid);
      expect(parsed.evidenceCoverage!.complete, isTrue);
    },
  );

  test('adjacent name lines can match a full multiline branch name', () {
    final parsed = draft([word('TEST MARKET', 20, 20), word('NORTH', 20, 48)]);
    expect(parsed.branchCandidates.map((c) => c.name), [
      'TEST MARKET',
      'NORTH',
      'TEST MARKET NORTH',
    ]);
  });

  test('metadata interrupts names but does not hide a later shop heading', () {
    final parsed = draft([
      word('TEST COOPERATIVE', 20, 20),
      word('Y-1234567-8', 20, 45),
      word('TEST MARKET NORTH', 20, 70),
      word('PUH: 000 1234567', 20, 95),
      word('12345 TEST CITY', 20, 120),
      word('www.example.invalid', 20, 145),
      word('ASIAKASOMISTAJAN EDUT ON HUOMIOITU.', 20, 170, width: 500),
    ]);
    expect(parsed.branchCandidates.map((c) => c.name), [
      'TEST COOPERATIVE',
      'TEST MARKET NORTH',
    ]);
  });

  test('large gaps, side columns and overlapping words do not join names', () {
    expect(
      draft([
        word('TEST MARKET', 20, 20),
        word('NORTH', 20, 100),
        word('SIDE CITY', 300, 125),
      ]).branchCandidates.map((c) => c.name),
      ['TEST MARKET', 'NORTH', 'SIDE CITY'],
    );
    expect(
      draft([word('TEST', 20, 20), word('OVERLAP', 50, 20)]).branchCandidates,
      isEmpty,
    );
  });

  test('explicit inline phone and tax labels separate names from metadata', () {
    final shop = [
      word('TEST MARKET', 20, 70, width: 150),
      word('NORTH,', 180, 70, width: 80),
    ];
    final parsed = draft([
      word('TEST COMPANY', 20, 20, width: 200),
      word('Y-1234567-8', 240, 20),
      ...shop,
      word('PUH:', 280, 70, width: 50),
      word('0001234567', 350, 70),
    ]);
    expect(parsed.branchCandidates.map((c) => c.name), [
      'TEST COMPANY',
      'TEST MARKET NORTH',
    ]);
    expect(parsed.branchCandidates.last.words, shop);
    expect(parsed.branchCandidates.last.words.last.text, 'NORTH,');
  });

  test('shop names starting with metadata-like text are not labels', () {
    expect(
      draft([word('TELAKKA MARKET', 20, 20)]).branchCandidates.single.name,
      'TELAKKA MARKET',
    );
    expect(
      draft([word('Y-MARKET NORTH', 20, 20)]).branchCandidates.single.name,
      'Y-MARKET NORTH',
    );
  });

  test(
    'crossing item boundaries and body/footer words are never candidates',
    () {
      expect(
        draft([word('CROSSING STORE', 20, 220)]).branchCandidates,
        isEmpty,
      );
      expect(draft([]).branchCandidates, isEmpty);
    },
  );

  test(
    'keeps diacritics and punctuation and accounts for the measured skew',
    () {
      final parsed = draft([
        word('TEST', 20, 32, width: 50),
        word('MÄRKET,', 300, 18, width: 80),
      ], slope: -.05);
      expect(parsed.branchCandidates.single.name, 'TEST MÄRKET,');
    },
  );
}
