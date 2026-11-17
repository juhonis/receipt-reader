import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'catalog_support.dart';
import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  late ReceiptBranch branch;
  late StoredProduct product;
  setUp(() async {
    h = await Harness.create();
    await h.repository.saveManual(command(snapshot()));
    branch = (await h.repository.branches()).single;
    await h.repository.saveProduct(productDocument(branch), mutationId: id(12));
    product = (await h.repository.readProduct(id(10)))!;
  });
  tearDown(() => h.dispose());
  ReceiptItemSnapshot linked(
    int number, {
    ReceiptProductLink? link,
    int amount = 400,
    bool quantity = true,
  }) => ReceiptItemSnapshot(
    id: id(number),
    name: 'TEST MILK',
    kind: LineKind.product,
    cents: BigInt.from(amount),
    product: link ?? product.link,
    quantityValue: quantity ? BigInt.from(2) : null,
    quantityScale: quantity ? 0 : null,
    quantityUnit: quantity ? QuantityUnit.piece : null,
    rateMicros: quantity ? BigInt.from(2000000) : null,
  );
  Future<List<StoredProductPurchase>> read({int limit = 30, int offset = 0}) =>
      h.repository.purchases(
        branch.id,
        product.document.product.id,
        limit: limit,
        offset: offset,
      );

  test('filters exact product and branch before pagination; duplicate rows and date-only dates stay deterministic', () async {
    await h.repository.saveProduct(
      productDocument(branch, number: 13),
      mutationId: id(14),
    );
    final equalNameProduct = (await h.repository.readProduct(id(13)))!;
    for (var i = 0; i < 34; i++) {
      final rows = [
        linked(200 + i * 3),
        linked(201 + i * 3),
        linked(202 + i * 3, link: equalNameProduct.link),
      ];
      await h.repository.saveManual(
        command(
          snapshot(
            number: 100 + i,
            branch: branch,
            date: i == 33 ? '17.11.2026 12:00' : '17.11.2026',
            items: rows,
            total: BigInt.from(1200),
          ),
          mutation: 500 + i,
        ),
      );
    }
    final first = await read();
    expect(first, hasLength(30));
    expect(first.first.purchase.receiptId, id(133));
    expect(first[1].purchase.row.id, id(300));
    final second = await read(offset: 30);
    final third = await read(offset: 60);
    expect(second, hasLength(30));
    expect(third, hasLength(8));
    final all = [...first, ...second, ...third];
    expect(all.map((p) => p.purchase.row.id).toSet(), hasLength(68));
    expect(all.every((p) => p.purchase.row.product!.id == id(10)), isTrue);
    expect(await h.repository.purchases(id(999), id(10)), isEmpty);
    expect(await h.repository.purchases(branch.id, id(999)), isEmpty);
    expect(await read(offset: 68), isEmpty);
    expect(() => read(limit: 201), throwsArgumentError);
    expect(() => read(limit: 0), throwsArgumentError);
    expect(() => read(offset: -1), throwsArgumentError);
  });

  test('reads are side-effect free and preserve raw amounts and related financial rows', () async {
    final rows = [
      linked(31),
      row(
        number: 32,
        cents: BigInt.from(-100),
        kind: LineKind.discount,
        parent: id(31),
        scope: DiscountScope.item,
      ),
      row(
        number: 33,
        cents: BigInt.from(40),
        kind: LineKind.deposit,
        parent: id(31),
      ),
      row(
        number: 34,
        cents: BigInt.from(-20),
        kind: LineKind.discount,
        scope: DiscountScope.receipt,
      ),
    ];
    await h.repository.saveManual(
      command(
        snapshot(
          number: 30,
          branch: branch,
          items: rows,
          total: BigInt.from(320),
        ),
        mutation: 35,
      ),
    );
    final before = await h.repository.exportBackup();
    final p = (await read()).single.purchase;
    expect(p.row.cents, BigInt.from(400));
    expect(p.effectiveCents, BigInt.from(300));
    expect(p.depositCents, BigInt.from(40));
    expect(p.receiptDiscountCents, BigInt.from(-20));
    expect(p.effectiveUnitPrice!.euros, '1,5000');
    expect(await h.repository.exportBackup(), before);
    await h.reopen();
    expect((await read()).single.purchase.row.id, id(31));
  });

  test('catalog edits do not rewrite historical links; correction, unlink and deletion replace observations', () async {
    final original = snapshot(
      number: 30,
      branch: branch,
      items: [linked(31)],
      total: BigInt.from(400),
    );
    final saved = await h.repository.saveManual(
      command(original, mutation: 32),
    );
    await h.repository.saveProduct(
      productDocument(branch, head: product.revision, name: 'UPDATED'),
      mutationId: id(33),
    );
    expect(
      (await read()).single.purchase.row.product!.revision,
      product.revision,
    );
    product = (await h.repository.readProduct(id(10)))!;
    final changed = snapshot(
      number: 30,
      branch: branch,
      items: [linked(31, amount: 500, quantity: false)],
      total: BigInt.from(500),
    );
    final corrected = await h.repository.saveManual(
      command(changed, mutation: 34, heads: [saved.revision]),
    );
    expect((await read()).single.purchase.row.cents, BigInt.from(500));
    expect((await read()).single.purchase.effectiveUnitPrice, isNull);
    final unlinked = snapshot(
      number: 30,
      branch: branch,
      items: [row(number: 31, cents: BigInt.from(500))],
      total: BigInt.from(500),
    );
    final removed = await h.repository.saveManual(
      command(unlinked, mutation: 35, heads: [corrected.revision]),
    );
    expect(await read(), isEmpty);
    final relinked = await h.repository.saveManual(
      command(changed, mutation: 36, heads: [removed.revision]),
    );
    final current = (await h.repository.read(id(30)))!;
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: current.document,
        expectedHead: relinked.revision,
        mutationId: id(37),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(2000), appVersion: 'purchase-test'),
    );
    expect(await read(), isEmpty);
    await h.reopen();
    expect(await read(), isEmpty);
    await h.repository.verifyIntegrity();
  });
}
