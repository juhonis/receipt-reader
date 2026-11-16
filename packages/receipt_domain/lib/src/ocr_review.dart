part of '../receipt_domain.dart';

/// Parser build associated with the supported OCR evidence policy.
const receiptOcrParserVersion = 'receipt_parser/0.1.0';

/// Extra financial semantics not represented by temporary OCR row inputs.
final class OcrRowDetails {
  const OcrRowDetails({
    this.depositParent,
    this.standaloneDeposit = false,
    this.adjustmentReason,
  });
  final Object? depositParent;
  final bool standaloneDeposit;
  final String? adjustmentReason;
}

/// A structured disposition, deliberately excluding OCR words and free-text notes.
final class OcrDecisionRecord {
  const OcrDecisionRecord._(
    this.issue,
    this.scope,
    this.sourceRowId,
    this.targetRowId,
    this.rowKind,
    this.relationshipKind,
    this.discountKind,
    this.geometryKind,
    this.nameHandled,
  );
  final ParseIssue issue;
  final FindingScope scope;
  final DurableId? sourceRowId, targetRowId;
  final RowEvidenceKind? rowKind;
  final ReviewRelationshipKind? relationshipKind;
  final DiscountFindingKind? discountKind;
  final GeometryFindingKind? geometryKind;
  final bool nameHandled;
}

final class OcrReviewRecord extends ReceiptReviewRecord {
  OcrReviewRecord._(
    super.at,
    super.app,
    super.heads,
    super.rows,
    Iterable<DurableId> originalRows,
    Iterable<OcrDecisionRecord> decisions,
    this.originalFindingCount,
  ) : originalRowIds = List.unmodifiable(originalRows),
      decisions = List.unmodifiable(decisions),
      super._();
  final List<DurableId> originalRowIds;
  final List<OcrDecisionRecord> decisions;
  final int originalFindingCount;
  @override
  String get source => 'ocr';
  @override
  int get policyVersion => 2;
}

/// Captures a ready live audit plus the exact durable mapping before final review.
/// No image, OCR dump or written evidence explanation enters this command.
final class OcrReviewChecks {
  OcrReviewChecks({
    required OcrEvidenceAudit audit,
    required ReceiptBranch branch,
    required DurableId receiptId,
    required ReviewRowIds rowIds,
    required Map<Object, OcrRowDetails> rowDetails,
    required Iterable<RevisionId> expectedHeads,
    required this.mutationId,
    required this.dateReviewed,
    required this.totalReviewed,
  }) : _audit = audit,
       _receiptId = receiptId,
       _rowIds = rowIds,
       _heads = List.unmodifiable(expectedHeads) {
    final adapted = _adaptOcr(audit, branch, receiptId, rowIds, rowDetails);
    _snapshotJson = ReceiptSnapshotCodec.encode(adapted.$1);
    _evidenceJson = _encode(
      _ocrEvidenceObject(
        adapted.$2,
        adapted.$3,
        audit.snapshot.draft.findings.length,
      ),
    );
  }
  final OcrEvidenceAudit _audit;
  final DurableId _receiptId, mutationId;
  final ReviewRowIds _rowIds;
  final List<RevisionId> _heads;
  final bool dateReviewed, totalReviewed;
  late final String _snapshotJson, _evidenceJson;

  OcrReceiptConfirmation confirm({
    required BigInt reviewedAtMs,
    required String appVersion,
  }) {
    _require(dateReviewed && totalReviewed, 'review', 'uncheckedFields');
    return OcrReceiptConfirmation._(
      this,
      checkedInt64(reviewedAtMs, 'reviewedAtMs', nonnegative: true),
      _text(appVersion, 'appVersion'),
    );
  }
}

final class OcrReceiptConfirmation {
  const OcrReceiptConfirmation._(
    this._checks,
    this.reviewedAtMs,
    this.appVersion,
  );
  final OcrReviewChecks _checks;
  final BigInt reviewedAtMs;
  final String appVersion;
}

