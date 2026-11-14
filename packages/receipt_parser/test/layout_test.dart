import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'parser_test.dart' show fixture;

ReceiptDraft parse(OcrPage page) =>
    parseReceipt(page, itemTop: 30, priceColumnLeft: 300);

void main() {
  test('date words are reconstructed from header geometry only', () {
    final body = fixture([
      ('TEST', '1,00'),
      ('YHTEENSÄ', '1,00'),
      ('VISA 1.1.2025 14:00', '1,00'),
    ]);
    final result = parse(
      OcrPage(body.width, body.height, [
        ...body.words,
        OcrWord('12:34', PixelBox(230, 5, 280, 17)),
        OcrWord('15.7.2026', PixelBox(100, 5, 200, 17)),
        OcrWord('KASSA', PixelBox(20, 5, 80, 17)),
      ]),
    );
    expect(result.date.utcInstant, DateTime.utc(2026, 7, 15, 9, 34));
    expect(result.rows.single.name, 'TEST');
    expect(parse(body).date.state, ReceiptDateState.missing);
  });

  test('wrapped name proposal never silently changes financial rows', () {
    final result = parse(
      fixture([
        ('LONG TEST DESCRIPTION', ''),
        ('CONTINUED', '2,00'),
        ('YHTEENSÄ', '2,00'),
      ]),
    );
    expect(result.wrappedNames.single.rowIndex, 0);
    expect(
      result.wrappedNames.single.proposedName,
      'LONG TEST DESCRIPTION CONTINUED',
    );
    expect(result.rows.single.name, 'CONTINUED');
    expect(result.notes, contains('LONG TEST DESCRIPTION'));
    expect(
      result.issues,
      containsAll([
        ParseIssue.unclassifiedRow,
        ParseIssue.wrappedNameNeedsReview,
      ]),
    );
    expect(result.totals.state, TotalState.matched);
  });

  test(
    'description cannot attach across discount notes or large vertical gaps',
    () {
      final interrupted = parse(
        fixture([
          ('LOOSE NAME', ''),
          ('KAMPANJA', '-0,50'),
          ('PRODUCT', '2,00'),
          ('YHTEENSÄ', '2,00'),
        ]),
      );
      expect(interrupted.wrappedNames, isEmpty);
      final page = fixture([
        ('LOOSE NAME', ''),
        ('PRODUCT', '2,00'),
        ('YHTEENSÄ', '2,00'),
      ]);
      final moved = page.words.map(
        (word) => word.text == 'LOOSE NAME'
            ? OcrWord(word.text, PixelBox(20, 30, 260, 34))
            : word,
      );
      expect(
        parse(OcrPage(page.width, page.height, moved)).wrappedNames,
        isEmpty,
      );
    },
  );

  test('expanded payment and VAT boundaries do not become purchases', () {
    for (final footer in ['PANKKIKORTTI', 'VAIHTORAHA', 'VEROTON']) {
      final result = parse(
        fixture([('PRODUCT', '2,00'), (footer, '2,00'), ('YHTEENSÄ', '2,00')]),
      );
      expect(result.rows, hasLength(1));
      expect(result.totals.state, TotalState.missing);
    }
  });

  test(
    'quantity tokens in separate columns attach to the preceding product',
    () {
      final result = parse(
        fixture([
          ('FRUIT', '0,75'),
          ('0,250 kg', '3,00 €/kg'),
          ('YHTEENSÄ', '0,75'),
        ]),
      );
      expect(result.rows.single.quantityMatches, isTrue);
      expect(result.rows.single.quantity!.value, BigInt.from(250000));
      expect(result.rows.single.rateMicros, BigInt.from(3000000));
    },
  );
}
