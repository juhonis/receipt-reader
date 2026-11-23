import 'dart:convert';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'catalog_test.dart' show product;

void main() {
  final link = ReceiptProductLink(
    id: id(10),
    storeId: id(2),
    revision: RevisionId(id(9), BigInt.one),
  );
  test('uncategorized products retain canonical v1; categorized products round-trip v2', () {
    final old = ProductDocumentCodec.encode(product());
    expect(jsonDecode(old)['payload_version'], '1');
    expect(ProductDocumentCodec.decode(old).product.category, isNull);
    expect(ProductDocumentCodec.encode(ProductDocumentCodec.decode(old)), old);
    final doc = product(
      snapshot: ProductSnapshot(
        id: id(1),
        storeId: id(2),
        canonicalName: 'TEST',
        category: 'Ruoka ja juoma',
      ),
    );
    final encoded = ProductDocumentCodec.encode(doc);
    expect(jsonDecode(encoded)['payload_version'], '2');
    expect(
      ProductDocumentCodec.decode(encoded).product.category,
      'Ruoka ja juoma',
    );
    expect(ProductDocumentCodec.decode(encoded).sha256Hex, doc.sha256Hex);
    for (final invalid in [
      encoded.replaceFirst('"category":"Ruoka ja juoma"', '"category":null'),
      encoded.replaceFirst('"payload_version":"2"', '"payload_version":"1"'),
      encoded.replaceFirst('"payload_version":"2"', '"payload_version":"3"'),
    ]) {
      expect(
        () => ProductDocumentCodec.decode(invalid),
        throwsA(isA<ReceiptDataException>()),
      );
    }
  });
  test('category labels are bounded, strict Unicode and editable text rather than enum guesses', () {
    expect(normalizeProductCategory('  Oma\t luokka  '), 'Oma luokka');
    for (final label in ['', ' ', ' x', 'x  y', 'x\ny', '\ud800', 'x' * 81]) {
      expect(
        () => ProductSnapshot(
          id: id(1),
          storeId: id(2),
          canonicalName: 'T',
          category: label,
        ),
        throwsA(isA<ReceiptDataException>()),
      );
    }
  });
  test('categories reconcile all signed rows with item discounts and unallocated groups', () {
    final snapshot = receipt(
      total: BigInt.from(1025),
      items: [
        row(number: 20, cents: BigInt.from(1000), product: link),
        row(
          number: 21,
          cents: BigInt.from(-100),
          kind: LineKind.discount,
          scope: DiscountScope.item,
          parent: id(20),
        ),
        row(number: 22, cents: BigInt.from(300)),
        row(number: 23, cents: BigInt.from(-200), product: link),
        row(
          number: 24,
          cents: BigInt.from(50),
          kind: LineKind.deposit,
          parent: id(20),
        ),
        row(
          number: 25,
          cents: BigInt.from(-20),
          kind: LineKind.discount,
          scope: DiscountScope.receipt,
        ),
        row(
          number: 26,
          cents: BigInt.from(-5),
          kind: LineKind.adjustment,
          reason: 'TEST',
        ),
      ],
    );
    final b = CategorySpendingBuilder()
      ..add(snapshot, {link.id: 'Ruoka ja juoma'});
    final summary = b.build();
    expect(summary.totalCents, snapshot.totalCents);
    expect(summary.productRows, 3);
    expect(summary.categorizedProductRows, 2);
    expect(summary.uncategorizedProductRows, 1);
    final food = summary.groups.singleWhere(
      (g) => g.category == ReceiptCategory.product('Ruoka ja juoma'),
    );
    expect(
      (food.totalCents, food.rowCount, food.receiptCount),
      (BigInt.from(700), 3, 1),
    );
    expect(
      summary.groups
          .singleWhere(
            (g) => g.category.kind == CategorySpendingKind.uncategorized,
          )
          .totalCents,
      BigInt.from(300),
    );
    expect(
      summary.groups
          .singleWhere((g) => g.category.kind == CategorySpendingKind.deposit)
          .totalCents,
      BigInt.from(50),
    );
    expect(() => summary.groups.clear(), throwsUnsupportedError);
  });
  test('latest labels regroup earlier linked purchases without changing their bytes', () {
    final snapshot = receipt(items: [row(product: link)]);
    final bytes = ReceiptSnapshotCodec.encode(snapshot);
    final before =
        (CategorySpendingBuilder()..add(snapshot, {link.id: 'Ruoka ja juoma'}))
            .build();
    final after =
        (CategorySpendingBuilder()..add(snapshot, {link.id: 'Oma luokka'}))
            .build();
    expect(before.groups.single.category.name, 'Ruoka ja juoma');
    expect(after.groups.single.category.name, 'Oma luokka');
    expect(after.totalCents, before.totalCents);
    expect(ReceiptSnapshotCodec.encode(snapshot), bytes);
    final cleared = (CategorySpendingBuilder()..add(snapshot, {link.id: null}))
        .build();
    expect(
      cleared.groups.single.category,
      const ReceiptCategory.uncategorized(),
    );
  });
  test('typed special buckets cannot collide with a custom label', () {
    final snapshot = receipt(
      total: BigInt.from(400),
      items: [
        row(number: 3, product: link),
        row(number: 4),
      ],
    );
    final result =
        (CategorySpendingBuilder()..add(snapshot, {link.id: 'Luokittelematon'}))
            .build();
    expect(result.groups, hasLength(2));
    expect(result.totalCents, BigInt.from(400));
  });
  test('more than 64 groups fails and huge signed sums remain exact', () {
    final b = CategorySpendingBuilder();
    for (var i = 0; i < 64; i++) {
      b.add(receipt(items: [row(product: link)]), {link.id: 'GROUP $i'});
    }
    expect(
      () => b.add(receipt(items: [row(product: link)]), {link.id: 'GROUP 64'}),
      throwsA(isA<ReceiptDataException>()),
    );
    final huge = receipt(
      total: BigInt.parse('18014398509481986'),
      items: [
        row(number: 3, cents: BigInt.parse('9007199254740993'), product: link),
        row(number: 4, cents: BigInt.parse('9007199254740993'), product: link),
      ],
    );
    expect(
      (CategorySpendingBuilder()..add(huge, {link.id: 'TEST'}))
          .build()
          .totalCents,
      huge.totalCents,
    );
  });
}
