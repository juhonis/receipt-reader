part of '../receipt_domain.dart';

/// A live selection of catalog links; financial and OCR values cannot be edited.
final class ProductLinkReviewChecks {
  ProductLinkReviewChecks({
    required ReceiptDocument base,
    required RevisionId expectedHead,
    required Map<DurableId, ReceiptProductLink?> selections,
    required this.mutationId,
  }) : _base = base,
       _head = expectedHead,
       _selections = Map.unmodifiable(selections) {
    final rows = base.snapshot.items;
    _require(
      selections.isNotEmpty &&
          selections.keys.every(
            (id) => rows.any((r) => r.id == id && r.kind == LineKind.product),
          ),
      'productLinks',
      'invalidRows',
    );
    _require(
      _changedRows(base.snapshot, _snapshot).isNotEmpty,
      'productLinks',
      'unchanged',
    );
  }
  final ReceiptDocument _base;
  final RevisionId _head;
  final Map<DurableId, ReceiptProductLink?> _selections;
  final DurableId mutationId;
  ReceiptSnapshot get _snapshot => _withLinks(_base.snapshot, _selections);

  ProductLinkConfirmation confirm({
    required BigInt reviewedAtMs,
    required String appVersion,
  }) => ProductLinkConfirmation._(
    this,
    checkedInt64(reviewedAtMs, 'reviewedAtMs', nonnegative: true),
    _text(appVersion, 'appVersion'),
  );

  ReceiptDocument _document(BigInt at, String app) => ReceiptDocument._(
    _snapshot,
    ProductLinkReviewRecord._(
      at,
      app,
      [_head],
      _changedRows(_base.snapshot, _snapshot),
      _base.review.source,
      _base.sha256Hex,
      originalReceiptRowIds(_base),
    ),
  );
}

final class ProductLinkConfirmation {
  const ProductLinkConfirmation._(
    this._checks,
    this.reviewedAtMs,
    this.appVersion,
  );
  final ProductLinkReviewChecks _checks;
  final BigInt reviewedAtMs;
  final String appVersion;
}

/// Only the listed product links were reviewed. Original approval stays in history.
final class ProductLinkReviewRecord extends ReceiptReviewRecord {
  ProductLinkReviewRecord._(
    super.at,
    super.app,
    super.heads,
    super.rows,
    this.source,
    this.baseDocumentSha256,
    Iterable<DurableId> originalRows,
  ) : originalRowIds = List.unmodifiable(originalRows),
      super._();
  @override
  final String source;
  @override
  int get policyVersion => 4;
  final String baseDocumentSha256;
  final List<DurableId> originalRowIds;
}

/// Original OCR evidence identities, including removed source rows.
List<DurableId> originalReceiptRowIds(ReceiptDocument document) =>
    switch (document.review) {
      OcrReviewRecord r => r.originalRowIds,
      ProductLinkReviewRecord r => r.originalRowIds,
      _ => const [],
    };

/// Used both at transaction time and during full event/backup replay.
void validateProductLinkRevision(
  ReceiptDocument current,
  ReceiptDocument? base,
) {
  final review = current.review;
  if (review is! ProductLinkReviewRecord) return;
  _require(
    base != null && base.sha256Hex == review.baseDocumentSha256,
    'productLinks',
    'baseMismatch',
  );
  _require(base!.review.source == review.source, 'productLinks', 'provenance');
  final selections = {
    for (final r in current.snapshot.items)
      if (r.kind == LineKind.product) r.id: r.product,
  };
  _require(
    ReceiptSnapshotCodec.encode(_withLinks(base.snapshot, selections)) ==
        ReceiptSnapshotCodec.encode(current.snapshot),
    'productLinks',
    'changedReceipt',
  );
  final changed = _changedRows(base.snapshot, current.snapshot);
  _require(
    changed.isNotEmpty && _sameIds(changed, review.reviewedRowIds),
    'productLinks',
    'unreviewedRows',
  );
  _require(
    _sameIds(originalReceiptRowIds(base), review.originalRowIds),
    'productLinks',
    'changedEvidence',
  );
}

bool _sameIds(List<DurableId> a, List<DurableId> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

List<DurableId> _changedRows(ReceiptSnapshot before, ReceiptSnapshot after) => [
  for (var i = 0; i < before.items.length; i++)
    if (jsonEncode(_itemObject(before.items[i], i)['product']) !=
        jsonEncode(_itemObject(after.items[i], i)['product']))
      before.items[i].id,
];

ReceiptSnapshot _withLinks(
  ReceiptSnapshot base,
  Map<DurableId, ReceiptProductLink?> selections,
) => ReceiptSnapshot(
  id: base.id,
  branch: base.branch,
  date: base.date,
  totalCents: base.totalCents,
  items: [
    for (final row in base.items)
      ReceiptItemSnapshot(
        id: row.id,
        name: row.name,
        rawName: row.rawName,
        kind: row.kind,
        cents: row.cents,
        quantityValue: row.quantityValue,
        quantityScale: row.quantityScale,
        quantityUnit: row.quantityUnit,
        rateMicros: row.rateMicros,
        parentItemId: row.parentItemId,
        discountScope: row.discountScope,
        adjustmentReason: row.adjustmentReason,
        product: selections.containsKey(row.id)
            ? selections[row.id]
            : row.product,
      ),
  ],
);

Map<String, Object?> _productLinkReviewObject(ProductLinkReviewRecord r) => {
  'policy_version': '4',
  'source': r.source,
  'app_version': r.appVersion,
  'timezone_rules_version': receiptTimezoneRulesVersion,
  'reviewed_at_ms': r.reviewedAtMs.toString(),
  'expected_heads': r.expectedHeads.map(_revisionObject).toList(),
  'base_document_sha256': r.baseDocumentSha256,
  'reviewed_product_row_ids': r.reviewedRowIds.map((id) => id.value).toList(),
  'original_row_ids': r.originalRowIds.map((id) => id.value).toList(),
};

ProductLinkReviewRecord _readProductLinkReview(
  Object? value,
  ReceiptSnapshot snapshot,
) {
  final r = _object(value, [
    'policy_version',
    'source',
    'app_version',
    'timezone_rules_version',
    'reviewed_at_ms',
    'expected_heads',
    'base_document_sha256',
    'reviewed_product_row_ids',
    'original_row_ids',
  ]);
  _require(
    r['policy_version'] == '4' &&
        ['manual', 'ocr'].contains(r['source']) &&
        r['timezone_rules_version'] == receiptTimezoneRulesVersion,
    'productLinks',
    'unsupported',
  );
  final heads = _list(r['expected_heads']).map(_readRevision).toList();
  final rows = _list(r['reviewed_product_row_ids']).map(_id).toList();
  final original = _list(r['original_row_ids']).map(_id).toList();
  final digest = _string(r['base_document_sha256']);
  _require(
    heads.length == 1 &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) &&
        rows.isNotEmpty &&
        rows.toSet().length == rows.length &&
        rows.every(
          (id) => snapshot.items.any(
            (row) => row.id == id && row.kind == LineKind.product,
          ),
        ) &&
        original.toSet().length == original.length &&
        (r['source'] == 'ocr' || original.isEmpty),
    'productLinks',
    'invalidReview',
  );
  return ProductLinkReviewRecord._(
    checkedInt64(
      _integer(r['reviewed_at_ms']),
      'reviewedAtMs',
      nonnegative: true,
    ),
    _text(_string(r['app_version']), 'appVersion'),
    heads,
    rows,
    _string(r['source']),
    digest,
    original,
  );
}
