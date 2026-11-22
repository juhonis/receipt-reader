import 'package:receipt_parser/receipt_parser.dart';

/// Invented text, prices and geometry. No image or OCR dump from a real purchase
/// was used. These annotations are independent of the parser's output.
class ReceiptLineFixture {
  const ReceiptLineFixture(
    this.name, [
    this.amount = '',
    this.amountTokens,
    this.amountGap = 12,
  ]);
  final String name, amount;
  final List<String>? amountTokens;
  final int amountGap;
}

class ExpectedReceiptRow {
  const ExpectedReceiptRow(
    this.name,
    this.cents, {
    this.kind = LineKind.product,
    this.quantityMicros,
    this.rateMicros,
    this.unit,
    this.quantityMatches,
  });
  final String name;
  final int cents;
  final LineKind kind;
  final int? quantityMicros, rateMicros;
  final QuantityUnit? unit;
  final bool? quantityMatches;
}

class ExpectedReceiptFinding {
  const ExpectedReceiptFinding(
    this.issue, {
    this.row,
    this.scope = FindingScope.item,
    this.discount,
  });
  final ParseIssue issue;
  final int? row;
  final FindingScope scope;
  final DiscountFindingKind? discount;
}

class FinnishReceiptFixture {
  const FinnishReceiptFixture({
    required this.id,
    required this.purpose,
    required this.lines,
    required this.rows,
    required this.total,
    this.findings = const [],
    this.date = '22.11.2026',
    this.dateState = ReceiptDateState.valid,
    this.unassigned = const [],
    this.wrapped = const [],
    this.layout = true,
    this.native = false,
    this.nativeAllowedIssues = const [],
  });
  final String id, purpose, date;
  final List<ReceiptLineFixture> lines;
  final List<ExpectedReceiptRow> rows;
  final int? total;
  final List<ExpectedReceiptFinding> findings;
  final ReceiptDateState dateState;
  final List<String> unassigned, wrapped;
  final bool layout, native;
  final List<ParseIssue> nativeAllowedIssues;

  int get height => 1000 + (lines.length > 12 ? (lines.length - 12) * 56 : 0);

  /// Individual OCR words and fixed pixel boxes; no financial expectation is
  /// used to build a page or select its boundaries. Native tests draw these same
  /// public words into a synthetic image and run the actual recognition engine.
  OcrPage page() {
    final words = <OcrWord>[];
    void label(String text, double y) {
      var x = 60.0;
      for (final token in text.split(' ')) {
        final width = token.length * 18.0;
        words.add(OcrWord(token, PixelBox(x, y, x + width, y + 30)));
        x += width + 12;
      }
    }

    label('SYNTEETTINEN TESTIKAUPPA', 40);
    label(date, 90);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i], y = 180.0 + i * 56;
      if (line.name.isNotEmpty) label(line.name, y);
      final tokens =
          line.amountTokens ??
          (line.amount.isEmpty ? const <String>[] : line.amount.split(' '));
      if (tokens.isEmpty) continue;
      var x = 1100.0 - tokens.first.length * 18;
      for (final token in tokens) {
        final width = token.length * 18.0;
        words.add(OcrWord(token, PixelBox(x, y + 1, x + width, y + 31)));
        x += width + line.amountGap;
      }
    }
    return OcrPage(1200, height, words);
  }
}

