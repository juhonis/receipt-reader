import 'dart:convert';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

const demoDataVersion = 'demo-data/1';
DurableId demoDataId(int n) =>
    DurableId.parse('de100001-0000-4000-8000-${n.toString().padLeft(12, '0')}');
const _shops = [
  ('DEMO Mallimarket Keskusta', 'Kuvitteellinen Keskuskatu 1'),
  ('DEMO Mallimarket Tori', 'Kuvitteellinen Torikatu 2'),
  ('DEMO Mallikioski Asema', 'Kuvitteellinen Asematie 3'),
];
const _products = [
  ('milk', 'DEMO Kevytmaito 1 l', 'Ruoka ja juoma', QuantityUnit.piece),
  ('bread', 'DEMO Ruispalat 660 g', 'Ruoka ja juoma', QuantityUnit.piece),
  ('banana', 'DEMO Banaani', 'Ruoka ja juoma', QuantityUnit.kg),
  ('coffee', 'DEMO Suodatinkahvi 500 g', 'Ruoka ja juoma', QuantityUnit.piece),
  ('apple', 'DEMO Omena', 'Ruoka ja juoma', QuantityUnit.kg),
  ('soap', 'DEMO Käsisaippua', 'Hygienia ja terveys', QuantityUnit.piece),
  ('toothpaste', 'DEMO Hammastahna', 'Hygienia ja terveys', QuantityUnit.piece),
  ('detergent', 'DEMO Pyykinpesuaine', 'Kodinhoito', QuantityUnit.piece),
  ('dish', 'DEMO Astianpesuaine', 'Kodinhoito', QuantityUnit.piece),
  ('soda', 'DEMO Kivennäisvesi 0,5 l', 'Ruoka ja juoma', QuantityUnit.piece),
  ('notebook', 'DEMO Muistivihko', 'Vapaa-aika', QuantityUnit.piece),
  ('battery', 'DEMO Paristot 4 kpl', 'Muut', QuantityUnit.piece),
];

typedef _Line = ({
  String code,
  int quantity,
  int scale,
  int rate,
  int discount,
  int deposit,
});
_Line _line(
  String code,
  int q,
  int cents, {
  int scale = 0,
  int discount = 0,
  int deposit = 0,
}) => (
  code: code,
  quantity: q,
  scale: scale,
  rate: cents,
  discount: discount,
  deposit: deposit,
);

final class _Basket {
  _Basket(
    this.shop,
    this.daysAgo,
    this.lines, {
    this.receiptDiscount = 0,
    this.bag = 0,
    this.adjustment = 0,
    this.returnedDeposits = 0,
  });
  final int shop, daysAgo, receiptDiscount, bag, adjustment, returnedDeposits;
  final List<_Line> lines;
}

