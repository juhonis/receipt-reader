part of '../receipt_domain.dart';

/// V1 canonical JSON: fixed field order, UTF-8, explicit nulls, decimal strings
/// for integers, and receipt order for rows. No image, OCR, or review-note fields.
final class ReceiptSnapshotCodec {
  static String encode(ReceiptSnapshot snapshot) =>
      _encode(_snapshotObject(snapshot));
  static ReceiptSnapshot decode(String json) =>
      _canonicalDecode(json, _readSnapshot, encode);
}

final class ReceiptDocumentCodec {
  static String encode(ReceiptDocument document) => _encode({
    'payload_version': '1',
    'receipt': _snapshotObject(document.snapshot),
    'review': {
      'policy_version': '1',
      'source': 'manual',
      'app_version': document.review.appVersion,
      'timezone_rules_version': receiptTimezoneRulesVersion,
      'reviewed_at_ms': document.review.reviewedAtMs.toString(),
      'expected_heads': document.review.expectedHeads
          .map(_revisionObject)
          .toList(),
      'branch_reviewed': true,
      'date_reviewed': true,
      'total_reviewed': true,
      'reconciled': true,
      'reviewed_row_ids': document.review.reviewedRowIds
          .map((id) => id.value)
          .toList(),
    },
  });

  static ReceiptDocument decode(String json) => _canonicalDecode(json, (value) {
    final root = _object(value, ['payload_version', 'receipt', 'review']);
    _require(root['payload_version'] == '1', 'payloadVersion', 'unsupported');
    final snapshot = _readSnapshot(root['receipt']);
    final review = _object(root['review'], [
      'policy_version',
      'source',
      'app_version',
      'timezone_rules_version',
      'reviewed_at_ms',
      'expected_heads',
      'branch_reviewed',
      'date_reviewed',
      'total_reviewed',
      'reconciled',
      'reviewed_row_ids',
    ]);
    _require(
      review['policy_version'] == '1' &&
          review['source'] == 'manual' &&
          review['timezone_rules_version'] == receiptTimezoneRulesVersion,
      'review',
      'unsupported',
    );
    _require(
      review['branch_reviewed'] == true &&
          review['date_reviewed'] == true &&
          review['total_reviewed'] == true &&
          review['reconciled'] == true,
      'review',
      'incomplete',
    );
    final at = checkedInt64(
      _integer(review['reviewed_at_ms']),
      'reviewedAtMs',
      nonnegative: true,
    );
    final app = _text(_string(review['app_version']), 'appVersion');
    final heads = _list(review['expected_heads']).map(_readRevision).toList();
    final rows = _list(review['reviewed_row_ids']).map(_id).toList();
    _require(
      rows.length == snapshot.items.length &&
          Iterable<int>.generate(rows.length)
              .every((i) => rows[i] == snapshot.items[i].id),
      'review.rows',
      'uncheckedOrForeignRows',
    );
    return ReceiptDocument._(
      snapshot,
      ManualReviewRecord._(at, app, heads, rows),
    );
  }, encode);
}

const _maxDocumentBytes = 2 * 1024 * 1024;

String _encode(Object value) {
  final result = jsonEncode(value);
  _checkSize(result);
  return result;
}

void _checkSize(String text) {
  _require(
    text.length <= _maxDocumentBytes &&
        utf8.encode(text).length <= _maxDocumentBytes,
    'json',
    'sizeLimit',
  );
}

T _canonicalDecode<T>(
  String json,
  T Function(Object?) read,
  String Function(T) encode,
) {
  _checkSize(json);
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw const ReceiptDataException('json', 'invalid');
  }
  final result = read(decoded);
  _require(encode(result) == json, 'json', 'nonCanonical');
  return result;
}

Map<String, Object?> _revisionObject(RevisionId revision) => {
  'origin': revision.origin.value,
  'sequence': revision.sequence.toString(),
};

