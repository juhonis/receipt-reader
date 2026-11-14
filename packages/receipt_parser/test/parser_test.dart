import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

/// Entirely invented OCR geometry. Name and price blocks deliberately arrive
/// in reverse order, with engine lines unrelated to the receipt's visual rows.
OcrPage fixture(List<(String, String)> lines, {bool reverse = true}) {
  final names = <Map<String, Object>>[];
  final prices = <Map<String, Object>>[];
  Map<String, Object> word(String text, int x, int y, int width) => {
    'text': text,
    'box': {'left': x, 'top': y, 'right': x + width, 'bottom': y + 12},
  };
  for (var i = 0; i < lines.length; i++) {
    final (name, price) = lines[i];
    if (name.isNotEmpty) names.add(word(name, 20, 40 + i * 24, 240));
    if (price.isNotEmpty) prices.add(word(price, 340, 41 + i * 24, 50));
  }
  return OcrPage.fromJson({
    'schemaVersion': 1,
    'image': {'width': 450, 'height': 1000, 'orientation': 'upright'},
    'blocks': [
      {
        'lines': [
          {'words': reverse ? prices.reversed.toList() : prices},
        ],
      },
      {
        'lines': [
          {'words': reverse ? names.reversed.toList() : names},
        ],
      },
    ],
  });
}

ReceiptDraft parse(List<(String, String)> rows) =>
    parseReceipt(fixture(rows), itemTop: 30, priceColumnLeft: 300);

