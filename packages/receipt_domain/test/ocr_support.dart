import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'support.dart' show id;

class OcrFixture {
  OcrFixture({ReceiptDraft? source}) {
    draft =
        source ??
        parseReceipt(
          OcrPage(500, 500, [
            OcrWord('16.11.2026', PixelBox(10, 10, 150, 26)),
            OcrWord('MILK', PixelBox(10, 70, 150, 86)),
            OcrWord('2,00', PixelBox(400, 70, 480, 86)),
            OcrWord('YHTEENSÄ', PixelBox(10, 220, 200, 236)),
            OcrWord('2,00', PixelBox(400, 220, 480, 236)),
          ]),
          itemTop: 40,
          priceColumnLeft: 350,
        );
    originals = [for (final _ in draft.rows) Object()];
    for (var i = 0; i < originals.length; i++) {
      ids.retain(originals[i], id(3 + i));
    }
    rows = [
      for (var i = 0; i < draft.rows.length; i++)
        OcrReviewRow(
          originals[i],
          ReviewRowInput(
            draft.rows[i].name,
            formatCents(draft.rows[i].cents),
            draft.rows[i].kind,
          ),
          true,
          draft.rowEvidence[i],
        ),
    ];
    total = formatCents(draft.printedTotal!);
  }
  late final ReceiptDraft draft;
  late final List<Object> originals;
  final ids = ReviewRowIds();
  late List<OcrReviewRow> rows;
  late String total;
  String branchName = 'TEST BRANCH', date = '16.11.2026';
  bool branchConfirmed = true;
  final decisions = <int, FindingEvidenceDecision>{};
  List<ParseFinding>? findings;
  ReceiptBranch get branch => ReceiptBranch(id: id(2), name: branchName);
  OcrReviewSnapshot get snapshot =>
      OcrReviewSnapshot(draft, branchName, date, total, branchConfirmed, rows);
  OcrEvidenceAudit audit({
    bool image = true,
    bool page = true,
    PageEvidenceApproval? approval,
  }) {
    final current = snapshot;
    return OcrEvidenceAudit(
      snapshot: current,
      findings: findings ?? reviewFindingsForDraft(draft),
      decisions: decisions,
      originalRowIds: originals,
      imageMatchesSource: image,
      pageApproval: page
          ? approval ??
                PageEvidenceApproval(
                  current,
                  'PRIVATE NOTE',
                  headerCompared: true,
                  footerCompared: true,
                  layoutCompared: true,
                  imageComplete: true,
                )
          : null,
    );
  }

  OcrEvidenceAudit receiptAudit({
    ReceiptReviewApproval? approval,
    bool image = true,
  }) => OcrEvidenceAudit(
    snapshot: snapshot,
    findings: findings ?? reviewFindingsForDraft(draft),
    decisions: decisions,
    originalRowIds: originals,
    imageMatchesSource: image,
    pageApproval: null,
    policy: OcrReviewPolicy.receipt,
    receiptApproval: approval,
  );

  OcrReviewChecks checks({
    OcrEvidenceAudit? current,
    Map<Object, OcrRowDetails> details = const {},
    bool dateChecked = true,
    bool totalChecked = true,
    List<RevisionId> heads = const [],
  }) => OcrReviewChecks(
    audit: current ?? audit(),
    branch: branch,
    receiptId: id(1),
    rowIds: ids,
    rowDetails: details,
    expectedHeads: heads,
    mutationId: id(99),
    dateReviewed: dateChecked,
    totalReviewed: totalChecked,
  );
  OcrReceiptConfirmation confirm({
    Map<Object, OcrRowDetails> details = const {},
  }) =>
      checks(details: details)
          .confirm(reviewedAtMs: BigInt.from(123), appVersion: 'ocr-test');
  ReviewedReceipt save({
    OcrEvidenceAudit? current,
    OcrReceiptConfirmation? confirmation,
    Map<Object, OcrRowDetails> details = const {},
    List<RevisionId> heads = const [],
  }) => ReviewedReceipt.ocr(
    current: current ?? audit(),
    branch: branch,
    rowDetails: details,
    expectedHeads: heads,
    confirmation: confirmation ?? confirm(details: details),
  );
}
