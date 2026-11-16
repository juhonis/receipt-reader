part of '../receipt_domain.dart';

/// A persisted deletion assertion. Decoding one never authorizes a local write.
final class ReceiptTombstone {
  const ReceiptTombstone._(
    this.receiptId,
    this.expectedHead,
    this.documentSha256,
    this.source,
    this.deletedAtMs,
    this.appVersion,
  );
  final DurableId receiptId;
  final RevisionId expectedHead;
  final String documentSha256, source, appVersion;
  final BigInt deletedAtMs;
  String get sha256Hex => sha256
      .convert(utf8.encode(ReceiptTombstoneCodec.encode(this)))
      .toString();
}

/// Captures the exact saved receipt and head displayed before confirmation.
final class ReceiptDeletionChecks {
  ReceiptDeletionChecks({
    required ReceiptDocument document,
    required this.expectedHead,
    required this.mutationId,
    required this.receiptReviewed,
  }) : _document = document;
  final ReceiptDocument _document;
  final RevisionId expectedHead;
  final DurableId mutationId;
  final bool receiptReviewed;

  ReviewedReceiptDeletion confirm({
    required BigInt deletedAtMs,
    required String appVersion,
  }) {
    _require(receiptReviewed, 'deletion', 'uncheckedReceipt');
    return ReviewedReceiptDeletion._(
      mutationId,
      ReceiptTombstone._(
        _document.snapshot.id,
        expectedHead,
        _document.sha256Hex,
        _document.review.source,
        checkedInt64(deletedAtMs, 'deletedAtMs', nonnegative: true),
        _text(appVersion, 'appVersion'),
      ),
    );
  }
}

final class ReviewedReceiptDeletion {
  const ReviewedReceiptDeletion._(this.mutationId, this.tombstone);
  final DurableId mutationId;
  final ReceiptTombstone tombstone;
}

final class ReceiptTombstoneCodec {
  static String encode(ReceiptTombstone tombstone) => _encode({
    'payload_version': '1',
    'receipt_id': tombstone.receiptId.value,
    'deletion_policy_version': '1',
    'expected_head': _revisionObject(tombstone.expectedHead),
    'reviewed_document_sha256': tombstone.documentSha256,
    'source': tombstone.source,
    'receipt_reviewed': true,
    'deleted_at_ms': tombstone.deletedAtMs.toString(),
    'app_version': tombstone.appVersion,
  });
  static ReceiptTombstone decode(String json) => _canonicalDecode(json, (
    value,
  ) {
    final root = _object(value, [
      'payload_version',
      'receipt_id',
      'deletion_policy_version',
      'expected_head',
      'reviewed_document_sha256',
      'source',
      'receipt_reviewed',
      'deleted_at_ms',
      'app_version',
    ]);
    _require(
      root['payload_version'] == '1' && root['deletion_policy_version'] == '1',
      'deletion',
      'unsupported',
    );
    _require(root['receipt_reviewed'] == true, 'deletion', 'uncheckedReceipt');
    final digest = _string(root['reviewed_document_sha256']);
    _require(
      RegExp(r'^[0-9a-f]{64}$').hasMatch(digest),
      'deletion.digest',
      'invalid',
    );
    final source = _string(root['source']);
    _require(
      source == 'manual' || source == 'ocr',
      'deletion.source',
      'unsupported',
    );
    return ReceiptTombstone._(
      _id(root['receipt_id']),
      _readRevision(root['expected_head']),
      digest,
      source,
      checkedInt64(
        _integer(root['deleted_at_ms']),
        'deletedAtMs',
        nonnegative: true,
      ),
      _text(_string(root['app_version']), 'appVersion'),
    );
  }, encode);
}
