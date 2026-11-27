import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

ReceiptDraft overlapDraft() => parseReceipt(
  OcrPage(500, 500, [
    OcrWord('19.11.2026', PixelBox(10, 10, 200, 26)),
    OcrWord('TEST', PixelBox(10, 70, 150, 86)),
    OcrWord('PACK', PixelBox(100, 70, 200, 86)),
    OcrWord('2,00', PixelBox(400, 70, 480, 86)),
    OcrWord('YHTEENSÄ', PixelBox(10, 150, 200, 166)),
    OcrWord('2,00', PixelBox(400, 150, 480, 166)),
  ]),
  itemTop: 40,
  priceColumnLeft: 350,
);

void main() {
  test(
    'boundary acceptance still requires every cut word to be accounted for',
    () {
      final draft = parseReceipt(
        OcrPage(500, 500, [
          OcrWord('19.11.2026', PixelBox(10, 10, 200, 26)),
          OcrWord('TEST PACK', PixelBox(10, 70, 200, 86)),
          OcrWord('2,00', PixelBox(400, 70, 480, 86)),
          OcrWord('YHTEENSÄ', PixelBox(10, 150, 200, 166)),
          OcrWord('2,00', PixelBox(400, 150, 480, 166)),
        ]),
        itemTop: 80,
        priceColumnLeft: 350,
      );
      final row = Object();
      final findings = reviewFindingsForDraft(draft, streamlined: true);
      final snapshot = OcrReviewSnapshot(
        draft,
        'TEST BRANCH',
        '19.11.2026',
        '2,00',
        true,
        [
          OcrReviewRow(
            row,
            const ReviewRowInput('TEST PACK', '2,00', LineKind.product),
            true,
            draft.evidenceCoverage!.unassignedWords,
          ),
        ],
      );
      final decisions = <int, FindingEvidenceDecision>{
        for (var i = 0; i < findings.length; i++)
          i: isGeometryFinding(findings[i])
              ? FindingEvidenceDecision(
                  note: '',
                  compared: true,
                  geometrySnapshot: snapshot,
                )
              : FindingEvidenceDecision(
                  note: '',
                  compared: true,
                  rowKind: RowEvidenceKind.financialRow,
                  target: row,
                ),
      };
      OcrEvidenceAudit audit() => OcrEvidenceAudit(
        snapshot: snapshot,
        findings: findings,
        decisions: decisions,
        originalRowIds: [],
        imageMatchesSource: true,
        pageApproval: null,
        policy: OcrReviewPolicy.receipt,
        receiptApproval: ReceiptReviewApproval(
          snapshot,
          ReceiptReviewMethod.quick,
        ),
      );
      expect(audit().ready, isTrue);
      decisions.remove(
        findings.indexWhere((f) => f.issue == ParseIssue.unassignedSource),
      );
      expect(audit().ready, isFalse);
      expect(audit().resolvableGeometry, isEmpty);
    },
  );
  test('receipt review asks once for covered overlap instead of classifying every word', () {
    final draft = overlapDraft(), row = Object();
    final findings = reviewFindingsForDraft(draft, streamlined: true);
    expect(
      findings.where((f) => f.issue == ParseIssue.geometrySource),
      isEmpty,
    );
    expect(
      reviewFindingsForDraft(draft)
          .where((f) => f.issue == ParseIssue.geometrySource),
      isNotEmpty,
    );
    final snapshot = OcrReviewSnapshot(
      draft,
      'TEST BRANCH',
      '19.11.2026',
      '2,00',
      true,
      [
        OcrReviewRow(
          row,
          ReviewRowInput(draft.rows.single.name, '2,00', LineKind.product),
          false,
          draft.rowEvidence.single,
        ),
      ],
    );
    OcrEvidenceAudit audit(Map<int, FindingEvidenceDecision> decisions) =>
        OcrEvidenceAudit(
          snapshot: snapshot,
          findings: findings,
          decisions: decisions,
          originalRowIds: [row],
          imageMatchesSource: true,
          pageApproval: null,
          policy: OcrReviewPolicy.receipt,
          receiptApproval: ReceiptReviewApproval(
            snapshot,
            ReceiptReviewMethod.quick,
          ),
        );
    expect(audit({}).ready, isFalse);
    final index = findings.indexWhere(isGeometryFinding);
    expect(audit({}).resolvableGeometry, contains(index));
    expect(
      audit({
        index: FindingEvidenceDecision(
          note: '',
          compared: true,
          geometrySnapshot: snapshot,
        ),
      }).ready,
      isTrue,
    );
    expect(
      audit({
        index: FindingEvidenceDecision(
          note: '',
          compared: false,
          geometrySnapshot: snapshot,
        ),
      }).ready,
      isFalse,
    );
  });

  test(
    'empty notes do not replace explicit page approval or image evidence',
    () {
      final draft = overlapDraft(), row = Object();
      final snapshot = OcrReviewSnapshot(
        draft,
        'TEST BRANCH',
        '19.11.2026',
        '2,00',
        true,
        [
          OcrReviewRow(
            row,
            ReviewRowInput(draft.rows.single.name, '2,00', LineKind.product),
            true,
            draft.rowEvidence.single,
          ),
        ],
      );
      expect(
        PageEvidenceApproval(
          snapshot,
          '',
          headerCompared: true,
          footerCompared: true,
          layoutCompared: true,
          imageComplete: true,
        ).validFor(snapshot),
        isTrue,
      );
      expect(
        PageEvidenceApproval(
          snapshot,
          '',
          headerCompared: false,
          footerCompared: true,
          layoutCompared: true,
          imageComplete: true,
        ).validFor(snapshot),
        isFalse,
      );
    },
  );

  test('orphan information may be explicitly classified but posted money cannot be discarded', () {
    final word = OcrWord('TEST INFORMATION', PixelBox(10, 10, 200, 26));
    for (final finding in [
      ParseFinding(ParseIssue.quantityWithoutProduct, words: [word]),
      ParseFinding(
        ParseIssue.discountNeedsReview,
        words: [word],
        discountKind: DiscountFindingKind.explanatoryPrice,
      ),
    ]) {
      expect(
        canResolveRowEvidence(finding, RowEvidenceKind.explanatoryText),
        isTrue,
      );
      expect(
        canResolveRowEvidence(
          finding,
          RowEvidenceKind.financialRow,
          target: const ReviewRowInput('TEST', '2,00', LineKind.product),
        ),
        isFalse,
      );
    }
    expect(
      canResolveRowEvidence(
        ParseFinding(ParseIssue.quantityMismatch, rowIndex: 0, words: [word]),
        RowEvidenceKind.explanatoryText,
      ),
      isFalse,
    );
    expect(
      canResolveRowEvidence(
        ParseFinding(
          ParseIssue.discountNeedsReview,
          rowIndex: 0,
          words: [word],
          discountKind: DiscountFindingKind.postedDiscount,
        ),
        RowEvidenceKind.explanatoryText,
      ),
      isFalse,
    );
  });
}
