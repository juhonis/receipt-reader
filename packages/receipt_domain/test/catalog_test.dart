import 'dart:convert';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

ProductDocument product({ProductSnapshot? snapshot}) => ProductDocument(
  product:
      snapshot ??
      ProductSnapshot(id: id(1), storeId: id(2), canonicalName: 'Ääkköset 1 l'),
  storeRevision: RevisionId(id(3), BigInt.one),
  expectedHead: null,
  reviewedAtMs: BigInt.from(123),
  appVersion: 'catalog-test',
);

ProductAliasDocument alias() => ProductAliasDocument(
  alias: ProductAliasSnapshot(
    id: id(4),
    storeId: id(2),
    normalizedName: 'ääkköset 1 l',
    productId: id(1),
    isActive: true,
  ),
  storeRevision: RevisionId(id(3), BigInt.one),
  productRevision: RevisionId(id(3), BigInt.two),
  expectedHead: null,
  reviewedAtMs: BigInt.from(124),
  appVersion: 'catalog-test',
);

void main() {
  test('catalog canonical documents preserve Unicode, decimal quantities and reviewed dependencies', () {
    final doc = product(
      snapshot: ProductSnapshot(
        id: id(1),
        storeId: id(2),
        canonicalName: 'Ääkköset 1 l',
        packageValue: BigInt.from(1500),
        packageScale: 3,
        packageUnit: QuantityUnit.litre,
      ),
    );
    final encoded = ProductDocumentCodec.encode(doc);
    final decoded = ProductDocumentCodec.decode(encoded);
    expect(decoded.product.packageValue, BigInt.from(1500));
    expect(decoded.product.packageScale, 3);
    expect(decoded.product.packageUnit, QuantityUnit.litre);
    expect(decoded.product.canonicalName, 'Ääkköset 1 l');
    expect(decoded.storeRevision, doc.storeRevision);
    expect(decoded.sha256Hex, doc.sha256Hex);
    expect(ProductDocumentCodec.encode(decoded), encoded);
    final a = alias(), text = ProductAliasDocumentCodec.encode(a);
    expect(ProductAliasDocumentCodec.decode(text).sha256Hex, a.sha256Hex);
    expect(
      ProductAliasDocumentCodec.decode(text).productRevision,
      a.productRevision,
    );
    expect(ProductAliasDocumentCodec.decode(text).alias.normalizerVersion, 1);
  });

  for (final (index, build) in <ProductSnapshot Function()>[
    () => ProductSnapshot(id: id(1), storeId: id(2), canonicalName: ' '),
    () => ProductSnapshot(id: id(1), storeId: id(2), canonicalName: ' bad'),
    () => ProductSnapshot(id: id(1), storeId: id(2), canonicalName: '\ud800'),
    () => ProductSnapshot(
      id: id(1),
      storeId: id(2),
      canonicalName: 'test',
      packageValue: BigInt.one,
    ),
    () => ProductSnapshot(
      id: id(1),
      storeId: id(2),
      canonicalName: 'test',
      packageScale: 0,
    ),
    () => ProductSnapshot(
      id: id(1),
      storeId: id(2),
      canonicalName: 'test',
      packageUnit: QuantityUnit.kg,
    ),
    for (final value in [BigInt.zero, -BigInt.one, sqliteInt64Max + BigInt.one])
      () => ProductSnapshot(
        id: id(1),
        storeId: id(2),
        canonicalName: 'test',
        packageValue: value,
        packageScale: 0,
        packageUnit: QuantityUnit.kg,
      ),
    for (final scale in [-1, 7])
      () => ProductSnapshot(
        id: id(1),
        storeId: id(2),
        canonicalName: 'test',
        packageValue: BigInt.one,
        packageScale: scale,
        packageUnit: QuantityUnit.kg,
      ),
    () => ProductSnapshot(
      id: id(1),
      storeId: id(2),
      canonicalName: 'test',
      packageValue: BigInt.one,
      packageScale: 0,
      packageUnit: QuantityUnit.unknown,
    ),
  ].indexed) {
    test('invalid product values are rejected (case $index)', () {
      expect(build, throwsA(isA<ReceiptDataException>()));
    });
  }

  test('aliases use the existing conservative v1 normalizer, without fuzzy folding', () {
    final key = normalizeReceiptNameV1('  ÄÄKKÖSET\t1 L  ');
    expect(key, 'ääkköset 1 l');
    expect(normalizeReceiptNameV1('AAKKOSET 1 L'), isNot(key));
    for (final name in ['UPPER', 'two  spaces', ' edge ', '', '\ud800']) {
      expect(
        () => ProductAliasSnapshot(
          id: id(4),
          storeId: id(2),
          normalizedName: name,
          productId: id(1),
          isActive: true,
        ),
        throwsA(isA<ReceiptDataException>()),
      );
    }
  });

  test('catalog decoders reject unsupported versions, extra fields and noncanonical JSON', () {
    final p = ProductDocumentCodec.encode(product()),
        a = ProductAliasDocumentCodec.encode(alias());
    for (final pair in [
      (p, ProductDocumentCodec.decode),
      (a, ProductAliasDocumentCodec.decode),
    ]) {
      for (final invalid in [
        pair.$1 + '\n',
        pair.$1.replaceFirst('"payload_version":"1"', '"payload_version":"2"'),
        jsonEncode({
          ...jsonDecode(pair.$1) as Map<String, dynamic>,
          'extra': true,
        }),
      ]) {
        expect(() => pair.$2(invalid), throwsA(isA<ReceiptDataException>()));
      }
    }
    final map = jsonDecode(a) as Map<String, dynamic>;
    map['alias']['normalizer_version'] = '2';
    expect(
      () => ProductAliasDocumentCodec.decode(jsonEncode(map)),
      throwsA(isA<ReceiptDataException>()),
    );
    map['alias']['normalizer_version'] = '1';
    map['alias']['is_active'] = 1;
    expect(
      () => ProductAliasDocumentCodec.decode(jsonEncode(map)),
      throwsA(isA<ReceiptDataException>()),
    );
  });
}