ReceiptDocument _buildOcr(
  OcrEvidenceAudit audit,
  ReceiptBranch branch,
  Map<Object, OcrRowDetails> details,
  Iterable<RevisionId> heads,
  OcrReceiptConfirmation confirmation,
) {
  final checks = confirmation._checks;
  _require(
    checks._audit.snapshot.matches(audit.snapshot),
    'review',
    'staleEvidence',
  );
  final adapted = _adaptOcr(
    audit,
    branch,
    checks._receiptId,
    checks._rowIds,
    details,
  );
  _require(
    ReceiptSnapshotCodec.encode(adapted.$1) == checks._snapshotJson &&
        _encode(
              _ocrEvidenceObject(
                adapted.$2,
                adapted.$3,
                audit.snapshot.draft.findings.length,
              ),
            ) ==
            checks._evidenceJson,
    'review',
    'staleContent',
  );
  final currentHeads = _heads(heads), approvedHeads = _heads(checks._heads);
  _require(
    currentHeads.length == approvedHeads.length &&
        Iterable<int>.generate(currentHeads.length)
            .every((i) => currentHeads[i] == approvedHeads[i]),
    'review',
    'staleHeads',
  );
  _validateOcrRecord(adapted.$1, adapted.$2, adapted.$3);
  return ReceiptDocument._(
    adapted.$1,
    OcrReviewRecord._(
      confirmation.reviewedAtMs,
      confirmation.appVersion,
      currentHeads,
      adapted.$1.items.map((r) => r.id),
      adapted.$2,
      adapted.$3,
      audit.snapshot.draft.findings.length,
    ),
  );
}

