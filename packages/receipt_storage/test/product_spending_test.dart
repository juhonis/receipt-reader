import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'catalog_support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  late ReceiptBranch branch;
  late StoredProduct a, b;
  setUp(() async {
    h = await Harness.create();
    await h.repository.saveManual(command(snapshot(date: '1.10.2026')));
    branch = (await h.repository.branches()).single;
    await h.repository.saveProduct(
      productDocument(branch, name: 'CANONICAL A'),
      mutationId: id(12),
    );
    await h.repository.saveProduct(
      productDocument(branch, number: 11, name: 'CANONICAL B'),
      mutationId: id(13),
    );
    a = (await h.repository.readProduct(id(10)))!;
    b = (await h.repository.readProduct(id(11)))!;
  });
  tearDown(() => h.dispose());
  SpendingDashboardQuery query({DurableId? store, String? day}) =>
      SpendingDashboardQuery(
        unit: day == null
            ? SpendingPeriodUnit.month
            : SpendingPeriodUnit.custom,
        anchor: StoredReceiptDate.parse(day ?? '18.11.2026'),
        today: StoredReceiptDate.parse('18.11.2026'),
        branchId: store,
        customFrom: day == null ? null : StoredReceiptDate.parse(day),
        customThrough: day == null ? null : StoredReceiptDate.parse(day),
      );
  Future<StoredReceipt> save(
    int n,
    StoredProduct? product, {
    int cents = 200,
    String date = '17.11.2026',
    ReceiptBranch? at,
    int discount = 0,
    bool extras = false,
    int? duplicate,
  }) async {
    final base = 10000 + n * 10;
    final rows = [
      ReceiptItemSnapshot(
        id: id(base + 1),
        name: 'PRINTED ALIAS',
        kind: LineKind.product,
        cents: BigInt.from(cents),
        product: product?.link,
      ),
      if (duplicate != null)
        ReceiptItemSnapshot(
          id: id(base + 2),
          name: 'SECOND ALIAS',
          kind: LineKind.product,
          cents: BigInt.from(duplicate),
          product: product?.link,
        ),
      if (discount < 0)
        ReceiptItemSnapshot(
          id: id(base + 3),
          name: 'ITEM DISCOUNT',
          kind: LineKind.discount,
          cents: BigInt.from(discount),
          parentItemId: id(base + 1),
          discountScope: DiscountScope.item,
        ),
      if (extras) ...[
        ReceiptItemSnapshot(
          id: id(base + 4),
          name: 'DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(40),
          parentItemId: id(base + 1),
        ),
        ReceiptItemSnapshot(
          id: id(base + 5),
          name: 'RECEIPT DISCOUNT',
          kind: LineKind.discount,
          cents: BigInt.from(-20),
          discountScope: DiscountScope.receipt,
        ),
        ReceiptItemSnapshot(
          id: id(base + 6),
          name: 'ADJUSTMENT',
          kind: LineKind.adjustment,
          cents: BigInt.from(5),
          adjustmentReason: 'SYNTHETIC CHECKED',
        ),
      ],
    ];
    final value = snapshot(
      number: base,
      branch: at ?? branch,
      date: date,
      items: rows,
      total: rows.fold<BigInt>(BigInt.zero, (sum, row) => sum + row.cents),
    );
    await h.repository.saveManual(command(value, mutation: base + 7));
    return (await h.repository.read(value.id))!;
  }

  test('all scan batches rank full signed amounts and reconcile every selected receipt row', () async {
    for (var i = 0; i < 67; i++) {
      await save(
        i,
        i < 40 ? a : b,
        cents: 200 + i,
        discount: i == 0 ? -10 : 0,
        extras: i == 0,
        date: i < 40 ? '16.11.2026 00:00' : '17.11.2026 23:59:59',
      );
    }
    await save(70, null, cents: 500, discount: -50);
    await save(71, a, cents: 9000, date: '19.11.2026');
    await save(72, a, cents: 9000, date: '18.10.2026');
    final before = await h.repository.exportBackup();
    final data = await h.repository.spendingDashboard(query());
    expect(data.products.groups.map((g) => g.totalCents), [
      BigInt.from(8770),
      BigInt.from(6831),
    ]);
    expect(data.products.groups.map((g) => g.name), [
      'CANONICAL A',
      'CANONICAL B',
    ]);
    expect(data.products.linkedRows, 67);
    expect(data.products.productRows, 68);
    expect(data.products.unlinkedCents, BigInt.from(450));
    expect(data.products.receiptTotalCents, BigInt.from(16076));
    expect(data.products.receiptTotalCents, data.selected.totalCents);
    final day = await h.repository.spendingDashboard(query(day: '17.11.2026'));
    expect(day.products.groups.single.productId, b.link.id);
    expect(day.products.groups.single.rowCount, 27);
    final purchases = await h.repository.purchaseHistory(
      branch.id,
      b.link.id,
      range: PurchaseDateRange(
        fromDate: StoredReceiptDate.parse('17.11.2026'),
        throughDate: StoredReceiptDate.parse('17.11.2026'),
      ),
    );
    expect(purchases.summary.effectiveCents, day.products.linkedCents);
    expect(await h.repository.exportBackup(), before);
  });
  test('equal names at different branches stay separate and branch filtering is exact', () async {
    await save(1, a);
    final other = ReceiptBranch(id: id(50000), name: branch.name);
    await h.repository.saveManual(
      command(
        snapshot(
          number: 50001,
          branch: other,
          date: '1.10.2026',
          items: [row(number: 50002)],
        ),
        mutation: 50003,
      ),
    );
    final current = (await h.repository.branches()).firstWhere(
      (v) => v.id == other.id,
    );
    await h.repository.saveProduct(
      productDocument(current, number: 50004, name: 'CANONICAL A'),
      mutationId: id(50005),
    );
    final product = (await h.repository.readProduct(id(50004)))!;
    await save(2, product, cents: 300, at: current);
    final all = await h.repository.spendingDashboard(query());
    expect(all.products.groups.length, 2);
    expect(all.products.groups.map((p) => p.name).toSet(), {'CANONICAL A'});
    final selected = await h.repository.spendingDashboard(
      query(store: branch.id),
    );
    expect(selected.products.groups.single.productId, a.link.id);
    expect(selected.products.linkedCents, BigInt.from(200));
  });
  test('returns, zero nets and duplicate products have exact product and receipt counts', () async {
    await save(1, a, duplicate: 100, discount: -50);
    await save(2, a, cents: -200, discount: -10);
    await save(3, b, cents: 200, discount: -200);
    final data = (await h.repository.spendingDashboard(query())).products;
    expect(data.groups.map((p) => p.totalCents), [
      BigInt.from(40),
      BigInt.zero,
    ]);
    expect(data.groups.first.rowCount, 3);
    expect(data.groups.first.receiptCount, 2);
    expect(data.groups.first.returnRows, 1);
    expect(data.groups.first.returnCents, BigInt.from(-210));
  });
  test('catalog rename uses current label while receipt documents remain unchanged', () async {
    final saved = await save(1, a);
    final bytes = ReceiptDocumentCodec.encode(saved.document);
    await h.repository.saveProduct(
      productDocument(branch, head: a.revision, name: 'RENAMED'),
      mutationId: id(50000),
    );
    final data = await h.repository.spendingDashboard(query());
    expect(data.products.groups.single.name, 'RENAMED');
    expect(data.products.linkedCents, BigInt.from(200));
    expect(
      ReceiptDocumentCodec.encode(
        (await h.repository.read(saved.document.snapshot.id))!.document,
      ),
      bytes,
    );
  });
  test('unlink, deletion, encrypted recovery and reopen produce the correct current ranking', () async {
    final first = await save(1, a), second = await save(2, b, cents: 300);
    final before = await h.repository.exportBackup();
    final encrypted = await ProtectedBackup.encrypt(
      before,
      'synthetic ranking password',
    );
    await h.repository.saveManual(
      ReviewedReceipt.productLinks(
        confirmation: ProductLinkReviewChecks(
          base: second.document,
          expectedHead: second.revision,
          selections: {second.document.snapshot.items.first.id: null},
          mutationId: id(50001),
        ).confirm(reviewedAtMs: BigInt.from(3000), appVersion: 'ranking-test'),
      ),
    );
    var data = (await h.repository.spendingDashboard(query())).products;
    expect(data.groups.single.productId, a.link.id);
    expect(data.unlinkedCents, BigInt.from(300));
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: first.document,
        expectedHead: first.revision,
        mutationId: id(50002),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(3001), appVersion: 'ranking-test'),
    );
    expect(
      (await h.repository.spendingDashboard(query())).products.groups,
      isEmpty,
    );
    final restored = await ReceiptRepository.restoreBackup(
      await ProtectedBackup.decrypt(encrypted, 'synthetic ranking password'),
      stagingParent: h.directory,
    );
    final recovered = await ReceiptRepository.open(restored.databaseFile);
    try {
      data = (await recovered.spendingDashboard(query())).products;
      expect(data.groups.map((g) => g.productId), [b.link.id, a.link.id]);
      expect(data.linkedCents, BigInt.from(500));
      expect(await recovered.exportBackup(), before);
    } finally {
      await recovered.close();
    }
    await h.reopen();
    expect(
      (await h.repository.spendingDashboard(query())).products.groups,
      isEmpty,
    );
  });
  test('metadata cache eviction and more than one list page preserve complete rankings', () async {
    for (var i = 0; i < 140; i++) {
      await h.repository.saveProduct(
        productDocument(branch, number: 100 + i, name: 'PRODUCT $i'),
        mutationId: id(1000 + i),
      );
      await save(
        i,
        (await h.repository.readProduct(id(100 + i)))!,
        cents: i + 1,
      );
    }
    await save(150, (await h.repository.readProduct(id(100)))!, cents: 150);
    final data = (await h.repository.spendingDashboard(query())).products;
    expect(data.groups.length, 140);
    expect(data.linkedRows, 141);
    expect(data.limitExceeded, isFalse);
    expect(data.groups.first.productId, id(100));
    expect(data.groups.first.name, 'PRODUCT 0');
    expect(data.linkedCents, BigInt.from(10020));
    expect(
      data.groups.fold(BigInt.zero, (sum, g) => sum + g.totalCents),
      data.linkedCents,
    );
  });
}
