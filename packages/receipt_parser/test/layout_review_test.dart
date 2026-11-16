import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  final crossing = OcrWord('CUT', PixelBox(10, 34, 100, 50));
  final companion = OcrWord('1,00', PixelBox(400, 40, 480, 52));
  final page = OcrPage(500, 500, [
    crossing,
    companion,
    OcrWord('YHTEENSÄ', PixelBox(10, 120, 200, 136)),
    OcrWord('1,00', PixelBox(400, 120, 480, 136)),
  ], baselineSlope: .01);

  test('geometry/skew evidence preserves original words without concealing omissions', () {
    final draft = parseReceipt(page, itemTop: 40, priceColumnLeft: 350);
    expect(draft.parseContext!.page, same(page));
    expect(draft.parseContext!.itemTop, 40);
    expect(draft.parseContext!.priceColumnLeft, 350);
    expect(
      draft.findings
          .firstWhere((f) => f.issue == ParseIssue.skewAdjusted)
          .words,
      page.words,
    );
    expect(
      draft.findings
          .firstWhere((f) => f.issue == ParseIssue.ambiguousGeometry)
          .words,
      [crossing],
    );
    expect(draft.evidenceCoverage!.unassignedWords, [crossing, companion]);
    expect(crossing.box.top, 34);
    expect(companion.box.top, 40);
  });

  test(
    'fresh layout parses same OCR independently and retains all findings',
    () {
      final original = parseReceipt(page, itemTop: 40, priceColumnLeft: 350);
      final fresh = parseReceipt(
        original.parseContext!.page,
        itemTop: 25,
        priceColumnLeft: 350,
      );
      expect(original.rows, isEmpty);
      expect(fresh.rows.single.name, 'CUT');
      expect(fresh.rows.single.cents, BigInt.from(100));
      expect(fresh.evidenceCoverage!.complete, isTrue);
      expect(original.evidenceCoverage!.complete, isFalse);
      expect(original.parseContext!.itemTop, 40);
      expect(fresh.parseContext!.itemTop, 25);
      expect(fresh.issues, contains(ParseIssue.skewAdjusted));
      expect(fresh.requiresReview, isTrue);
    },
  );

  test(
    'omissions need their own decisions; resolving geometry cannot clear them',
    () {
      final draft = parseReceipt(page, itemTop: 40, priceColumnLeft: 350);
      final findings = reviewFindingsForDraft(draft);
      final geometry = findings.indexWhere(
        (f) => f.issue == ParseIssue.ambiguousGeometry,
      );
      final first = findings.indexWhere(
        (f) => f.issue == ParseIssue.unassignedSource,
      );
      expect(
        findings.where((f) => f.issue == ParseIssue.unassignedSource).length,
        2,
      );
      expect(
        unreviewedOmissions(draft.evidenceCoverage!, findings, {geometry}),
        [crossing, companion],
      );
      expect(unreviewedOmissions(draft.evidenceCoverage!, findings, {first}), [
        companion,
      ]);
      expect(
        unreviewedOmissions(draft.evidenceCoverage!, findings, {
          first,
          first + 1,
        }),
        isEmpty,
      );
      expect(unreviewedOmissions(draft.evidenceCoverage!, findings, {}), [
        crossing,
        companion,
      ]);
      expect(draft.evidenceCoverage!.unassignedWords.length, 2);
      expect(() => findings.clear(), throwsUnsupportedError);
    },
  );
}
