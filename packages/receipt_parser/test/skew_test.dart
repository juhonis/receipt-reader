import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'parser_test.dart' show fixture;

Map<String, dynamic> skewFixture(
  double slope, {
  int count = 6,
  bool missing = false,
}) {
  Map<String, Object> word(String text, double x, double y, double width) {
    final centerY = y + slope * (x + width / 2);
    return {
      'text': text,
      'box': {
        'left': x,
        'right': x + width,
        'top': centerY - 6,
        'bottom': centerY + 6,
      },
    };
  }

  return {
    'schemaVersion': 1,
    'image': {'width': 500, 'height': 600, 'orientation': 'upright'},
    'blocks': [
      for (var i = 0; i < count; i++)
        {
          'lines': [
            {
              'words': [
                word('TEST', 20, 100 + i * 30, 45),
                word('PRODUCT', 150, 100 + i * 30, 80),
              ],
            },
          ],
        },
      {
        'lines': [
          for (var i = 0; i < count; i++)
            if (!(missing && i == 2))
              {
                'words': [word('1,00', 400, 100 + i * 30, 40)],
              },
        ],
      },
      {
        'lines': [
          {
            'words': [word('YHTEENSÄ', 20, 100 + count * 30, 100)],
          },
        ],
      },
      {
        'lines': [
          {
            'words': [word('$count,00', 400, 100 + count * 30, 40)],
          },
        ],
      },
    ],
  };
}

ReceiptDraft parse(OcrPage page) =>
    parseReceipt(page, itemTop: 50, priceColumnLeft: 350);

void main() {
  test('both skew directions align independent blocks without changing coordinates', () {
    for (final slope in [-.06, .06]) {
      final page = OcrPage.fromJson(skewFixture(slope));
      expect(page.baselineSlope, closeTo(slope, .00001));
      final topBefore = page.words.first.box.top;
      final draft = parse(page);
      expect(draft.rows, hasLength(6));
      expect(draft.rows.every((r) => r.name == 'TEST PRODUCT'), isTrue);
      expect(draft.rows.map((r) => r.cents), everyElement(BigInt.from(100)));
      expect(draft.totals.state, TotalState.matched);
      expect(draft.issues, contains(ParseIssue.skewAdjusted));
      expect(page.words.first.box.top, topBefore);
    }
  });

  test('missing price remains unresolved instead of borrowing a neighbouring price', () {
    final result = parse(OcrPage.fromJson(skewFixture(.06, missing: true)));
    expect(result.rows, hasLength(5));
    expect(result.totals.difference, BigInt.from(-100));
    expect(result.issues, contains(ParseIssue.unclassifiedRow));
  });

  test('sparse or out-of-range skew evidence is not used', () {
    expect(OcrPage.fromJson(skewFixture(.06, count: 3)).baselineSlope, 0);
    expect(OcrPage.fromJson(skewFixture(.2)).baselineSlope, 0);
    final mixed = skewFixture(.06);
    final opposite = skewFixture(-.06);
    for (var i = 0; i < 3; i++) {
      (mixed['blocks'] as List<dynamic>)[i] =
          (opposite['blocks'] as List<dynamic>)[i];
    }
    expect(OcrPage.fromJson(mixed).baselineSlope, 0);
    expect(
      () => OcrPage(500, 500, [], baselineSlope: double.nan),
      throwsFormatException,
    );
  });

  test(
    'limited total aliases are flagged and never normalized in product names',
    () {
      for (final total in ['YHTEENSA', 'YHTEENSĂ']) {
        final result = parseReceipt(
          fixture([
            ('YHTEENSA PRODUCT', '1,00'),
            (total, '1,00'),
            ('BONUSTA KERRYTTÄVÄT OSTOT', '1,00'),
            ('YHTEENSÄ', '9,99'),
          ]),
          itemTop: 30,
          priceColumnLeft: 300,
        );
        expect(result.rows.single.name, 'YHTEENSA PRODUCT');
        expect(result.printedTotal, BigInt.from(100));
        expect(result.issues, contains(ParseIssue.totalLabelNeedsReview));
      }
      final ambiguous = parseReceipt(
        fixture([('TEST', '1,00'), ('YHTEENSA', '1,00'), ('YHTEENSÄ', '2,00')]),
        itemTop: 30,
        priceColumnLeft: 300,
      );
      expect(ambiguous.printedTotal, isNull);
      expect(ambiguous.issues, contains(ParseIssue.ambiguousTotal));
    },
  );

  test('OCR decimal whitespace is flagged without guessing digits', () {
    final result = parseReceipt(
      fixture([('TEST', '1, 00'), ('YHTEENSÄ', '1 ,00')]),
      itemTop: 30,
      priceColumnLeft: 300,
    );
    expect(result.totals.state, TotalState.matched);
    expect(result.issues, contains(ParseIssue.normalizedOcrAmount));
    for (final invalid in ['1 2,34', 'I,00', '1,0O']) {
      final bad = parseReceipt(
        fixture([('TEST', invalid), ('YHTEENSÄ', '1,00')]),
        itemTop: 30,
        priceColumnLeft: 300,
      );
      expect(bad.rows, isEmpty);
      expect(bad.issues, contains(ParseIssue.invalidAmount));
    }
  });

  test('separate digit tokens cannot become a fabricated amount', () {
    for (final left in [375.0, 420.0]) {
      final result = parse(
        OcrPage(500, 600, [
          OcrWord('TEST', PixelBox(20, 100, 100, 112)),
          OcrWord('1', PixelBox(360, 100, 370, 112)),
          OcrWord('2,34', PixelBox(left, 100, left + 40, 112)),
          OcrWord('YHTEENSÄ', PixelBox(20, 150, 120, 162)),
          OcrWord('12,34', PixelBox(400, 150, 460, 162)),
        ]),
      );
      expect(result.rows, isEmpty);
      expect(result.totals.state, TotalState.mismatched);
    }
  });
}
