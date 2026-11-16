import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

class Fixture {
  Fixture({
    double slope = 0,
    bool overlap = false,
    bool quantity = false,
    bool second = false,
  }) {
    draft = parseReceipt(
      OcrPage(500, 500, [
        OcrWord('16.11.2026', PixelBox(10, 10, 150, 26)),
        OcrWord('MILK', PixelBox(10, 70, 150, 86)),
        if (overlap) OcrWord('MILK', PixelBox(15, 70, 155, 86)),
        OcrWord('2,00', PixelBox(400, 70, 480, 86)),
        if (quantity)
          OcrWord('2 kpl 1,00 EUR/kpl', PixelBox(10, 100, 300, 116)),
        if (second) ...[
          OcrWord('BREAD', PixelBox(10, 150, 150, 166)),
          OcrWord('1,00', PixelBox(400, 150, 480, 166)),
        ],
        OcrWord('YHTEENSÄ', PixelBox(10, 220, 200, 236)),
        OcrWord(second ? '3,00' : '2,00', PixelBox(400, 220, 480, 236)),
        OcrWord('ALV', PixelBox(10, 280, 100, 296)),
      ], baselineSlope: slope),
      itemTop: 40,
      priceColumnLeft: 350,
    );
    ids = [for (final _ in draft.rows) Object()];
    snapshot = OcrReviewSnapshot(
      draft,
      'TEST BRANCH',
      '16.11.2026',
      second ? '3,00' : '2,00',
      true,
      [
        for (var i = 0; i < draft.rows.length; i++)
          OcrReviewRow(
            ids[i],
            ReviewRowInput(
              draft.rows[i].name,
              formatCents(draft.rows[i].cents),
              draft.rows[i].kind,
              quantity: draft.rows[i].quantity == null
                  ? ''
                  : formatFixed(
                      draft.rows[i].quantity!.value,
                      draft.rows[i].quantity!.scale,
                    ),
              rate: draft.rows[i].rateMicros == null
                  ? ''
                  : formatFixed(draft.rows[i].rateMicros!, 6),
              unit: draft.rows[i].quantity?.unit ?? QuantityUnit.unknown,
            ),
            true,
            draft.rowEvidence[i],
          ),
      ],
    );
  }
  late final ReceiptDraft draft;
  late final List<Object> ids;
  late final OcrReviewSnapshot snapshot;
}

PageEvidenceApproval approve(OcrReviewSnapshot snapshot) =>
    PageEvidenceApproval(
      snapshot,
      'Compared all receipt evidence',
      headerCompared: true,
      footerCompared: true,
      layoutCompared: true,
      imageComplete: true,
    );

OcrReviewSnapshot withRows(
  Fixture f,
  List<OcrReviewRow> rows, {
  String? total,
}) => OcrReviewSnapshot(
  f.draft,
  f.snapshot.branch,
  f.snapshot.date,
  total ?? f.snapshot.total,
  true,
  rows,
);

OcrEvidenceAudit audit(
  Fixture f, {
  OcrReviewSnapshot? snapshot,
  bool image = true,
  bool page = true,
  PageEvidenceApproval? approval,
  List<ParseFinding>? findings,
  Map<int, FindingEvidenceDecision> decisions = const {},
}) => OcrEvidenceAudit(
  snapshot: snapshot ?? f.snapshot,
  imageMatchesSource: image,
  originalRowIds: f.ids,
  findings: findings ?? reviewFindingsForDraft(f.draft),
  decisions: decisions,
  pageApproval: page ? approval ?? approve(snapshot ?? f.snapshot) : null,
);

