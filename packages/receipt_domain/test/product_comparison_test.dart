import 'dart:convert';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'catalog_test.dart' show product;

ProductSnapshot saved({
  int branch = 2,
  int size = 500,
  int scale = 3,
  QuantityUnit unit = QuantityUnit.kg,
  bool package = true,
}) => ProductSnapshot(
  id: id(10),
  storeId: id(branch),
  canonicalName: 'SAME PRODUCT',
  comparisonKey: 'Group',
  packageValue: package ? BigInt.from(size) : null,
  packageScale: package ? scale : null,
  packageUnit: package ? unit : null,
);
ProductPurchase purchase({
  int branch = 2,
  int cents = 300,
  int? quantity = 2,
  int scale = 0,
  QuantityUnit unit = QuantityUnit.piece,
  int day = 16,
  int discount = 0,
}) {
  final r = row(
    number: 3,
    cents: BigInt.from(cents),
    quantity: quantity == null ? null : BigInt.from(quantity),
    scale: quantity == null ? null : scale,
    unit: quantity == null ? null : unit,
    rate: quantity == null
        ? null
        : BigInt.from(cents).abs() *
              BigInt.from(10).pow(scale + 4) ~/
              BigInt.from(quantity).abs(),
    product: ReceiptProductLink(
      id: id(10),
      storeId: id(branch),
      revision: RevisionId(id(9), BigInt.one),
    ),
  );
  return ProductPurchase.fromReceipt(
    receipt(
      branch: ReceiptBranch(id: id(branch), name: 'Branch'),
      date: '$day.11.2026',
      total: BigInt.from(cents + discount),
      items: [
        r,
        if (discount != 0)
          row(
            number: 4,
            cents: BigInt.from(discount),
            kind: LineKind.discount,
            scope: DiscountScope.item,
            parent: r.id,
          ),
      ],
    ),
    r.id,
  );
}

ProductComparisonBuilder builder() => ProductComparisonBuilder(
  purchaseCalendarDay(StoredReceiptDate.parse('1.11.2026')),
  purchaseCalendarDay(StoredReceiptDate.parse('30.11.2026')),
);
void main() {
  test('v3 explicit groups round-trip with nullable category; v1/v2 canonical bytes retained', () {
    final d = product(snapshot: saved());
    final text = ProductDocumentCodec.encode(d);
    expect(jsonDecode(text)['payload_version'], '3');
    expect(
      ProductDocumentCodec.encode(ProductDocumentCodec.decode(text)),
      text,
    );
    expect(ProductDocumentCodec.decode(text).product.comparisonKey, 'Group');
    for (final bad in [
      text.replaceFirst('"comparison_key":"Group"', '"comparison_key":null'),
      text.replaceFirst(
        '"comparison_key":"Group"',
        '"comparison_key":" Group"',
      ),
      text.replaceFirst('"payload_version":"3"', '"payload_version":"2"'),
    ]) {
      expect(
        () => ProductDocumentCodec.decode(bad),
        throwsA(isA<ReceiptDataException>()),
      );
    }
    final old = ProductDocumentCodec.encode(product());
    expect(jsonDecode(old)['payload_version'], '1');
    expect(ProductDocumentCodec.decode(old).product.comparisonKey, isNull);
  });
  test('pack sizes normalize exactly and quantity weights combine direct kg with packs', () {
    final b = builder(), branch = ReceiptBranch(id: id(2), name: 'Branch');
    b.add(purchase(cents: 300), saved(), branch); // 2*0.5kg = 1kg
    b.add(purchase(cents: 500, quantity: 1), saved(size: 1, scale: 0), branch);
    b.add(
      purchase(cents: 200, quantity: 5, scale: 1, unit: QuantityUnit.kg),
      saved(package: false),
      branch,
    );
    expect(b.finish().series.single.weightedMean.euros, '4,0000');
    expect(b.finish().series.single.count, 3);
  });
  test('kg/l/piece series stay separate; discounts apply before division', () {
    final b = builder(), branch = ReceiptBranch(id: id(2), name: 'Branch');
    b.add(purchase(discount: -100), saved(), branch);
    b.add(purchase(), saved(unit: QuantityUnit.litre), branch);
    b.add(
      purchase(),
      saved(size: 6, scale: 0, unit: QuantityUnit.piece),
      branch,
    );
    final d = b.finish();
    expect(d.series, hasLength(3));
    expect(
      d.series.singleWhere((s) => s.unit == QuantityUnit.kg).weightedMean.euros,
      '2,0000',
    );
    expect(
      d.series
          .singleWhere((s) => s.unit == QuantityUnit.piece)
          .weightedMean
          .euros,
      '0,2500',
    );
  });
  test('returns, missing quantities and packages, negative net excluded; free purchases valid', () {
    final b = builder(), branch = ReceiptBranch(id: id(2), name: 'Branch');
    for (final p in [
      purchase(cents: -300, quantity: -2),
      purchase(quantity: null),
      purchase(cents: 10, discount: -100),
      purchase(cents: 0),
    ]) {
      b.add(p, saved(), branch);
    }
    b.add(purchase(), saved(package: false), branch);
    final d = b.finish();
    expect(
      (
        d.totalRows,
        d.comparableRows,
        d.returnRows,
        d.missingQuantityRows,
        d.missingPackageRows,
        d.negativeRows,
      ),
      (5, 1, 1, 1, 1, 1),
    );
    expect(d.series.single.weightedMean.euros, '0,0000');
  });
  test(
    'full 12 decimal quantity precision and beyond-int64 folds stay exact',
    () {
      final p = purchase(cents: 1, quantity: 1, scale: 6);
      expect(
        comparisonQuantity(p, saved(size: 1, scale: 6))!.value,
        BigInt.one,
      );
      final b = builder(), branch = ReceiptBranch(id: id(2), name: 'Branch');
      for (var i = 0; i < 1100; i++) {
        b.add(
          purchase(cents: 9007199254740993, quantity: 10000),
          saved(size: 1, scale: 0),
          branch,
        );
      }
      expect(
        b.finish().series.single.weightedMean.numerator ~/
            b.finish().series.single.weightedMean.denominator,
        BigInt.parse('9007199254740993') ~/ BigInt.from(10000),
      );
    },
  );
  test('shared buckets retain gaps and deterministic branch identity', () {
    final b = builder();
    b.add(purchase(day: 1), saved(), ReceiptBranch(id: id(2), name: 'Same'));
    b.add(purchase(day: 30), saved(), ReceiptBranch(id: id(2), name: 'Same'));
    b.add(
      purchase(branch: 20),
      saved(branch: 20),
      ReceiptBranch(id: id(20), name: 'Same'),
    );
    final d = b.finish();
    expect(d.series, hasLength(2));
    expect(d.series.first.buckets, hasLength(2));
    expect(
      d.series.first.buckets.first.lastDay,
      lessThan(d.series.first.buckets.last.firstDay - 1),
    );
    expect(ProductComparisonBuilder(null, null).finish().series, isEmpty);
  });
  test(
    'comparison series overflow rejects complete result instead of truncating',
    () {
      final b = builder();
      for (var i = 0; i < 64; i++) {
        b.add(
          purchase(branch: 100 + i),
          saved(branch: 100 + i),
          ReceiptBranch(id: id(100 + i), name: 'Branch'),
        );
      }
      expect(
        () => b.add(
          purchase(branch: 200),
          saved(branch: 200),
          ReceiptBranch(id: id(200), name: 'Branch'),
        ),
        throwsA(
          isA<ReceiptDataException>().having(
            (e) => e.code,
            'code',
            'groupLimit',
          ),
        ),
      );
    },
  );
}
