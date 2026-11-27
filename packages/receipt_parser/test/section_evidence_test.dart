import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

// Invented products, amounts, identifiers and coordinates. The complete header
// notice is standard receipt boilerplate, not a product-name heuristic.
const notice = 'ASIAKASOMISTAJAN EDUT ON HUOMIOITU.';
OcrWord word(
  String text,
  double x,
  double y,
  double width, {
  double height = 20,
}) => OcrWord(text, PixelBox(x, y, x + width, y + height));

OcrPage sectionPage({
  String header = notice,
  bool footer = true,
  bool total = true,
}) => OcrPage(
  900,
  600,
  [
    word('19.11.2026', 40, 20, 120),
    if (header.isNotEmpty) word(header, 40, 80, 500),
    word('TEST PACK 6KPL', 40, 116, 210),
    word('1,80', 700, 116, 50),
    word('2 kpl 0,90 €/kpl', 40, 146, 400),
    word('TEST BREAD', 40, 180, 180),
    word('2,20', 700, 180, 50),
    if (total) ...[word('YHTEENSÄ', 40, 230, 150), word('4,00', 700, 230, 50)],
    if (footer) ...[word('VISA', 40, 280, 80), word('4,00', 700, 280, 50)],
    word('TEST-PAYMENT-REFERENCE', 50, 320, 700),
    word('CARD DETAIL', 40, 360, 200),
    word('TEST TOKEN', 200, 360, 180),
    // Small middle token creates two bands; the later tall token can match
    // both. This is footer ambiguity, unrelated to the purchased products.
    word('FOOTER A', 40, 400, 100),
    word('FOOTER B', 220, 414, 100, height: 4),
    word('FOOTER C', 400, 407.5, 100),
  ].reversed,
);

ReceiptDraft parse(OcrPage page, {double itemTop = 60}) =>
    parseReceipt(page, itemTop: itemTop, priceColumnLeft: 650);

OcrEvidenceAudit receiptAudit(ReceiptDraft draft) {
  final rows = List.generate(draft.rows.length, (_) => Object());
  return OcrEvidenceAudit(
    snapshot: OcrReviewSnapshot(
      draft,
      'INVENTED BRANCH',
      '19.11.2026',
      '4,00',
      true,
      [
        for (var i = 0; i < draft.rows.length; i++)
          OcrReviewRow(
            rows[i],
            ReviewRowInput(
              draft.rows[i].name,
              formatCents(draft.rows[i].cents),
              draft.rows[i].kind,
              quantity: draft.rows[i].quantity == null
                  ? ''
                  : formatFixed(draft.rows[i].quantity!.value, 6),
              rate: draft.rows[i].rateMicros == null
                  ? ''
                  : formatFixed(draft.rows[i].rateMicros!, 6),
              unit: draft.rows[i].quantity?.unit ?? QuantityUnit.unknown,
            ),
            false,
            draft.rowEvidence[i],
          ),
      ],
    ),
    findings: reviewFindingsForDraft(draft),
    decisions: const {},
    originalRowIds: rows,
    imageMatchesSource: true,
    pageApproval: null,
    policy: OcrReviewPolicy.receipt,
  );
}

