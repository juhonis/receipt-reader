part of '../receipt_domain.dart';

/// A branch-owned identity. Equal names do not imply equal products.
final class ProductSnapshot {
  ProductSnapshot({
    required this.id,
    required this.storeId,
    required String canonicalName,
    this.packageValue,
    this.packageScale,
    this.packageUnit,
    String? category,
  }) : canonicalName = _text(canonicalName, 'product.name'),
       category = category == null ? null : _categoryLabel(category) {
    final absent =
        packageValue == null && packageScale == null && packageUnit == null;
    _require(
      absent ||
          (packageValue != null &&
              packageScale != null &&
              packageUnit != null &&
              packageUnit != QuantityUnit.unknown),
      'product.package',
      'incomplete',
    );
    if (!absent) {
      checkedInt64(packageValue!, 'product.package');
      _require(
        packageValue! > BigInt.zero && packageScale! >= 0 && packageScale! <= 6,
        'product.package',
        'range',
      );
    }
  }
  final DurableId id, storeId;
  final String canonicalName;

  /// Current reviewed classification; historical receipts retain their bytes.
  final String? category;
  final BigInt? packageValue;
  final int? packageScale;
  final QuantityUnit? packageUnit;
}

String normalizeProductCategory(String value) =>
    _categoryLabel(value.trim().replaceAll(RegExp(r'\s+', unicode: true), ' '));
String _categoryLabel(String value) {
  _text(value, 'product.category');
  _require(
    value.runes.length <= 80 &&
        !RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value) &&
        value == value.replaceAll(RegExp(r'\s+', unicode: true), ' '),
    'product.category',
    'invalidLabel',
  );
  return value;
}

/// Reviewed catalog snapshot, including the exact branch revision it used.
final class ProductDocument {
  ProductDocument({
    required this.product,
    required this.storeRevision,
    required this.expectedHead,
    required BigInt reviewedAtMs,
    required String appVersion,
  }) : reviewedAtMs = checkedInt64(
         reviewedAtMs,
         'reviewedAtMs',
         nonnegative: true,
       ),
       appVersion = _text(appVersion, 'appVersion');
  final ProductSnapshot product;
  final RevisionId storeRevision;
  final RevisionId? expectedHead;
  final BigInt reviewedAtMs;
  final String appVersion;
  String get sha256Hex =>
      sha256.convert(utf8.encode(ProductDocumentCodec.encode(this))).toString();
}

/// An exact normalized receipt-name key. Deactivation retains identity/history.
final class ProductAliasSnapshot {
  ProductAliasSnapshot({
    required this.id,
    required this.storeId,
    required String normalizedName,
    required this.productId,
    required this.isActive,
  }) : normalizedName = _text(normalizedName, 'alias.name') {
    _require(
      normalizeReceiptNameV1(normalizedName) == normalizedName,
      'alias.name',
      'notNormalized',
    );
  }
  final DurableId id, storeId, productId;
  final String normalizedName;
  final bool isActive;
  int get normalizerVersion => 1;
}

final class ProductAliasDocument {
  ProductAliasDocument({
    required this.alias,
    required this.storeRevision,
    required this.productRevision,
    required this.expectedHead,
    required BigInt reviewedAtMs,
    required String appVersion,
  }) : reviewedAtMs = checkedInt64(
         reviewedAtMs,
         'reviewedAtMs',
         nonnegative: true,
       ),
       appVersion = _text(appVersion, 'appVersion');
  final ProductAliasSnapshot alias;
  final RevisionId storeRevision, productRevision;
  final RevisionId? expectedHead;
  final BigInt reviewedAtMs;
  final String appVersion;
  String get sha256Hex => sha256
      .convert(utf8.encode(ProductAliasDocumentCodec.encode(this)))
      .toString();
}

Map<String, Object?> _catalogReview(
  RevisionId store,
  RevisionId? head,
  BigInt at,
  String app,
) => {
  'store_revision': _revisionObject(store),
  'expected_head': head == null ? null : _revisionObject(head),
  'reviewed_at_ms': at.toString(),
  'app_version': app,
};

Map<String, Object?> _readCatalogReview(Object? value) => _object(value, [
  'store_revision',
  'expected_head',
  'reviewed_at_ms',
  'app_version',
]);