Map<String, Object?> _snapshotObject(ReceiptSnapshot snapshot) => {
  'id': snapshot.id.value,
  'branch': {
    'id': snapshot.branch.id.value,
    'name': snapshot.branch.name,
    'revision': snapshot.branch.revision == null
        ? null
        : _revisionObject(snapshot.branch.revision!),
    'chain': snapshot.branch.chain,
    'address': snapshot.branch.address,
    'printed_identifier': snapshot.branch.printedIdentifier,
  },
  'date': {
    'year': snapshot.date.year.toString(),
    'month': snapshot.date.month.toString(),
    'day': snapshot.date.day.toString(),
    'hour': snapshot.date.hour?.toString(),
    'minute': snapshot.date.minute?.toString(),
    'second': snapshot.date.second?.toString(),
    'precision': switch (snapshot.date.precision) {
      DatePrecision.day => 'day',
      DatePrecision.minute => 'minute',
      DatePrecision.second => 'second',
    },
    'timezone': snapshot.date.timezone,
    'utc_instant_ms': snapshot.date.utcInstantMs?.toString(),
  },
  'currency': snapshot.currency,
  'total_cents': snapshot.totalCents.toString(),
  'items': [
    for (var i = 0; i < snapshot.items.length; i++)
      _itemObject(snapshot.items[i], i),
  ],
};

Map<String, Object?> _itemObject(ReceiptItemSnapshot row, int position) => {
  'id': row.id.value,
  'position': position.toString(),
  'kind': switch (row.kind) {
    LineKind.product => 'product',
    LineKind.discount => 'discount',
    LineKind.deposit => 'deposit',
    LineKind.adjustment => 'adjustment',
  },
  'raw_name': row.rawName,
  'name': row.name,
  'normalized_name': row.normalizedName,
  'normalizer_version': '1',
  'quantity': row.quantityValue == null
      ? null
      : {
          'value': row.quantityValue.toString(),
          'scale': row.quantityScale.toString(),
          'unit': switch (row.quantityUnit!) {
            QuantityUnit.piece => 'piece',
            QuantityUnit.kg => 'kg',
            QuantityUnit.litre => 'litre',
            QuantityUnit.unknown => throw const ReceiptDataException(
              'row.quantity',
              'unknownUnit',
            ),
          },
        },
  'rate_micros': row.rateMicros?.toString(),
  'cents': row.cents.toString(),
  'parent_item_id': row.parentItemId?.value,
  'discount_scope': switch (row.discountScope) {
    null => null,
    DiscountScope.item => 'item',
    DiscountScope.receipt => 'receipt',
  },
  'product': row.product == null
      ? null
      : {
          'id': row.product!.id.value,
          'store_id': row.product!.storeId.value,
          'revision': _revisionObject(row.product!.revision),
        },
  'adjustment_reason': row.adjustmentReason,
};

Map<String, Object?> _object(Object? value, List<String> fields) {
  _require(value is Map<String, Object?>, 'json.object', 'type');
  final object = value as Map<String, Object?>;
  _require(
    object.length == fields.length && fields.every(object.containsKey),
    'json.object',
    'fields',
  );
  return object;
}

List<Object?> _list(Object? value) {
  _require(value is List<Object?>, 'json.list', 'type');
  return value as List<Object?>;
}

String _string(Object? value) {
  _require(value is String, 'json.string', 'type');
  return value as String;
}

BigInt _integer(Object? value) {
  final text = _string(value);
  // A signed SQLite integer needs at most 20 characters. Bound work before
  // parsing a potentially very large decimal from a corrupt/imported payload.
  _require(text.length <= 20, 'json.integer', 'integerRange');
  _require(
    RegExp(r'^(?:0|-?[1-9][0-9]*)$').hasMatch(text),
    'json.integer',
    'decimalString',
  );
  return checkedInt64(BigInt.parse(text), 'json.integer');
}

int _smallInteger(Object? value) => _integer(value).toInt();
DurableId _id(Object? value) => DurableId.parse(_string(value));
RevisionId _readRevision(Object? value) {
  final object = _object(value, ['origin', 'sequence']);
  return RevisionId(_id(object['origin']), _integer(object['sequence']));
}

ReceiptSnapshot _readSnapshot(Object? value) {
  final object = _object(value, [
    'id',
    'branch',
    'date',
    'currency',
    'total_cents',
    'items',
  ]);
  _require(object['currency'] == 'EUR', 'currency', 'unsupported');
  final branch = _object(object['branch'], [
    'id',
    'name',
    'revision',
    'chain',
    'address',
    'printed_identifier',
  ]);
  final items = _list(object['items']);
  return ReceiptSnapshot(
    id: _id(object['id']),
    branch: ReceiptBranch(
      id: _id(branch['id']),
      name: _string(branch['name']),
      revision: branch['revision'] == null
          ? null
          : _readRevision(branch['revision']),
      chain: branch['chain'] == null ? null : _string(branch['chain']),
      address: branch['address'] == null ? null : _string(branch['address']),
      printedIdentifier: branch['printed_identifier'] == null
          ? null
          : _string(branch['printed_identifier']),
    ),
    date: _readDate(object['date']),
    totalCents: _integer(object['total_cents']),
    items: [for (var i = 0; i < items.length; i++) _readItem(items[i], i)],
  );
}