List<_Basket> _baskets() => [
  _Basket(0, 0, [
    _line('milk', 2, 119),
    _line('bread', 1, 269),
    _line('banana', 860, 189, scale: 3),
    _line('coffee', 1, 749, discount: -100),
    _line('soda', 2, 109, deposit: 40),
    _line('soap', 1, 299),
  ], receiptDiscount: -50),
  _Basket(1, 1, [
    _line('milk', 1, 129),
    _line('bread', 2, 249),
    _line('apple', 1200, 249, scale: 3),
    _line('detergent', 1, 899),
    _line('toothpaste', 1, 349),
    _line('notebook', 2, 349),
  ]),
  _Basket(2, 0, [_line('battery', -1, 499)], returnedDeposits: -40),
  _Basket(0, 7, [
    _line('milk', 2, 115),
    _line('coffee', 2, 699, discount: -200),
    _line('banana', 640, 179, scale: 3),
    _line('dish', 1, 239),
    _line('soda', 4, 99, deposit: 80),
  ]),
  _Basket(
    1,
    8,
    [
      _line('detergent', 1, 849),
      _line('toothpaste', 2, 329),
      _line('soap', 2, 279),
      _line('battery', 1, 549),
    ],
    bag: 30,
    adjustment: 2,
  ),
  _Basket(0, 14, [
    _line('milk', 3, 109),
    _line('bread', 1, 239),
    _line('coffee', 1, 599),
    _line('apple', 950, 219, scale: 3),
    _line('soda', 2, 99, deposit: 40),
  ]),
  _Basket(2, 20, [
    _line('notebook', 3, 299),
    _line('battery', 2, 499, discount: -50),
    _line('soda', 1, 149, deposit: 20),
  ]),
  _Basket(0, 31, [
    _line('coffee', 2, 549),
    _line('milk', 2, 105),
    _line('bread', 2, 229),
    _line('banana', 1050, 169, scale: 3),
    _line('detergent', 1, 799),
    _line('soda', 6, 89, deposit: 120),
  ], receiptDiscount: -150),
  _Basket(1, 51, [
    _line('milk', 2, 119),
    _line('soap', 1, 259),
    _line('dish', 1, 229),
    _line('apple', 1400, 199, scale: 3),
    _line('bread', 1, 239),
    _line('toothpaste', 1, 299),
  ]),
  _Basket(0, 180, [
    _line('coffee', 1, 499),
    _line('milk', 2, 99),
    _line('bread', 1, 209),
    _line('banana', 750, 149, scale: 3),
    _line('notebook', 1, 249),
  ]),
];

ReceiptBranch _branch(int shop) => ReceiptBranch(
  id: demoDataId(100 + shop),
  name: _shops[shop].$1,
  chain: 'DEMO – kuvitteellinen aineisto',
  address: _shops[shop].$2,
);
int _productIndex(String code) => _products.indexWhere((p) => p.$1 == code);
DurableId _productId(int shop, String code) =>
    demoDataId(1000 + shop * 100 + _productIndex(code));

({ReceiptSnapshot receipt, Map<DurableId, DurableId> products}) _receipt(
  int index,
  _Basket basket,
  StoredReceiptDate anchor,
  ReceiptBranch branch,
) {
  final rows = <ReceiptItemSnapshot>[], links = <DurableId, DurableId>{};
  DurableId next() => demoDataId(10000 + index * 100 + rows.length);
  for (final line in basket.lines) {
    final spec = _products[_productIndex(line.code)];
    final rowId = next();
    final quantity = Quantity(BigInt.from(line.quantity), line.scale, spec.$4);
    final rate = BigInt.from(line.rate) * BigInt.from(10000);
    rows.add(
      ReceiptItemSnapshot(
        id: rowId,
        name: spec.$2,
        kind: LineKind.product,
        cents: extendedCents(quantity, rate),
        quantityValue: quantity.value,
        quantityScale: quantity.scale,
        quantityUnit: quantity.unit,
        rateMicros: rate,
      ),
    );
    links[rowId] = _productId(basket.shop, line.code);
    if (line.discount != 0) {
      rows.add(
        ReceiptItemSnapshot(
          id: next(),
          name: 'DEMO Rivitarjous',
          kind: LineKind.discount,
          cents: BigInt.from(line.discount),
          parentItemId: rowId,
          discountScope: DiscountScope.item,
        ),
      );
    }
    if (line.deposit != 0) {
      rows.add(
        ReceiptItemSnapshot(
          id: next(),
          name: 'DEMO Pantti',
          kind: LineKind.deposit,
          cents: BigInt.from(line.deposit),
          parentItemId: rowId,
        ),
      );
    }
  }
  if (basket.bag != 0) {
    rows.add(
      ReceiptItemSnapshot(
        id: next(),
        name: 'DEMO Pakkauspussi (liittämätön)',
        kind: LineKind.product,
        cents: BigInt.from(basket.bag),
      ),
    );
  }
  if (basket.receiptDiscount != 0) {
    rows.add(
      ReceiptItemSnapshot(
        id: next(),
        name: 'DEMO Kuittialennus',
        kind: LineKind.discount,
        cents: BigInt.from(basket.receiptDiscount),
        discountScope: DiscountScope.receipt,
      ),
    );
  }
  if (basket.returnedDeposits != 0) {
    rows.add(
      ReceiptItemSnapshot(
        id: next(),
        name: 'DEMO Pullopanttien palautus',
        kind: LineKind.deposit,
        cents: BigInt.from(basket.returnedDeposits),
      ),
    );
  }
  if (basket.adjustment != 0) {
    rows.add(
      ReceiptItemSnapshot(
        id: next(),
        name: 'DEMO Pyöristysoikaisu',
        kind: LineKind.adjustment,
        cents: BigInt.from(basket.adjustment),
        adjustmentReason: 'DEMO: kuvitteellinen tarkistettu pyöristysero',
      ),
    );
  }
  final day = purchaseCalendarDate(
    purchaseCalendarDay(anchor) - basket.daysAgo,
  );
  return (
    receipt: ReceiptSnapshot(
      id: demoDataId(200 + index),
      branch: branch,
      date: day,
      totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
      items: rows,
    ),
    products: links,
  );
}