void main() {
  test('individual name words and split decimal tokens join by geometry', () {
    final page = OcrPage(450, 300, [
      OcrWord('00', PixelBox(365, 42, 385, 54)),
      OcrWord('PRODUCT', PixelBox(75, 40, 150, 52)),
      OcrWord('1,', PixelBox(340, 41, 360, 53)),
      OcrWord('TEST', PixelBox(20, 40, 65, 52)),
      OcrWord('YHTEENSÄ', PixelBox(20, 70, 150, 82)),
      OcrWord('1,00', PixelBox(340, 70, 385, 82)),
    ]);
    final draft = parseReceipt(page, itemTop: 30, priceColumnLeft: 300);
    expect(draft.rows.single.name, 'TEST PRODUCT');
    expect(draft.rows.single.cents, BigInt.from(100));
    expect(draft.issues, isEmpty);
    expect(
      parseReceipt(page, itemTop: 45, priceColumnLeft: 300).issues,
      contains(ParseIssue.ambiguousGeometry),
    );
    expect(
      parseReceipt(page, itemTop: 30, priceColumnLeft: 350).issues,
      contains(ParseIssue.ambiguousGeometry),
    );
  });

  group('exact financial arithmetic', () {
    test('strict Finnish decimals, Unicode minus and surrounding spaces', () {
      expect(parseCents('\u00a0−12,34\u202f'), BigInt.from(-1234));
      expect(parseCents('12.34'), BigInt.from(1234));
      for (final bad in ['I2,34', '12,3', '1 2,34', '12,345', '1e2', 'NaN']) {
        expect(parseCents(bad), isNull, reason: bad);
      }
      expect(parseFixed('0,125', 6), BigInt.from(125000));
    });
    test('round half away from zero without float or overflow', () {
      for (final sign in [1, -1]) {
        expect(
          extendedCents(
            Quantity(BigInt.from(sign), 0, QuantityUnit.piece),
            BigInt.from(1005000),
          ),
          BigInt.from(sign * 101),
        );
      }
      final huge = BigInt.parse('999999999999999999999999999');
      expect(
        extendedCents(Quantity(huge, 0, QuantityUnit.kg), BigInt.from(1000000)),
        huge * BigInt.from(100),
      );
    });
    test('unknown quantity stays unknown and discrepancy is exact', () {
      final row = FinancialRow(name: 'TEST', cents: BigInt.from(123));
      expect(row.quantity, isNull);
      expect(row.quantityMatches, isNull);
      expect(
        Reconciliation([row], BigInt.from(124)).difference,
        BigInt.from(-1),
      );
      expect(Reconciliation([row], null).state, TotalState.missing);
    });
  });

  test(
    'geometry joins separated blocks, preserves duplicates and signed rows',
    () {
      final result = parse([
        ('TEST PRODUCT', '2,00'),
        ('TEST PRODUCT', '2,00'),
        ('PANTTI', '0,20'),
        ('PANTTI PALAUTUS', '-0,20'),
        ('RETURN PRODUCT', '-1,00'),
        ('ALENNUS', '-0,50'),
        ('YHTEENSÄ', '2,50'),
        ('VISA', '2,50'),
        ('ALV', '0,48'),
        ('YHTEENSÄ', '2,50'),
      ]);
      expect(result.rows.map((r) => r.cents.toInt()), [
        200,
        200,
        20,
        -20,
        -100,
        -50,
      ]);
      expect(result.rows[2].kind, LineKind.deposit);
      expect(result.rows.last.kind, LineKind.discount);
      expect(result.totals.state, TotalState.matched);
      expect(result.issues, isEmpty);
      expect(result.requiresReview, isTrue);
    },
  );

  test(
    'weighed goods and multi-buy rates validate without replacing posted cents',
    () {
      final result = parse([
        ('TEST FRUIT', '0,50'),
        ('0,250 kg 2,00 €/kg', ''),
        ('TEST CANS', '3,00'),
        ('3 kpl 1,00 €/kpl', ''),
        ('TEST RETURN', '-0,50'),
        ('-0,250 kg 2,00 €/kg', ''),
        ('YHTEENSÄ', '3,00'),
      ]);
      expect(result.rows.map((r) => r.quantityMatches), [true, true, true]);
      expect(result.rows.first.quantity!.unit, QuantityUnit.kg);
      expect(result.rows.last.quantity!.value.isNegative, isTrue);
      expect(result.issues, isEmpty);
      final mismatch = parse([
        ('TEST FRUIT', '0,51'),
        ('0,250 kg 2,00 €/kg', ''),
        ('YHTEENSÄ', '0,51'),
      ]);
      expect(mismatch.rows.single.cents, BigInt.from(51));
      expect(mismatch.issues, contains(ParseIssue.quantityMismatch));
      expect(mismatch.totals.state, TotalState.matched);
    },
  );

  test('net price explanations are never subtracted twice', () {
    final result = parse([
      ('TEST NET PRODUCT', '1,50'),
      ('NORM.', '2,00'),
      ('KAMPANJA', '-0,50'),
      ('YHTEENSÄ', '1,50'),
    ]);
    expect(result.rows.single.cents, BigInt.from(150));
    expect(result.notes, hasLength(2));
    expect(result.issues, contains(ParseIssue.discountNeedsReview));
    expect(result.totals.state, TotalState.matched);
  });

  test('missing and competing totals remain unresolved', () {
    expect(
      parse([('TEST', '1,00'), ('VISA', '1,00')]).totals.state,
      TotalState.missing,
    );
    final ambiguous = parse([
      ('TEST', '1,00'),
      ('YHTEENSÄ', '1,00'),
      ('YHTEENSÄ', '2,00'),
    ]);
    expect(ambiguous.printedTotal, isNull);
    expect(ambiguous.issues, contains(ParseIssue.ambiguousTotal));
  });

  test('wrapped names and corrupted prices are retained for review', () {
    final result = parse([
      ('WRAPPED DESCRIPTION', ''),
      ('CONTINUED', '1,00'),
      ('TEST BAD PRICE', 'I,00'),
      ('YHTEENSÄ', '2,00'),
    ]);
    expect(
      result.issues,
      containsAll([ParseIssue.unclassifiedRow, ParseIssue.invalidAmount]),
    );
    expect(result.notes, contains('WRAPPED DESCRIPTION'));
    expect(result.totals.state, TotalState.mismatched);
  });

  test('orphan quantity and inconsistent units cannot attach silently', () {
    final result = parse([
      ('2 kpl 1,00 €/kpl', ''),
      ('TEST', '1,00'),
      ('1 kg 1,00 €/l', ''),
      ('YHTEENSÄ', '1,00'),
    ]);
    expect(result.rows.single.quantity, isNull);
    expect(result.issues, contains(ParseIssue.quantityWithoutProduct));
  });

  test('input order cannot change parsed amounts', () {
    final lines = [('ONE', '1,00'), ('TWO', '2,00'), ('YHTEENSÄ', '3,00')];
    final a = parseReceipt(fixture(lines), itemTop: 30, priceColumnLeft: 300);
    final b = parseReceipt(
      fixture(lines, reverse: false),
      itemTop: 30,
      priceColumnLeft: 300,
    );
    expect(a.rows.map((r) => r.name), b.rows.map((r) => r.name));
    expect(a.rows.map((r) => r.cents), b.rows.map((r) => r.cents));
  });

  test('overlapping duplicate OCR words flag ambiguous geometry', () {
    final page = fixture([('TEST', '1,00'), ('YHTEENSÄ', '1,00')]);
    final duplicate = OcrPage(page.width, page.height, [
      ...page.words,
      page.words.first,
    ]);
    expect(
      parseReceipt(duplicate, itemTop: 30, priceColumnLeft: 300).issues,
      contains(ParseIssue.ambiguousGeometry),
    );
  });

  test('malformed geometry and layout hints are rejected', () {
    expect(() => PixelBox(0, 0, double.nan, 10), throwsFormatException);
    expect(
      () => OcrPage(10, 10, [OcrWord('X', PixelBox(0, 0, 11, 5))]),
      throwsFormatException,
    );
    expect(
      () => parseReceipt(fixture([]), itemTop: -1, priceColumnLeft: 300),
      throwsArgumentError,
    );
    expect(
      () => OcrPage.fromJson({
        'schemaVersion': 1,
        'image': {'width': 10, 'height': 10, 'orientation': 'rotated'},
        'blocks': <Object>[],
      }),
      throwsFormatException,
    );
  });
}
