import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

OcrWord word(String text, double y, {double x = 10, double right = 200}) =>
    OcrWord(text, PixelBox(x, y, right, y + 16));

ReceiptDraft parse(List<OcrWord> words) =>
    parseReceipt(OcrPage(500, 500, words), itemTop: 40, priceColumnLeft: 350);

void main() {
  test(
    'invalid item and total amounts retain distinct scopes and evidence',
    () {
      final draft = parse([
        word('15.11.2026', 10),
        word('MILK', 70),
        word('I,00', 70, x: 400, right: 480),
        word('YHTEENSÄ', 120),
        word('I,00', 120, x: 400, right: 480),
        word('ALV', 180),
      ]);
      final findings = draft.findings
          .where((f) => f.issue == ParseIssue.invalidAmount)
          .toList();
      final total = findings.singleWhere((f) => f.scope == FindingScope.total);
      final item = findings.singleWhere((f) => f.scope == FindingScope.item);
      expect(total.rowIndex, isNull);
      expect(total.words.first.text, 'YHTEENSÄ');
      expect(item.words.first.text, 'MILK');
      expect(isUnparsedItemFinding(item), isTrue);
      expect(isUnparsedItemFinding(total), isFalse);
      expect(canResolveFinding(total, total: '1,00'), isTrue);
      expect(canResolveFinding(item, total: '1,00'), isFalse);
      expect(
        canResolveRowEvidence(
          total,
          RowEvidenceKind.financialRow,
          target: const ReviewRowInput('MILK', '1,00', LineKind.product),
        ),
        isFalse,
      );
      expect(draft.evidenceCoverage!.complete, isTrue);
      expect(draft.requiresReview, isTrue);
    },
  );

  test(
    'normalized total can be reviewed without inventing a product association',
    () {
      final draft = parse([
        word('MILK', 70),
        word('1,00', 70, x: 400, right: 480),
        word('YHTEENSÄ', 120),
        word('1, 00', 120, x: 400, right: 480),
      ]);
      final finding = draft.findings.single;
      expect(finding.issue, ParseIssue.normalizedOcrAmount);
      expect(finding.scope, FindingScope.total);
      expect(finding.rowIndex, isNull);
      expect(canResolveFinding(finding, total: '1,00'), isTrue);
      expect(canResolveFinding(finding, total: 'I,00'), isFalse);
    },
  );

  test('unparsed row dispositions require valid non-discount targets or explicit nonfinancial categories', () {
    final finding = ParseFinding(
      ParseIssue.unclassifiedRow,
      scope: FindingScope.item,
      words: [word('CONTINUED', 70)],
    );
    const product = ReviewRowInput('TEST', '1,00', LineKind.product);
    expect(
      canResolveRowEvidence(
        finding,
        RowEvidenceKind.financialRow,
        target: product,
      ),
      isTrue,
    );
    expect(
      canResolveRowEvidence(
        finding,
        RowEvidenceKind.description,
        target: product,
      ),
      isTrue,
    );
    for (final target in [
      null,
      const ReviewRowInput('', '1,00', LineKind.product),
      const ReviewRowInput('TEST', 'I,00', LineKind.product),
      const ReviewRowInput('ALE', '-1,00', LineKind.discount),
      const ReviewRowInput(
        'TEST',
        '1,00',
        LineKind.product,
        quantity: '2',
        rate: '1',
        unit: QuantityUnit.piece,
      ),
    ]) {
      expect(
        canResolveRowEvidence(
          finding,
          RowEvidenceKind.financialRow,
          target: target,
        ),
        isFalse,
      );
    }
    expect(
      canResolveRowEvidence(
        finding,
        RowEvidenceKind.financialRow,
        target: const ReviewRowInput('RETURN', '-1,00', LineKind.deposit),
      ),
      isTrue,
    );
    expect(
      canResolveRowEvidence(
        finding,
        RowEvidenceKind.description,
        target: const ReviewRowInput('DEPOSIT', '1,00', LineKind.deposit),
      ),
      isFalse,
    );
    for (final kind in [
      RowEvidenceKind.headerMetadata,
      RowEvidenceKind.paymentOrTax,
      RowEvidenceKind.explanatoryText,
    ]) {
      expect(canResolveRowEvidence(finding, kind), isTrue);
      expect(canResolveRowEvidence(finding, kind, target: product), isFalse);
    }
    expect(
      canResolveRowEvidence(
        ParseFinding(ParseIssue.unclassifiedRow, scope: FindingScope.item),
        RowEvidenceKind.headerMetadata,
      ),
      isFalse,
    );
    expect(
      canResolveRowEvidence(
        ParseFinding(ParseIssue.unclassifiedRow, words: finding.words),
        RowEvidenceKind.headerMetadata,
      ),
      isFalse,
    ); // Legacy unknown scope.
  });

  test('section boundary exclusions remain visible in coverage inventory', () {
    final crossing = OcrWord('CUT', PixelBox(10, 34, 100, 50));
    final companion = OcrWord('CUT', PixelBox(400, 40, 480, 52));
    final draft = parse([
      crossing,
      companion,
      word('YHTEENSÄ', 120),
      word('1,00', 120, x: 400, right: 480),
    ]);
    final coverage = draft.evidenceCoverage!;
    expect(coverage.complete, isFalse);
    expect(coverage.sourceWords.length, 4);
    expect(coverage.unassignedWords, [crossing, companion]);
    expect(() => coverage.sourceWords.clear(), throwsUnsupportedError);
    expect(() => coverage.unassignedWords.clear(), throwsUnsupportedError);
  });

  test(
    'text between competing totals cannot silently disappear from coverage',
    () {
      final skipped = word('UNACCOUNTED', 150);
      final draft = parse([
        word('YHTEENSÄ', 100),
        word('1,00', 100, x: 400, right: 480),
        skipped,
        word('YHTEENSÄ', 200),
        word('1,00', 200, x: 400, right: 480),
        word('ALV', 300),
      ]);
      expect(draft.issues, contains(ParseIssue.ambiguousTotal));
      expect(draft.evidenceCoverage!.unassignedWords, [skipped]);
    },
  );
}