final class ProductDocumentCodec {
  static String encode(ProductDocument document) => _encode({
    'payload_version': document.product.category == null ? '1' : '2',
    'product': {
      'id': document.product.id.value,
      'store_id': document.product.storeId.value,
      'canonical_name': document.product.canonicalName,
      'package': document.product.packageValue == null
          ? null
          : {
              'value': document.product.packageValue.toString(),
              'scale': document.product.packageScale.toString(),
              'unit': document.product.packageUnit!.name,
            },
      if (document.product.category != null)
        'category': document.product.category,
    },
    'review': _catalogReview(
      document.storeRevision,
      document.expectedHead,
      document.reviewedAtMs,
      document.appVersion,
    ),
  });
  static ProductDocument decode(String json) => _canonicalDecode(json, (value) {
    final root = _object(value, ['payload_version', 'product', 'review']);
    final version = root['payload_version'];
    _require(version == '1' || version == '2', 'payloadVersion', 'unsupported');
    final p = _object(root['product'], [
      'id',
      'store_id',
      'canonical_name',
      'package',
      if (version == '2') 'category',
    ]);
    final q = p['package'] == null
        ? null
        : _object(p['package'], ['value', 'scale', 'unit']);
    final r = _readCatalogReview(root['review']);
    return ProductDocument(
      product: ProductSnapshot(
        id: _id(p['id']),
        storeId: _id(p['store_id']),
        canonicalName: _string(p['canonical_name']),
        category: version == '2' ? _string(p['category']) : null,
        packageValue: q == null ? null : _integer(q['value']),
        packageScale: q == null ? null : _smallInteger(q['scale']),
        packageUnit: q == null
            ? null
            : switch (q['unit']) {
                'piece' => QuantityUnit.piece,
                'kg' => QuantityUnit.kg,
                'litre' => QuantityUnit.litre,
                _ => throw const ReceiptDataException(
                  'product.package',
                  'unknownUnit',
                ),
              },
      ),
      storeRevision: _readRevision(r['store_revision']),
      expectedHead: r['expected_head'] == null
          ? null
          : _readRevision(r['expected_head']),
      reviewedAtMs: _integer(r['reviewed_at_ms']),
      appVersion: _string(r['app_version']),
    );
  }, encode);
}

final class ProductAliasDocumentCodec {
  static String encode(ProductAliasDocument document) => _encode({
    'payload_version': '1',
    'alias': {
      'id': document.alias.id.value,
      'store_id': document.alias.storeId.value,
      'normalized_name': document.alias.normalizedName,
      'normalizer_version': '1',
      'product_id': document.alias.productId.value,
      'is_active': document.alias.isActive,
    },
    'product_revision': _revisionObject(document.productRevision),
    'review': _catalogReview(
      document.storeRevision,
      document.expectedHead,
      document.reviewedAtMs,
      document.appVersion,
    ),
  });
  static ProductAliasDocument decode(String json) => _canonicalDecode(json, (
    value,
  ) {
    final root = _object(value, [
      'payload_version',
      'alias',
      'product_revision',
      'review',
    ]);
    _require(root['payload_version'] == '1', 'payloadVersion', 'unsupported');
    final a = _object(root['alias'], [
      'id',
      'store_id',
      'normalized_name',
      'normalizer_version',
      'product_id',
      'is_active',
    ]);
    _require(
      a['normalizer_version'] == '1' && a['is_active'] is bool,
      'alias',
      'unsupported',
    );
    final r = _readCatalogReview(root['review']);
    return ProductAliasDocument(
      alias: ProductAliasSnapshot(
        id: _id(a['id']),
        storeId: _id(a['store_id']),
        normalizedName: _string(a['normalized_name']),
        productId: _id(a['product_id']),
        isActive: a['is_active']! as bool,
      ),
      productRevision: _readRevision(root['product_revision']),
      storeRevision: _readRevision(r['store_revision']),
      expectedHead: r['expected_head'] == null
          ? null
          : _readRevision(r['expected_head']),
      reviewedAtMs: _integer(r['reviewed_at_ms']),
      appVersion: _string(r['app_version']),
    );
  }, encode);
}