StoredReceiptDate _readDate(Object? value) {
  final object = _object(value, [
    'year',
    'month',
    'day',
    'hour',
    'minute',
    'second',
    'precision',
    'timezone',
    'utc_instant_ms',
  ]);
  _require(
    object['timezone'] == 'Europe/Helsinki',
    'date.timezone',
    'unsupported',
  );
  final precision = object['precision'];
  _require(
    precision == 'day' || precision == 'minute' || precision == 'second',
    'date.precision',
    'unsupported',
  );
  _require(
    precision == 'day'
        ? object['hour'] == null &&
              object['minute'] == null &&
              object['second'] == null
        : object['hour'] != null &&
              object['minute'] != null &&
              (precision == 'minute'
                  ? object['second'] == null
                  : object['second'] != null),
    'date',
    'precisionFields',
  );
  final dateText =
      '${_integer(object['day'])}.${_integer(object['month'])}.${_integer(object['year'])}'
      '${precision == 'day' ? '' : ' ${_integer(object['hour'])}:${_string(object['minute']).padLeft(2, '0')}'}'
      '${precision == 'second' ? ':${_string(object['second']).padLeft(2, '0')}' : ''}';
  final date = StoredReceiptDate.parse(dateText);
  final utc = object['utc_instant_ms'] == null
      ? null
      : _integer(object['utc_instant_ms']);
  _require(date.utcInstantMs == utc, 'date.utcInstantMs', 'notDerived');
  return date;
}

ReceiptItemSnapshot _readItem(Object? value, int position) {
  final object = _object(value, [
    'id',
    'position',
    'kind',
    'raw_name',
    'name',
    'normalized_name',
    'normalizer_version',
    'quantity',
    'rate_micros',
    'cents',
    'parent_item_id',
    'discount_scope',
    'product',
    'adjustment_reason',
  ]);
  _require(
    _integer(object['position']) == BigInt.from(position),
    'row.position',
    'notDense',
  );
  _require(
    object['normalizer_version'] == '1',
    'row.normalizerVersion',
    'unsupported',
  );
  final kind = switch (object['kind']) {
    'product' => LineKind.product,
    'discount' => LineKind.discount,
    'deposit' => LineKind.deposit,
    'adjustment' => LineKind.adjustment,
    _ => throw const ReceiptDataException('row.kind', 'unsupported'),
  };
  final quantity = object['quantity'] == null
      ? null
      : _object(object['quantity'], ['value', 'scale', 'unit']);
  final unit = quantity == null
      ? null
      : switch (quantity['unit']) {
          'piece' => QuantityUnit.piece,
          'kg' => QuantityUnit.kg,
          'litre' => QuantityUnit.litre,
          _ => throw const ReceiptDataException(
            'row.quantity.unit',
            'unsupported',
          ),
        };
  final scope = switch (object['discount_scope']) {
    null => null,
    'item' => DiscountScope.item,
    'receipt' => DiscountScope.receipt,
    _ => throw const ReceiptDataException('row.discountScope', 'unsupported'),
  };
  final product = object['product'] == null
      ? null
      : _object(object['product'], ['id', 'store_id', 'revision']);
  final row = ReceiptItemSnapshot(
    id: _id(object['id']),
    name: _string(object['name']),
    kind: kind,
    cents: _integer(object['cents']),
    rawName: object['raw_name'] == null ? null : _string(object['raw_name']),
    quantityValue: quantity == null ? null : _integer(quantity['value']),
    quantityScale: quantity == null ? null : _smallInteger(quantity['scale']),
    quantityUnit: unit,
    rateMicros: object['rate_micros'] == null
        ? null
        : _integer(object['rate_micros']),
    parentItemId: object['parent_item_id'] == null
        ? null
        : _id(object['parent_item_id']),
    discountScope: scope,
    product: product == null
        ? null
        : ReceiptProductLink(
            id: _id(product['id']),
            storeId: _id(product['store_id']),
            revision: _readRevision(product['revision']),
          ),
    adjustmentReason: object['adjustment_reason'] == null
        ? null
        : _string(object['adjustment_reason']),
  );
  _require(
    row.normalizedName == object['normalized_name'],
    'row.normalizedName',
    'notDerived',
  );
  return row;
}