void main() {
  test(
    'leading notice and anchored footer geometry do not block receipt review',
    () {
      final input = sectionPage(), draft = parse(input);
      expect(draft.rows.map((r) => (r.name, r.cents.toInt())), [
        ('TEST PACK 6KPL', 180),
        ('TEST BREAD', 220),
      ]);
      expect(draft.rows.first.quantity!.value, BigInt.from(2000000));
      expect(draft.rows.first.rateMicros, BigInt.from(900000));
      expect(draft.rows.first.quantityMatches, isTrue);
      expect(draft.totals.state, TotalState.matched);
      expect(draft.date.state, ReceiptDateState.valid);
      expect(draft.notes, isEmpty);
      expect(draft.wrappedNames, isEmpty);
      expect(draft.findings, isEmpty);
      expect(draft.issues, isEmpty);
      expect(draft.evidenceCoverage!.complete, isTrue);
      expect(
        draft.rowEvidence.expand((w) => w).every(input.words.contains),
        isTrue,
      );
      expect(
        draft.rowEvidence.expand((w) => w).map((w) => w.text),
        isNot(contains(notice)),
      );
      expect(draft.parseContext!.page, same(input));
      final audit = receiptAudit(draft);
      expect(audit.automaticReady, isTrue);
      expect(audit.ready, isFalse);
      expect(audit.blockers, {OcrEvidenceBlocker.receiptApproval});
    },
  );

  test('only complete notice wording is classified, with harmless case and spacing', () {
    final exact = parse(
      sectionPage(header: '  asiakasomistajan  edut on huomioitu  '),
    );
    expect(exact.notes, isEmpty);
    final uncertain = parse(
      sectionPage(header: 'ASIAKASOMISTAJAN EDUT ON HUOMIOITU KAIKKI'),
    );
    expect(
      uncertain.notes,
      contains('ASIAKASOMISTAJAN EDUT ON HUOMIOITU KAIKKI'),
    );
    expect(uncertain.issues, contains(ParseIssue.unclassifiedRow));
    expect(receiptAudit(uncertain).automaticReady, isFalse);
  });

  test('a notice-like product with a posted amount is never excluded', () {
    final base = sectionPage();
    final draft = parse(
      OcrPage(900, 600, [...base.words, word('1,23', 700, 80, 50)]),
    );
    expect(draft.rows.first.name, notice);
    expect(draft.rows.first.cents, BigInt.from(123));
    expect(draft.rows, hasLength(3));
    expect(draft.totals.state, TotalState.mismatched);
  });

  test('unknown unpriced leading text ends header notice classification', () {
    final base = sectionPage();
    final draft = parse(
      OcrPage(900, 600, [
        ...base.words,
        word('UNPRICED TEST ITEM', 40, 65, 280, height: 10),
      ]),
    );
    expect(draft.notes, containsAll(['UNPRICED TEST ITEM', notice]));
    expect(draft.issues, contains(ParseIssue.unclassifiedRow));
    expect(draft.evidenceCoverage!.complete, isTrue);
    expect(receiptAudit(draft).automaticReady, isFalse);
  });

  test('notice wording inside the product section remains reviewable', () {
    final base = sectionPage();
    final moved = OcrPage(
      900,
      600,
      base.words.map(
        (w) => w.text == notice ? word(notice, 40, 158, 500, height: 10) : w,
      ),
    );
    final draft = parse(moved);
    expect(draft.notes, contains(notice));
    expect(draft.issues, contains(ParseIssue.unclassifiedRow));
    expect(receiptAudit(draft).automaticReady, isFalse);
  });

  test('a header notice cannot be excluded without a printed header date', () {
    final base = sectionPage();
    final draft = parse(
      OcrPage(900, 600, base.words.where((w) => w.text != '19.11.2026')),
    );
    expect(draft.date.state, ReceiptDateState.missing);
    expect(draft.notes, contains(notice));
    expect(draft.issues, contains(ParseIssue.unclassifiedRow));
  });

  test(
    'cut section boundaries keep omissions even through known boilerplate',
    () {
      final input = sectionPage(), draft = parse(input, itemTop: 90);
      expect(
        draft.findings.any(
          (f) => f.geometryKind == GeometryFindingKind.sectionBoundary,
        ),
        isTrue,
      );
      expect(
        draft.evidenceCoverage!.unassignedWords.map((w) => w.text),
        contains(notice),
      );
      expect(receiptAudit(draft).automaticReady, isFalse);
    },
  );

  test('date overlap remains a geometry finding', () {
    final base = sectionPage();
    final dateTime = word('08:45', 140, 20, 70);
    final draft = parse(OcrPage(900, 600, [...base.words, dateTime]));
    expect(draft.date.state, ReceiptDateState.valid);
    expect(
      draft.findings.any(
        (f) =>
            f.geometryKind == GeometryFindingKind.wordOverlap &&
            f.words.contains(dateTime),
      ),
      isTrue,
    );
    expect(receiptAudit(draft).automaticReady, isFalse);
  });

  test('product overlap and price-boundary crossings remain reviewable', () {
    final base = sectionPage();
    final duplicate = word('TEST BREAD', 40, 180, 180);
    final crossing = word('CROSSING', 630, 116, 60);
    final draft = parse(
      OcrPage(900, 600, [...base.words, duplicate, crossing]),
    );
    expect(
      draft.findings.any(
        (f) =>
            f.geometryKind == GeometryFindingKind.wordOverlap &&
            f.words.contains(duplicate),
      ),
      isTrue,
    );
    expect(
      draft.findings.any(
        (f) =>
            f.geometryKind == GeometryFindingKind.priceBoundary &&
            f.words.contains(crossing),
      ),
      isTrue,
    );
    expect(receiptAudit(draft).automaticReady, isFalse);
  });

  test('unrecognized post-total text is not treated as payment metadata', () {
    final base = sectionPage();
    final unknown = word('UNEXPLAINED ROW', 40, 260, 720);
    final draft = parse(OcrPage(900, 600, [...base.words, unknown]));
    expect(draft.evidenceCoverage!.unassignedWords, contains(unknown));
    expect(
      draft.findings.any(
        (f) =>
            f.geometryKind == GeometryFindingKind.priceBoundary &&
            f.words.contains(unknown),
      ),
      isTrue,
    );
    expect(receiptAudit(draft).automaticReady, isFalse);
  });

  test(
    'unrecognized footer sections retain omissions and geometry findings',
    () {
      final draft = parse(sectionPage(footer: false));
      expect(draft.totals.state, TotalState.matched);
      expect(draft.evidenceCoverage!.complete, isFalse);
      expect(draft.issues, contains(ParseIssue.ambiguousGeometry));
      expect(receiptAudit(draft).automaticReady, isFalse);
    },
  );

  test(
    'footer boxes extending back into the total region remain uncertain',
    () {
      final base = sectionPage();
      final crossing = word(
        'UNCERTAIN PAYMENT BOX',
        600,
        235,
        160,
        height: 100,
      );
      final draft = parse(OcrPage(900, 600, [...base.words, crossing]));
      expect(draft.totals.state, TotalState.matched);
      expect(
        draft.findings.any(
          (f) =>
              f.geometryKind == GeometryFindingKind.priceBoundary &&
              f.words.contains(crossing),
        ),
        isTrue,
      );
      expect(receiptAudit(draft).automaticReady, isFalse);
    },
  );

  test(
    'missing or competing totals keep conservative footer geometry checks',
    () {
      final missing = parse(sectionPage(total: false));
      expect(missing.printedTotal, isNull);
      expect(
        missing.issues,
        containsAll([ParseIssue.missingTotal, ParseIssue.ambiguousGeometry]),
      );
      final base = sectionPage();
      final competing = parse(
        OcrPage(900, 600, [
          ...base.words,
          word('YHTEENSA', 40, 252, 150),
          word('4,00', 700, 252, 50),
        ]),
      );
      expect(competing.printedTotal, isNull);
      expect(
        competing.issues,
        containsAll([ParseIssue.ambiguousTotal, ParseIssue.ambiguousGeometry]),
      );
      expect(receiptAudit(competing).automaticReady, isFalse);
    },
  );
}