void main() {
  test('source/finding context cannot be dropped and approval outputs are immutable', () {
    final f = Fixture(slope: .01);
    expect(
      audit(f, findings: []).blockers,
      contains(OcrEvidenceBlocker.sourceContext),
    );
    final invalid = withRows(f, [
      OcrReviewRow(f.ids.single, f.snapshot.rows.single.input, true, [
        OcrWord('UNRELATED', PixelBox(1, 1, 2, 2)),
      ]),
    ]);
    expect(
      audit(f, snapshot: invalid).blockers,
      contains(OcrEvidenceBlocker.sourceContext),
    );
    expect(() => f.snapshot.rows.clear(), throwsUnsupportedError);
    expect(() => f.snapshot.rows.single.words.clear(), throwsUnsupportedError);
    expect(
      PageEvidenceApproval(
        f.snapshot,
        'Checked',
        headerCompared: true,
        footerCompared: true,
        layoutCompared: true,
        imageComplete: false,
      ).validFor(f.snapshot),
      isFalse,
    );
  });

  test('duplicate disposition cannot silently discard original quantity information', () {
    final f = Fixture(quantity: true, second: true);
    final snapshot = withRows(f, [f.snapshot.rows.last]);
    final findings = [
      ...reviewFindingsForDraft(f.draft),
      for (final word in f.draft.rowEvidence.first)
        ParseFinding(
          ParseIssue.removedSource,
          scope: FindingScope.item,
          words: [word],
        ),
    ];
    final decisions = {
      for (var i = 0; i < findings.length; i++)
        i: FindingEvidenceDecision(
          note: 'Duplicate source',
          compared: true,
          rowKind: RowEvidenceKind.duplicateOcr,
          target: f.ids.last,
        ),
    };
    expect(
      audit(
        f,
        snapshot: snapshot,
        findings: findings,
        decisions: decisions,
      ).blockers,
      contains(OcrEvidenceBlocker.originalRows),
    );
  });

  test('two orphan quantity claims cannot approve the same product', () {
    final draft = parseReceipt(
      OcrPage(500, 500, [
        OcrWord('2 kpl 1,00 EUR/kpl', PixelBox(10, 40, 300, 56)),
        OcrWord('2 kpl 1,00 EUR/kpl', PixelBox(10, 70, 300, 86)),
        OcrWord('MILK', PixelBox(10, 100, 150, 116)),
        OcrWord('2,00', PixelBox(400, 100, 480, 116)),
        OcrWord('YHTEENSÄ', PixelBox(10, 200, 200, 216)),
        OcrWord('2,00', PixelBox(400, 200, 480, 216)),
      ]),
      itemTop: 35,
      priceColumnLeft: 350,
    );
    final id = Object();
    final snapshot = OcrReviewSnapshot(
      draft,
      'TEST',
      '16.11.2026',
      '2,00',
      true,
      [
        OcrReviewRow(
          id,
          const ReviewRowInput(
            'MILK',
            '2,00',
            LineKind.product,
            quantity: '2',
            rate: '1',
            unit: QuantityUnit.piece,
          ),
          true,
          draft.rowEvidence.single,
        ),
      ],
    );
    final findings = reviewFindingsForDraft(draft);
    expect(findings.length, 2);
    final decisions = {
      for (var i = 0; i < findings.length; i++)
        i: FindingEvidenceDecision(
          note: 'Checked quantity',
          compared: true,
          relationshipKind: ReviewRelationshipKind.quantity,
          target: id,
        ),
    };
    final result = OcrEvidenceAudit(
      snapshot: snapshot,
      originalRowIds: [id],
      findings: findings,
      decisions: decisions,
      imageMatchesSource: true,
      pageApproval: approve(snapshot),
    );
    expect(result.blockers, contains(OcrEvidenceBlocker.quantityRelationships));
    expect(result.ready, isFalse);
  });
  test('supported evidence readiness and arithmetic/final confirmation remain independent', () {
    final f = Fixture();
    expect(audit(f).ready, isTrue);
    ReviewValidation validation(OcrReviewSnapshot snapshot, bool reviewed) =>
        ReviewValidation(
          branch: snapshot.branch,
          dateText: snapshot.date,
          totalText: snapshot.total,
          rows: snapshot.rows.map((r) => r.input).toList(),
          branchConfirmed: true,
          reviewed: reviewed,
          hasUnresolvedParserIssues: !audit(f, snapshot: snapshot).ready,
        );
    expect(validation(f.snapshot, false).complete, isFalse);
    expect(validation(f.snapshot, true).complete, isTrue);
    final mismatch = withRows(f, f.snapshot.rows, total: '2,01');
    expect(audit(f, snapshot: mismatch).ready, isTrue);
    expect(validation(mismatch, true).complete, isFalse);
  });

  test(
    'missing image, context, row comparison, and page approval fail closed',
    () {
      final f = Fixture();
      expect(
        audit(f, image: false).blockers,
        contains(OcrEvidenceBlocker.sourceContext),
      );
      expect(
        audit(f, page: false).blockers,
        contains(OcrEvidenceBlocker.pageReview),
      );
      final unchecked = withRows(f, [
        OcrReviewRow(
          f.ids.single,
          f.snapshot.rows.single.input,
          false,
          f.draft.rowEvidence.single,
        ),
      ]);
      expect(
        audit(f, snapshot: unchecked).blockers,
        contains(OcrEvidenceBlocker.rowReview),
      );
      final legacy = ReceiptDraft(
        f.draft.rows,
        f.draft.printedTotal,
        [],
        [],
        f.draft.date,
        [],
      );
      final legacySnapshot = OcrReviewSnapshot(
        legacy,
        'TEST',
        '16.11.2026',
        '2,00',
        true,
        f.snapshot.rows,
      );
      expect(
        OcrEvidenceAudit(
          snapshot: legacySnapshot,
          findings: [],
          decisions: {},
          originalRowIds: f.ids,
          imageMatchesSource: true,
          pageApproval: approve(legacySnapshot),
        ).ready,
        isFalse,
      );
    },
  );

  test('page approval rejects changed values and evidence links even when rows are marked compared', () {
    final f = Fixture();
    final original = f.snapshot.rows.single;
    for (final changed in [
      const ReviewRowInput('CORRECTED', '2,00', LineKind.product),
      const ReviewRowInput('MILK', '2,01', LineKind.product),
      const ReviewRowInput('MILK', '2,00', LineKind.adjustment),
      const ReviewRowInput(
        'MILK',
        '2,00',
        LineKind.product,
        quantity: '2',
        rate: '1',
        unit: QuantityUnit.piece,
      ),
    ]) {
      final snapshot = withRows(f, [
        OcrReviewRow(original.id, changed, true, original.words),
      ]);
      expect(
        audit(f, snapshot: snapshot, approval: approve(f.snapshot)).blockers,
        contains(OcrEvidenceBlocker.pageReview),
      );
    }
    final linked = withRows(f, [
      OcrReviewRow(original.id, original.input, true, [
        ...original.words,
        f.draft.parseContext!.page.words.first,
      ]),
    ]);
    expect(approve(f.snapshot).validFor(linked), isFalse);
    expect(
      approve(f.snapshot).validFor(withRows(f, f.snapshot.rows, total: '2,01')),
      isFalse,
    );
  });

  test('skew confirmation requires page/row review and a current geometry snapshot', () {
    final f = Fixture(slope: .01);
    final findings = reviewFindingsForDraft(f.draft);
    final index = findings.indexWhere(
      (finding) => finding.geometryKind == GeometryFindingKind.skew,
    );
    expect(audit(f).ready, isFalse);
    expect(audit(f).resolvableGeometry, {index});
    final decisions = {
      index: FindingEvidenceDecision(
        note: 'Checked skew against image',
        compared: true,
        geometrySnapshot: f.snapshot,
      ),
    };
    expect(audit(f, decisions: decisions).ready, isTrue);
    expect(audit(f, page: false, decisions: decisions).ready, isFalse);
    final changed = withRows(f, f.snapshot.rows, total: '2,01');
    expect(audit(f, snapshot: changed, decisions: decisions).ready, isFalse);
    final result = audit(f, decisions: decisions);
    expect(() => result.blockers.clear(), throwsUnsupportedError);
    expect(() => result.unresolved.clear(), throwsUnsupportedError);
    expect(() => result.decisions.clear(), throwsUnsupportedError);
  });

  test(
    'overlap needs individual source dispositions before geometry approval',
    () {
      final f = Fixture(overlap: true);
      final findings = reviewFindingsForDraft(f.draft);
      final geometry = findings.indexWhere(
        (finding) => finding.geometryKind == GeometryFindingKind.wordOverlap,
      );
      final decisions = <int, FindingEvidenceDecision>{};
      for (var i = 0; i < findings.length; i++) {
        if (findings[i].issue == ParseIssue.geometrySource) {
          decisions[i] = FindingEvidenceDecision(
            note: 'Explicitly compared this source word',
            compared: true,
            rowKind: RowEvidenceKind.duplicateOcr,
            target: f.ids.single,
          );
        }
      }
      expect(audit(f, decisions: {}).resolvableGeometry, isEmpty);
      expect(audit(f, decisions: decisions).resolvableGeometry, {geometry});
      expect(audit(f, decisions: decisions).ready, isFalse);
      decisions[geometry] = FindingEvidenceDecision(
        note: 'Overlap resolved through source-word review',
        compared: true,
        geometrySnapshot: f.snapshot,
      );
      expect(audit(f, decisions: decisions).ready, isTrue);
      decisions.remove(
        decisions.keys.firstWhere(
          (i) => findings[i].issue == ParseIssue.geometrySource,
        ),
      );
      expect(audit(f, decisions: decisions).ready, isFalse);
      expect(f.draft.rows.single.name, 'MILK MILK');
    },
  );

  test(
    'boundary issues require corrected parsing and cannot be acknowledged away',
    () {
      final f = Fixture();
      final draft = parseReceipt(
        f.draft.parseContext!.page,
        itemTop: 78,
        priceColumnLeft: 350,
      );
      final id = Object();
      final snapshot = OcrReviewSnapshot(
        draft,
        'TEST',
        '16.11.2026',
        '2,00',
        true,
        [
          OcrReviewRow(
            id,
            const ReviewRowInput('MILK', '2,00', LineKind.product),
            true,
            [],
          ),
        ],
      );
      final findings = reviewFindingsForDraft(draft);
      final decisions = <int, FindingEvidenceDecision>{
        for (var i = 0; i < findings.length; i++)
          i: findings[i].issue == ParseIssue.unassignedSource
              ? FindingEvidenceDecision(
                  note: 'Mapped missing word',
                  compared: true,
                  rowKind: RowEvidenceKind.financialRow,
                  target: id,
                )
              : FindingEvidenceDecision(
                  note: 'Cannot bypass boundary',
                  compared: true,
                  geometrySnapshot: snapshot,
                ),
      };
      final result = OcrEvidenceAudit(
        snapshot: snapshot,
        findings: findings,
        decisions: decisions,
        originalRowIds: [],
        imageMatchesSource: true,
        pageApproval: approve(snapshot),
      );
      expect(result.resolvableGeometry, isEmpty);
      expect(result.ready, isFalse);
    },
  );

  test('deleting a parsed row needs explicit duplicate/nonfinancial source accounting', () {
    final f = Fixture(second: true);
    final remaining = withRows(f, [f.snapshot.rows.last]);
    expect(
      audit(f, snapshot: remaining).blockers,
      contains(OcrEvidenceBlocker.originalRows),
    );
    final findings = [
      ...reviewFindingsForDraft(f.draft),
      for (final word in f.draft.rowEvidence.first)
        ParseFinding(
          ParseIssue.removedSource,
          scope: FindingScope.item,
          words: [word],
        ),
    ];
    final decisions = {
      for (var i = 0; i < findings.length; i++)
        i: FindingEvidenceDecision(
          note: 'Duplicate recognition of retained row',
          compared: true,
          rowKind: RowEvidenceKind.duplicateOcr,
          target: f.ids.last,
        ),
    };
    expect(
      audit(
        f,
        snapshot: remaining,
        findings: findings,
        decisions: decisions,
      ).ready,
      isTrue,
    );
    final invalid = {
      for (final i in decisions.keys)
        i: FindingEvidenceDecision(
          note: 'Unexplained deletion',
          compared: true,
        ),
    };
    expect(
      audit(
        f,
        snapshot: remaining,
        findings: findings,
        decisions: invalid,
      ).ready,
      isFalse,
    );
  });

  test('original quantity cannot disappear behind matching receipt totals', () {
    final f = Fixture(quantity: true);
    final without = withRows(f, [
      OcrReviewRow(
        f.ids.single,
        const ReviewRowInput('MILK', '2,00', LineKind.product),
        true,
        f.draft.rowEvidence.single,
      ),
    ]);
    expect(
      audit(f, snapshot: without).blockers,
      contains(OcrEvidenceBlocker.originalQuantities),
    );
  });

  test(
    'manual discounts and unreviewed findings block final evidence approval',
    () {
      final f = Fixture();
      final manualDiscount = OcrReviewRow(
        Object(),
        const ReviewRowInput('ALE', '-0,50', LineKind.discount),
        true,
        [],
      );
      final snapshot = withRows(f, [...f.snapshot.rows, manualDiscount]);
      expect(
        audit(f, snapshot: snapshot).blockers,
        contains(OcrEvidenceBlocker.discountRelationships),
      );
      final extra = [
        ...reviewFindingsForDraft(f.draft),
        ParseFinding(
          ParseIssue.unclassifiedRow,
          scope: FindingScope.item,
          words: [f.draft.parseContext!.page.words.first],
        ),
      ];
      expect(audit(f, findings: extra).ready, isFalse);
    },
  );
}