const finnishReceiptFixtures = [
  FinnishReceiptFixture(
    id: 'wide_currency_spacing',
    purpose:
        'A separated currency marker is not a second amount or a lost row.',
    lines: [
      ReceiptLineFixture('MAITO', '1,30 €', null, 48),
      ReceiptLineFixture('LEIPÄ', '2,20 EUR', null, 32),
      ReceiptLineFixture('YHTEENSÄ:', '3,50 €', null, 48),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    total: 350,
  ),
  FinnishReceiptFixture(
    id: 'ocr_dash_sign',
    purpose: 'A leading typographic OCR dash is proposed as negative only with explicit review.',
    lines: [
      ReceiptLineFixture('PALAUTUS', '—1,00 €'),
      ReceiptLineFixture('LEIPÄ', '2,40'),
      ReceiptLineFixture('YHTEENSÄ', '1,40'),
    ],
    rows: [
      ExpectedReceiptRow('PALAUTUS', -100),
      ExpectedReceiptRow('LEIPÄ', 240),
    ],
    findings: [ExpectedReceiptFinding(ParseIssue.normalizedOcrAmount, row: 0)],
    total: 140,
  ),
  FinnishReceiptFixture(
    id: 'separate_digit_runs',
    purpose:
        'Currency-spacing support must not fuse independent numeric tokens.',
    lines: [
      ReceiptLineFixture('KAHVI', '', ['1', '99,00'], 8),
      ReceiptLineFixture('TEE', '1,29'),
      ReceiptLineFixture('YHTEENSÄ', '100,29'),
    ],
    rows: [ExpectedReceiptRow('TEE', 129)],
    findings: [ExpectedReceiptFinding(ParseIssue.invalidAmount)],
    total: 10029,
    layout: false,
  ),
  FinnishReceiptFixture(
    id: 'euro_duplicates',
    purpose: 'Repeated products, currency suffixes, annotated total and VAT/card footer.',
    native: true,
    lines: [
      ReceiptLineFixture('MAITO', '1,29 €'),
      ReceiptLineFixture('MAITO', '1,29 €'),
      ReceiptLineFixture('LEIPÄ', '2,49 €'),
      ReceiptLineFixture('YHTEENSÄ (EUR)', '5,07 €'),
      ReceiptLineFixture('VISA', '5,07'),
      ReceiptLineFixture('ALV 14 %', '0,62'),
      ReceiptLineFixture('YHTEENSÄ', '99,99'),
    ],
    rows: [
      ExpectedReceiptRow('MAITO', 129),
      ExpectedReceiptRow('MAITO', 129),
      ExpectedReceiptRow('LEIPÄ', 249),
    ],
    total: 507,
  ),
  FinnishReceiptFixture(
    id: 'weighed_multiplication',
    purpose:
        'Explicit kg multiplication and independent rounding to posted cents.',
    native: true,
    lines: [
      ReceiptLineFixture('BANAANI', '1,42'),
      ReceiptLineFixture('0,750 kg x 1,89 €/kg'),
      ReceiptLineFixture('MAITO', '1,39'),
      ReceiptLineFixture('YHTEENSÄ', '2,81'),
    ],
    rows: [
      ExpectedReceiptRow(
        'BANAANI',
        142,
        quantityMicros: 750000,
        rateMicros: 1890000,
        unit: QuantityUnit.kg,
        quantityMatches: true,
      ),
      ExpectedReceiptRow('MAITO', 139),
    ],
    total: 281,
  ),
  FinnishReceiptFixture(
    id: 'counted_multiplication',
    purpose:
        'Explicit piece quantities, multiplication glyph and EUR unit rate.',
    lines: [
      ReceiptLineFixture('KIVENNÄISVESI', '3,30'),
      ReceiptLineFixture('3 kpl × 1,10 EUR/kpl'),
      ReceiptLineFixture('VOI', '2,50'),
      ReceiptLineFixture('YHTEENSÄ EUR', '5,80'),
    ],
    rows: [
      ExpectedReceiptRow(
        'KIVENNÄISVESI',
        330,
        quantityMicros: 3000000,
        rateMicros: 1100000,
        unit: QuantityUnit.piece,
        quantityMatches: true,
      ),
      ExpectedReceiptRow('VOI', 250),
    ],
    total: 580,
  ),
  FinnishReceiptFixture(
    id: 'weighed_return',
    purpose:
        'Unicode minus preserves a returned product and negative kg quantity.',
    native: true,
    nativeAllowedIssues: [ParseIssue.normalizedOcrAmount],
    lines: [
      ReceiptLineFixture('OMENA', '−1,00'),
      ReceiptLineFixture('−0,500 kg × 2,00 €/kg'),
      ReceiptLineFixture('LEIPÄ', '2,40'),
      ReceiptLineFixture('YHTEENSÄ', '1,40'),
    ],
    rows: [
      ExpectedReceiptRow(
        'OMENA',
        -100,
        quantityMicros: -500000,
        rateMicros: 2000000,
        unit: QuantityUnit.kg,
        quantityMatches: true,
      ),
      ExpectedReceiptRow('LEIPÄ', 240),
    ],
    total: 140,
  ),
  FinnishReceiptFixture(
    id: 'quantity_decimal_whitespace',
    purpose: 'Nearby split quantity/rate decimals retain an explicit review warning.',
    lines: [
      ReceiptLineFixture('OMENA', '-1,00'),
      ReceiptLineFixture('-0, 500 kg x 2, 00 €/kg'),
      ReceiptLineFixture('LEIPÄ', '2,40'),
      ReceiptLineFixture('YHTEENSÄ', '1,40'),
    ],
    rows: [
      ExpectedReceiptRow(
        'OMENA',
        -100,
        quantityMicros: -500000,
        rateMicros: 2000000,
        unit: QuantityUnit.kg,
        quantityMatches: true,
      ),
      ExpectedReceiptRow('LEIPÄ', 240),
    ],
    findings: [ExpectedReceiptFinding(ParseIssue.normalizedOcrAmount, row: 0)],
    total: 140,
  ),
  FinnishReceiptFixture(
    id: 'quantity_separate_digit_runs',
    purpose: 'Quantity recovery must not fuse independent numeric runs.',
    lines: [
      ReceiptLineFixture('OMENA', '-1,00'),
      ReceiptLineFixture('-0,500 kg x 2, 0 0 €/kg'),
      ReceiptLineFixture('LEIPÄ', '2,40'),
      ReceiptLineFixture('YHTEENSÄ', '1,40'),
    ],
    rows: [ExpectedReceiptRow('OMENA', -100), ExpectedReceiptRow('LEIPÄ', 240)],
    findings: [ExpectedReceiptFinding(ParseIssue.unclassifiedRow)],
    total: 140,
  ),
  FinnishReceiptFixture(
    id: 'deposit_and_refund',
    purpose: 'Deposit charge and refund remain separate signed financial rows.',
    lines: [
      ReceiptLineFixture('LIMONAADI', '1,19'),
      ReceiptLineFixture('PANTTI', '0,15'),
      ReceiptLineFixture('PANTTI PALAUTUS', '−0,20'),
      ReceiptLineFixture('YHTEENSÄ', '1,14'),
    ],
    rows: [
      ExpectedReceiptRow('LIMONAADI', 119),
      ExpectedReceiptRow('PANTTI', 15, kind: LineKind.deposit),
      ExpectedReceiptRow('PANTTI PALAUTUS', -20, kind: LineKind.deposit),
    ],
    total: 114,
  ),
  FinnishReceiptFixture(
    id: 'posted_discounts',
    purpose: 'Posted discounts contribute once but require explicit relationship review.',
    lines: [
      ReceiptLineFixture('KAHVI', '5,00'),
      ReceiptLineFixture('ALENNUS 20 %', '-1,00'),
      ReceiptLineFixture('ALE', '-0,50'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
    ],
    rows: [
      ExpectedReceiptRow('KAHVI', 500),
      ExpectedReceiptRow('ALENNUS 20 %', -100, kind: LineKind.discount),
      ExpectedReceiptRow('ALE', -50, kind: LineKind.discount),
    ],
    findings: [
      ExpectedReceiptFinding(
        ParseIssue.discountNeedsReview,
        row: 1,
        discount: DiscountFindingKind.postedDiscount,
      ),
      ExpectedReceiptFinding(
        ParseIssue.discountNeedsReview,
        row: 2,
        discount: DiscountFindingKind.postedDiscount,
      ),
    ],
    total: 350,
  ),
  FinnishReceiptFixture(
    id: 'net_price_explanations',
    purpose: 'Normal/campaign prices explain a net amount; never subtract them again.',
    lines: [
      ReceiptLineFixture('JOGURTTI', '1,49'),
      ReceiptLineFixture('NORM.', '1,99'),
      ReceiptLineFixture('KAMPANJA', '-0,50'),
      ReceiptLineFixture('MEHU', '2,00'),
      ReceiptLineFixture('YHTEENSÄ', '3,49'),
    ],
    rows: [
      ExpectedReceiptRow('JOGURTTI', 149),
      ExpectedReceiptRow('MEHU', 200),
    ],
    findings: [
      ExpectedReceiptFinding(
        ParseIssue.discountNeedsReview,
        discount: DiscountFindingKind.explanatoryPrice,
      ),
      ExpectedReceiptFinding(
        ParseIssue.discountNeedsReview,
        discount: DiscountFindingKind.explanatoryPrice,
      ),
    ],
    total: 349,
  ),
  FinnishReceiptFixture(
    id: 'wrapped_or_missing_price',
    purpose: 'An unpriced line may be wrapping or a missing product price; do not silently merge.',
    lines: [
      ReceiptLineFixture('PAAHDETTU'),
      ReceiptLineFixture('TÄYSJYVÄLEIPÄ', '2,20'),
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
    ],
    rows: [
      ExpectedReceiptRow('TÄYSJYVÄLEIPÄ', 220),
      ExpectedReceiptRow('MAITO', 130),
    ],
    findings: [
      ExpectedReceiptFinding(ParseIssue.unclassifiedRow),
      ExpectedReceiptFinding(ParseIssue.wrappedNameNeedsReview, row: 0),
    ],
    wrapped: ['PAAHDETTU TÄYSJYVÄLEIPÄ'],
    total: 350,
  ),
  FinnishReceiptFixture(
    id: 'orphan_quantity',
    purpose: 'A quantity before any product is not attached to a later row.',
    lines: [
      ReceiptLineFixture('2 kpl x 1,00 €/kpl'),
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('LEIPÄ', '2,20'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    findings: [ExpectedReceiptFinding(ParseIssue.quantityWithoutProduct)],
    total: 350,
  ),
  FinnishReceiptFixture(
    id: 'quantity_mismatch',
    purpose: 'Matching receipt totals cannot override an inconsistent quantity extension.',
    lines: [
      ReceiptLineFixture('BANAANI', '1,43'),
      ReceiptLineFixture('0,750 kg x 1,89 €/kg'),
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('YHTEENSÄ', '2,73'),
    ],
    rows: [
      ExpectedReceiptRow(
        'BANAANI',
        143,
        quantityMicros: 750000,
        rateMicros: 1890000,
        unit: QuantityUnit.kg,
        quantityMatches: false,
      ),
      ExpectedReceiptRow('MAITO', 130),
    ],
    findings: [ExpectedReceiptFinding(ParseIssue.quantityMismatch, row: 0)],
    total: 273,
  ),
  FinnishReceiptFixture(
    id: 'corrupted_amount',
    purpose: 'OCR letter I is not guessed to be the digit 1.',
    lines: [
      ReceiptLineFixture('KAHVI', 'I,99'),
      ReceiptLineFixture('TEE', '1,29'),
      ReceiptLineFixture('YHTEENSÄ', '3,28'),
    ],
    rows: [ExpectedReceiptRow('TEE', 129)],
    findings: [ExpectedReceiptFinding(ParseIssue.invalidAmount)],
    total: 328,
    layout: false,
  ),
  FinnishReceiptFixture(
    id: 'competing_totals',
    purpose: 'Do not choose the total that happens to reconcile.',
    lines: [
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('LEIPÄ', '2,20'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
      ReceiptLineFixture('YHTEENSÄ', '13,50'),
      ReceiptLineFixture('VISA', '3,50'),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    findings: [
      ExpectedReceiptFinding(
        ParseIssue.ambiguousTotal,
        scope: FindingScope.total,
      ),
    ],
    total: null,
    layout: false,
  ),
  FinnishReceiptFixture(
    id: 'decimal_whitespace',
    purpose: 'Bounded OCR decimal recovery remains a visible finding.',
    lines: [
      ReceiptLineFixture('KEKSI', '', ['1, 99']),
      ReceiptLineFixture('TEE', '1,29'),
      ReceiptLineFixture('YHTEENSÄ', '3,28'),
    ],
    rows: [ExpectedReceiptRow('KEKSI', 199), ExpectedReceiptRow('TEE', 129)],
    findings: [ExpectedReceiptFinding(ParseIssue.normalizedOcrAmount, row: 0)],
    total: 328,
  ),
  FinnishReceiptFixture(
    id: 'cash_footer',
    purpose: 'Parser and layout detector agree that later cash/footer totals are not candidates.',
    lines: [
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('LEIPÄ', '2,20'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
      ReceiptLineFixture('KÄTEINEN', '10,00'),
      ReceiptLineFixture('VAIHTORAHA', '6,50'),
      ReceiptLineFixture('YHTEENSÄ', '10,00'),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    total: 350,
  ),
  FinnishReceiptFixture(
    id: 'unknown_footer',
    purpose:
        'Unrecognized footer material remains uncovered even when sums match.',
    lines: [
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('LEIPÄ', '2,20'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
      ReceiptLineFixture('TUNTEMATON LISÄTIETO'),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    total: 350,
    unassigned: ['TUNTEMATON', 'LISÄTIETO'],
  ),
  FinnishReceiptFixture(
    id: 'unsupported_quantity_unit',
    purpose: 'Package units are not guessed to be pieces.',
    lines: [
      ReceiptLineFixture('KEKSI', '2,98'),
      ReceiptLineFixture('2 pkt x 1,49 €/pkt'),
      ReceiptLineFixture('MAITO', '1,00'),
      ReceiptLineFixture('YHTEENSÄ', '3,98'),
    ],
    rows: [ExpectedReceiptRow('KEKSI', 298), ExpectedReceiptRow('MAITO', 100)],
    findings: [ExpectedReceiptFinding(ParseIssue.unclassifiedRow)],
    total: 398,
  ),
  FinnishReceiptFixture(
    id: 'foreign_currency',
    purpose: 'A USD total is not silently treated as EUR.',
    lines: [
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('LEIPÄ', '2,20'),
      ReceiptLineFixture('YHTEENSÄ', '3,50USD'),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    findings: [
      ExpectedReceiptFinding(
        ParseIssue.invalidAmount,
        scope: FindingScope.total,
      ),
    ],
    total: null,
    layout: false,
  ),
  FinnishReceiptFixture(
    id: 'ambiguous_helsinki_clock',
    purpose: 'An autumn clock fold stays ambiguous independently of matching amounts.',
    date: '25.10.2026 03:30',
    dateState: ReceiptDateState.ambiguous,
    lines: [
      ReceiptLineFixture('MAITO', '1,30'),
      ReceiptLineFixture('LEIPÄ', '2,20'),
      ReceiptLineFixture('YHTEENSÄ', '3,50'),
    ],
    rows: [ExpectedReceiptRow('MAITO', 130), ExpectedReceiptRow('LEIPÄ', 220)],
    total: 350,
  ),
];
