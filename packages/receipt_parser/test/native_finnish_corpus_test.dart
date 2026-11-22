import 'dart:convert';
import 'dart:io';

import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'fixtures/finnish_receipts.dart';

void main() {
  final captures = [
    for (final backend in ['tesseract', 'mlkit'])
      ...jsonDecode(
            File('test/fixtures/native_$backend.json').readAsStringSync(),
          )['captures']
          as List,
  ];
  for (final capture in captures) {
    final fixture = finnishReceiptFixtures.singleWhere(
      (f) => f.id == capture['case'],
    );
    test('captured ${capture['backend']}: ${fixture.id}', () {
      expect(capture['synthetic'], isTrue);
      expect(capture['sourceImageSha256'], matches(r'^[0-9a-f]{64}$'));
      final page = OcrPage(capture['width'] as int, capture['height'] as int, [
        for (final w in capture['words'] as List)
          OcrWord(
            w[0] as String,
            PixelBox(
              (w[1] as num).toDouble(),
              (w[2] as num).toDouble(),
              (w[3] as num).toDouble(),
              (w[4] as num).toDouble(),
            ),
          ),
      ], baselineSlope: (capture['baselineSlope'] as num).toDouble());
      final draft = parseReceipt(page, itemTop: 150, priceColumnLeft: 900);
      expect(draft.rows.map((r) => (r.name, r.cents, r.kind)), [
        for (final row in fixture.rows)
          (row.name, BigInt.from(row.cents), row.kind),
      ]);
      expect(draft.printedTotal, BigInt.from(fixture.total!));
      expect(draft.date.state, ReceiptDateState.valid);
      expect(
        (
          draft.date.printed!.year,
          draft.date.printed!.month,
          draft.date.printed!.day,
        ),
        (2026, 11, 22),
      );
      for (var i = 0; i < fixture.rows.length; i++) {
        final expected = fixture.rows[i], actual = draft.rows[i];
        expect(
          actual.quantity?.value,
          expected.quantityMicros == null
              ? null
              : BigInt.from(expected.quantityMicros!),
        );
        expect(
          actual.rateMicros,
          expected.rateMicros == null
              ? null
              : BigInt.from(expected.rateMicros!),
        );
        expect(actual.quantity?.unit, expected.unit);
        expect(actual.quantityMatches, expected.quantityMatches);
      }
      // Explicitly annotated from the captured input, not generated from the
      // current parser: Tesseract read a minus as an em dash; ML Kit split the
      // unit rate into "2," and "00". Both require human evidence review.
      expect(
        draft.findings.map((f) => (f.issue, f.rowIndex, f.scope)),
        fixture.id == 'weighed_return'
            ? [(ParseIssue.normalizedOcrAmount, 0, FindingScope.item)]
            : isEmpty,
      );
      expect(draft.evidenceCoverage!.complete, isTrue);
      expect(draft.totals.state, TotalState.matched);
      final layout = proposeLayout(page);
      expect(layout.available, isTrue);
      final proposed = parseReceipt(
        page,
        itemTop: layout.itemTop!,
        priceColumnLeft: layout.priceColumnLeft!,
      );
      expect(
        proposed.rows.map((r) => (r.name, r.cents)),
        draft.rows.map((r) => (r.name, r.cents)),
      );
    });
  }

  test('distant quantity decimal fragments are never fused', () {
    final capture = captures.singleWhere(
      (c) => c['backend'] == 'mlkit' && c['case'] == 'weighed_return',
    );
    final page = OcrPage(capture['width'] as int, capture['height'] as int, [
      for (final w in capture['words'] as List)
        OcrWord(
          w[0] as String,
          PixelBox(
            (w[1] as num).toDouble() +
                (w[2] == 241.0 && (w[1] as num) >= 294 ? 60 : 0),
            (w[2] as num).toDouble(),
            (w[3] as num).toDouble() +
                (w[2] == 241.0 && (w[1] as num) >= 294 ? 60 : 0),
            (w[4] as num).toDouble(),
          ),
        ),
    ]);
    final draft = parseReceipt(page, itemTop: 150, priceColumnLeft: 900);
    expect(draft.rows.first.quantity, isNull);
    expect(draft.findings.map((f) => f.issue), [ParseIssue.unclassifiedRow]);
    expect(draft.findings.single.words.map((w) => w.text), [
      '-0,500',
      'kg',
      'x',
      '2,',
      '00',
      '€/kg',
    ]);
    expect(draft.totals.state, TotalState.matched);
  });

  test(
    'OCR-specific notation does not relax strict manual financial input',
    () {
      for (final text in ['1,00 €', '1,00EUR', '—1,00', '–1,00', '1, 00']) {
        expect(parseCents(text), isNull, reason: text);
      }
      expect(parseCents('−1,00'), BigInt.from(-100));
    },
  );
}
