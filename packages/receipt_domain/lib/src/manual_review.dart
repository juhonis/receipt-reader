part of '../receipt_domain.dart';

/// Snapshot-bound manual checklist. The app must use this only for manual entry;
/// an OCR-origin session must use the live-evidence adapter, never relabel.
final class ManualReviewChecks {
  ManualReviewChecks({
    required ReceiptSnapshot snapshot,
    required Iterable<RevisionId> expectedHeads,
    required this.mutationId,
    required this.branchReviewed,
    required this.dateReviewed,
    required this.totalReviewed,
    required Iterable<DurableId> reviewedRowIds,
  }) : _snapshotJson = ReceiptSnapshotCodec.encode(snapshot),
       _expectedHeads = _heads(expectedHeads),
       _rowIds = List.unmodifiable(snapshot.items.map((row) => row.id)),
       reviewedRowIds = Set.unmodifiable(reviewedRowIds);

  final String _snapshotJson;
  final List<RevisionId> _expectedHeads;
  final List<DurableId> _rowIds;
  final DurableId mutationId;
  final bool branchReviewed, dateReviewed, totalReviewed;
  final Set<DurableId> reviewedRowIds;

  /// A separate user action after the field and row checks. No boolean flag can
  /// be passed directly to ReviewedReceipt to authorize a local write.
  ManualReceiptConfirmation confirm({
    required BigInt reviewedAtMs,
    required String appVersion,
  }) {
    _require(
      branchReviewed && dateReviewed && totalReviewed,
      'review',
      'uncheckedFields',
    );
    _require(
      reviewedRowIds.length == _rowIds.length &&
          _rowIds.every(reviewedRowIds.contains),
      'review.rows',
      'uncheckedOrForeignRows',
    );
    return ManualReceiptConfirmation._(
      this,
      checkedInt64(reviewedAtMs, 'reviewedAtMs', nonnegative: true),
      _text(appVersion, 'appVersion'),
    );
  }
}

final class ManualReceiptConfirmation {
  const ManualReceiptConfirmation._(
    this._checks,
    this.reviewedAtMs,
    this.appVersion,
  );
  final ManualReviewChecks _checks;
  final BigInt reviewedAtMs;
  final String appVersion;
}

/// Historical assertions are data; only live review constructors authorize writes.
sealed class ReceiptReviewRecord {
  ReceiptReviewRecord._(
    this.reviewedAtMs,
    this.appVersion,
    Iterable<RevisionId> heads,
    Iterable<DurableId> rows,
  ) : expectedHeads = _heads(heads),
      reviewedRowIds = List.unmodifiable(rows);
  final BigInt reviewedAtMs;
  final String appVersion;
  final List<RevisionId> expectedHeads;
  /// All rows for full receipt approvals; only changed product rows for policy 4.
  final List<DurableId> reviewedRowIds;
  String get source;
  int get policyVersion;
}

final class ManualReviewRecord extends ReceiptReviewRecord {
  ManualReviewRecord._(super.at, super.app, super.heads, super.rows)
    : super._();
  @override
  String get source => 'manual';
  @override
  int get policyVersion => 1;
}

/// Serializable structured history; decoding is not human confirmation.
final class ReceiptDocument {
  const ReceiptDocument._(this.snapshot, this.review);
  final ReceiptSnapshot snapshot;
  final ReceiptReviewRecord review;
  String get sha256Hex =>
      sha256.convert(utf8.encode(ReceiptDocumentCodec.encode(this))).toString();
}

/// Local save command. No SQL writes or event identities are assigned.
/// The repository rechecks catalog dependencies, expected heads and
/// durable row ownership in its write transaction.
final class ReviewedReceipt {
  ReviewedReceipt.manual({
    required ReceiptSnapshot current,
    required Iterable<RevisionId> expectedHeads,
    required ManualReceiptConfirmation confirmation,
  }) : mutationId = confirmation._checks.mutationId,
       document = _build(current, expectedHeads, confirmation);

  ReviewedReceipt.ocr({
    required OcrEvidenceAudit current,
    required ReceiptBranch branch,
    required Map<Object, OcrRowDetails> rowDetails,
    required Iterable<RevisionId> expectedHeads,
    required OcrReceiptConfirmation confirmation,
  }) : mutationId = confirmation._checks.mutationId,
       document = _buildOcr(
         current,
         branch,
         rowDetails,
         expectedHeads,
         confirmation,
       );

  ReviewedReceipt.productLinks({required ProductLinkConfirmation confirmation})
    : mutationId = confirmation._checks.mutationId,
      document = confirmation._checks._document(
        confirmation.reviewedAtMs,
        confirmation.appVersion,
      );

  static ReceiptDocument _build(
    ReceiptSnapshot current,
    Iterable<RevisionId> expectedHeads,
    ManualReceiptConfirmation confirmation,
  ) {
    final checks = confirmation._checks;
    _require(
      ReceiptSnapshotCodec.encode(current) == checks._snapshotJson,
      'review',
      'staleContent',
    );
    final heads = _heads(expectedHeads);
    _require(
      heads.length == checks._expectedHeads.length &&
          Iterable<int>.generate(heads.length)
              .every((i) => heads[i] == checks._expectedHeads[i]),
      'review',
      'staleHeads',
    );
    return ReceiptDocument._(
      current,
      ManualReviewRecord._(
        confirmation.reviewedAtMs,
        confirmation.appVersion,
        heads,
        current.items.map((item) => item.id),
      ),
    );
  }

  final DurableId mutationId;
  final ReceiptDocument document;
}