(ReceiptSnapshot, List<DurableId>, List<OcrDecisionRecord>) _adaptOcr(
  OcrEvidenceAudit audit,
  ReceiptBranch branch,
  DurableId receiptId,
  ReviewRowIds rowIds,
  Map<Object, OcrRowDetails> details,
) {
  final current = audit.snapshot;
  _require(
    audit.ready && current.rows.every((r) => r.compared),
    'review',
    'evidenceNotReady',
  );
  _require(
    current.branchConfirmed && current.branch.trim() == branch.name,
    'review.branch',
    'mismatch',
  );
  _require(
    details.keys.every((id) => current.rows.any((r) => identical(r.id, id))),
    'review.rows',
    'foreignDetails',
  );
  final validation = ReviewValidation(
    branch: current.branch,
    dateText: current.date,
    totalText: current.total,
    rows: current.rows.map((r) => r.input).toList(),
    branchConfirmed: current.branchConfirmed,
    reviewed: true,
  );
  _require(validation.complete, 'review', 'invalidReceipt');
  DurableId? targetId(Object? target) {
    if (target == null) return null;
    _require(
      current.rows.any((r) => identical(r.id, target)),
      'review.target',
      'missing',
    );
    return rowIds.idFor(target);
  }

  final originals = audit.originalRowIds.map(rowIds.idFor).toList();
  final decisions = <OcrDecisionRecord>[];
  for (var i = 0; i < audit.findings.length; i++) {
    final finding = audit.findings[i], decision = audit.decisions[i];
    _require(
      decision != null && decision.compared && decision.note.trim().isNotEmpty,
      'review.finding',
      'unchecked',
    );
    final source = finding.rowIndex == null
        ? null
        : finding.rowIndex! >= 0 && finding.rowIndex! < originals.length
        ? originals[finding.rowIndex!]
        : null;
    _require(
      finding.rowIndex == null || source != null,
      'review.finding',
      'sourceIndex',
    );
    decisions.add(
      OcrDecisionRecord._(
        finding.issue,
        finding.scope,
        source,
        targetId(decision!.target),
        decision.rowKind,
        decision.relationshipKind,
        finding.discountKind,
        finding.geometryKind,
        decision.nameHandled,
      ),
    );
  }
  final items = <ReceiptItemSnapshot>[];
  for (final row in current.rows) {
    final id = rowIds.idFor(row.id), input = row.input;
    final extra = details[row.id] ?? const OcrRowDetails();
    _require(
      input.kind == LineKind.adjustment
          ? extra.adjustmentReason != null
          : extra.adjustmentReason == null,
      'row.adjustmentReason',
      'requiredOnlyForAdjustment',
    );
    _require(
      input.kind == LineKind.deposit ||
          (!extra.standaloneDeposit && extra.depositParent == null),
      'row.parent',
      'unsupportedDetails',
    );
    DurableId? parent;
    DiscountScope? scope;
    if (input.kind == LineKind.discount) {
      final links = decisions
          .where(
            (d) =>
                d.sourceRowId == id &&
                d.discountKind == DiscountFindingKind.postedDiscount,
          )
          .toList();
      _require(links.length == 1, 'row.discount', 'ambiguousRelationship');
      final link = links.single;
      _require(
        link.relationshipKind == ReviewRelationshipKind.receiptDiscount ||
            link.relationshipKind == ReviewRelationshipKind.productDiscount,
        'row.discount',
        'unreviewedRelationship',
      );
      scope = link.relationshipKind == ReviewRelationshipKind.receiptDiscount
          ? DiscountScope.receipt
          : DiscountScope.item;
      parent = link.targetRowId;
    } else if (input.kind == LineKind.deposit) {
      _require(
        extra.standaloneDeposit != (extra.depositParent != null),
        'row.parent',
        'unreviewedDeposit',
      );
      parent = targetId(extra.depositParent);
    }
    final sourceIndex = audit.originalRowIds.indexWhere(
      (r) => identical(r, row.id),
    );
    final hasQuantity = input.quantityState != QuantityReviewState.absent;
    items.add(
      ReceiptItemSnapshot(
        id: id,
        name: input.name.trim(),
        rawName: sourceIndex < 0
            ? null
            : current.draft.rows[sourceIndex].name.trim(),
        kind: input.kind,
        cents: parseCents(input.amount)!,
        quantityValue: hasQuantity ? parseFixed(input.quantity, 6) : null,
        quantityScale: hasQuantity ? 6 : null,
        quantityUnit: hasQuantity ? input.unit : null,
        rateMicros: hasQuantity ? parseFixed(input.rate, 6) : null,
        parentItemId: parent,
        discountScope: scope,
        adjustmentReason: extra.adjustmentReason?.trim(),
      ),
    );
  }
  return (
    ReceiptSnapshot(
      id: receiptId,
      branch: branch,
      date: StoredReceiptDate.parse(current.date),
      totalCents: parseCents(current.total)!,
      items: items,
    ),
    originals,
    decisions,
  );
}

Map<String, Object?> _ocrEvidenceObject(
  List<DurableId> originals,
  List<OcrDecisionRecord> decisions,
  int originalFindingCount,
) => {
  'parser_version': receiptOcrParserVersion,
  'image_matches_source': true,
  'rows_compared': true,
  'page_header_compared': true,
  'page_footer_compared': true,
  'page_layout_compared': true,
  'image_complete': true,
  'original_finding_count': originalFindingCount.toString(),
  'reviewed_finding_count': decisions.length.toString(),
  'source_disposition_count': decisions
      .where(
        (d) => [
          ParseIssue.geometrySource,
          ParseIssue.unassignedSource,
          ParseIssue.removedSource,
        ].contains(d.issue),
      )
      .length
      .toString(),
  'unresolved_count': '0',
  'original_row_ids': originals.map((id) => id.value).toList(),
  'decisions': [
    for (final d in decisions)
      {
        'issue': d.issue.name,
        'scope': d.scope.name,
        'source_row_id': d.sourceRowId?.value,
        'target_row_id': d.targetRowId?.value,
        'row_kind': d.rowKind?.name,
        'relationship_kind': d.relationshipKind?.name,
        'discount_kind': d.discountKind?.name,
        'geometry_kind': d.geometryKind?.name,
        'name_handled': d.nameHandled,
      },
  ],
};