String _financial(ReceiptSnapshot snapshot) {
  final value =
      jsonDecode(ReceiptSnapshotCodec.encode(snapshot)) as Map<String, dynamic>;
  value['branch']['revision'] = null;
  for (final row in value['items'] as List) {
    (row as Map)['product'] = null;
  }
  return jsonEncode(value);
}

void _requireDemo(bool ok, String code) {
  if (!ok) throw StateError('demo_data_$code');
}

final class DemoDataResult {
  const DemoDataResult(
    this.createdReceipts,
    this.createdProducts,
    this.linkedReceipts,
    this.receipts,
    this.weekCents,
    this.monthCents,
    this.yearCents,
  );
  final int createdReceipts, createdProducts, linkedReceipts, receipts;
  final BigInt weekCents, monthCents, yearCents;
}

/// Development-only additive loader. Checks all reserved identities before its
/// first write and refuses edits/deletions/collisions instead of overwriting them.
Future<DemoDataResult> loadDemoReceipts(
  ReceiptRepository repository,
  StoredReceiptDate anchor,
) async {
  _requireDemo(
    anchor.hour == null && purchaseCalendarDay(anchor) >= 180,
    'anchor',
  );
  final baskets = _baskets();
  final used = {
    for (final b in baskets)
      for (final line in b.lines) (b.shop, line.code),
  };
  final branches = {for (final b in await repository.branches()) b.id: b};
  final existing = <DurableId, StoredReceipt>{};
  for (var i = 0; i < _shops.length; i++) {
    final branch = branches[demoDataId(100 + i)];
    _requireDemo(
      branch == null ||
          (branch.name == _shops[i].$1 &&
              branch.address == _shops[i].$2 &&
              branch.chain == _branch(i).chain),
      'branch_collision',
    );
  }
  for (final entry in used) {
    final product = await repository.readProduct(
      _productId(entry.$1, entry.$2),
    );
    final spec = _products[_productIndex(entry.$2)];
    _requireDemo(
      product == null ||
          (product.document.appVersion == demoDataVersion &&
              product.document.product.storeId == demoDataId(100 + entry.$1) &&
              product.document.product.canonicalName == spec.$2 &&
              product.document.product.category == spec.$3 &&
              product.document.product.packageValue == null),
      'product_edited_or_collision',
    );
  }
  for (var i = 0; i < baskets.length; i++) {
    final expected = _receipt(i, baskets[i], anchor, _branch(baskets[i].shop));
    _requireDemo(
      await repository.readDeleted(expected.receipt.id) == null,
      'receipt_deleted',
    );
    final saved = await repository.read(expected.receipt.id);
    if (saved == null) continue;
    _requireDemo(
      saved.document.review.appVersion == demoDataVersion &&
          saved.document.review.source == 'manual' &&
          _financial(saved.document.snapshot) == _financial(expected.receipt),
      'receipt_edited_or_collision',
    );
    final linked = saved.document.snapshot.items
        .where((r) => expected.products.containsKey(r.id))
        .toList();
    final initial =
        saved.document.review.policyVersion == 1 &&
        linked.every((r) => r.product == null);
    final complete =
        saved.document.review.policyVersion == 4 &&
        linked.every((r) => r.product?.id == expected.products[r.id]);
    _requireDemo(initial || complete, 'receipt_links_edited');
    existing[saved.document.snapshot.id] = saved;
  }
  var created = 0, createdProducts = 0, linked = 0;
  BigInt now() => BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch);
  for (var i = 0; i < baskets.length; i++) {
    if (existing.containsKey(demoDataId(200 + i))) continue;
    final b = baskets[i];
    final current = _receipt(
      i,
      b,
      anchor,
      branches[demoDataId(100 + b.shop)] ?? _branch(b.shop),
    ).receipt;
    await repository.saveManual(
      ReviewedReceipt.manual(
        current: current,
        expectedHeads: [],
        confirmation: ManualReviewChecks(
          snapshot: current,
          expectedHeads: [],
          mutationId: demoDataId(40000 + i),
          branchReviewed: true,
          dateReviewed: true,
          totalReviewed: true,
          reviewedRowIds: current.items.map((r) => r.id),
        ).confirm(reviewedAtMs: now(), appVersion: demoDataVersion),
      ),
    );
    branches.addAll({
      for (final branch in await repository.branches()) branch.id: branch,
    });
    created++;
  }
  final products = <DurableId, StoredProduct>{};
  for (final entry in used) {
    final id = _productId(entry.$1, entry.$2);
    var product = await repository.readProduct(id);
    if (product == null) {
      final spec = _products[_productIndex(entry.$2)];
      await repository.saveProduct(
        ProductDocument(
          product: ProductSnapshot(
            id: id,
            storeId: demoDataId(100 + entry.$1),
            canonicalName: spec.$2,
            category: spec.$3,
          ),
          storeRevision: branches[demoDataId(100 + entry.$1)]!.revision!,
          expectedHead: null,
          reviewedAtMs: now(),
          appVersion: demoDataVersion,
        ),
        mutationId: demoDataId(
          50000 + entry.$1 * 100 + _productIndex(entry.$2),
        ),
      );
      product = (await repository.readProduct(id))!;
      createdProducts++;
    }
    products[id] = product;
  }
  for (var i = 0; i < baskets.length; i++) {
    final saved = (await repository.read(demoDataId(200 + i)))!;
    if (saved.document.review.policyVersion == 4) continue;
    final mapping = _receipt(
      i,
      baskets[i],
      anchor,
      _branch(baskets[i].shop),
    ).products;
    await repository.saveManual(
      ReviewedReceipt.productLinks(
        confirmation: ProductLinkReviewChecks(
          base: saved.document,
          expectedHead: saved.revision,
          selections: {
            for (final entry in mapping.entries)
              entry.key: products[entry.value]!.link,
          },
          mutationId: demoDataId(60000 + i),
        ).confirm(reviewedAtMs: now(), appVersion: demoDataVersion),
      ),
    );
    linked++;
  }
  final totals = <BigInt>[];
  for (final unit in [
    SpendingPeriodUnit.week,
    SpendingPeriodUnit.month,
    SpendingPeriodUnit.year,
  ]) {
    final builder = SpendingDashboardBuilder(
      SpendingDashboardQuery(unit: unit, anchor: anchor, today: anchor),
    );
    for (var i = 0; i < baskets.length; i++) {
      final saved = (await repository.read(demoDataId(200 + i)))!;
      builder.add(
        saved.document.snapshot,
        products: {
          for (final p in products.values) p.link.id: p.document.product,
        },
        productCategories: {
          for (final p in products.values)
            p.link.id: p.document.product.category,
        },
      );
    }
    totals.add(builder.build().selected.totalCents);
  }
  await repository.verifyIntegrity();
  return DemoDataResult(
    created,
    createdProducts,
    linked,
    baskets.length,
    totals[0],
    totals[1],
    totals[2],
  );
}
