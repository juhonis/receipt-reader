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
  Future<StoredReceipt> save(
    int n, {
    String date = '17.11.2026',
    int cents = 200,
    int quantity = 1,
    bool quantified = true,
    int discount = 0,
    QuantityUnit unit = QuantityUnit.kg,
    bool warnings = false,
    StoredProduct? selected,
  }) async {
    final base = 1000 + n * 10;
    final item = ReceiptItemSnapshot(
      id: id(base + 1),
      name: 'TEST MILK',
      kind: LineKind.product,
      cents: BigInt.from(cents),
      product: (selected ?? product).link,
      quantityValue: quantified ? BigInt.from(quantity) : null,
      quantityScale: quantified ? 0 : null,
      quantityUnit: quantified ? unit : null,
      rateMicros: quantified ? BigInt.from(cents ~/ quantity * 10000) : null,
    );
    final rows = [
      item,
      if (discount < 0)
        ReceiptItemSnapshot(
          id: id(base + 2),
          name: 'SALE',
          kind: LineKind.discount,
          cents: BigInt.from(discount),
          parentItemId: item.id,
          discountScope: DiscountScope.item,
        ),
      if (warnings) ...[
        ReceiptItemSnapshot(
          id: id(base + 3),
          name: 'DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(40),
          parentItemId: item.id,
        ),
        ReceiptItemSnapshot(
          id: id(base + 4),
          name: 'RECEIPT SALE',
          kind: LineKind.discount,
          cents: BigInt.from(-10),
          discountScope: DiscountScope.receipt,
        ),
        ReceiptItemSnapshot(
          id: id(base + 5),
          name: 'ADJUSTMENT',
          kind: LineKind.adjustment,
          cents: BigInt.one,
          adjustmentReason: 'Reviewed',
        ),
      ],
    ];
    final s = snapshot(
      number: base,
      branch: branch,
      date: date,
      items: rows,
      total: rows.fold<BigInt>(BigInt.zero, (sum, r) => sum + r.cents),
    );
    await h.repository.saveManual(command(s, mutation: base + 6));
    return (await h.repository.read(s.id))!;
  }

  Future<PurchaseHistoryResult> read({
    PurchaseDateRange? range,
    int offset = 0,
  }) => h.repository.purchaseHistory(
    branch.id,
    product.document.product.id,
    range: range,
    offset: offset,
  );

  test('all selected rows contribute beyond pages and scan batches; inclusive bounds filter details and summary together', () async {
    for (var i = 0; i < 67; i++) {
      await save(
        i,
        cents: 200 + i,
        date: i < 40 ? '16.11.2026 00:00' : '17.11.2026 23:59:59',
      );
    }
    await save(67, cents: 999, date: '15.11.2026');
    await save(68, cents: 999, date: '18.11.2026');
    await h.repository.saveProduct(
      productDocument(branch, number: 13),
      mutationId: id(14),
    );
    await save(
      69,
      cents: 999,
      selected: (await h.repository.readProduct(id(13)))!,
    );
    final range = PurchaseDateRange(
      fromDate: StoredReceiptDate.parse('16.11.2026'),
      throughDate: StoredReceiptDate.parse('17.11.2026'),
    );
    final before = await h.repository.exportBackup();
    for (final offset in [0, 30, 60, 90]) {
      final data = await read(range: range, offset: offset);
      expect(data.summary.totalRows, 67);
      expect(data.summary.comparableRows, 67);
      expect(data.summary.rawCents, BigInt.from(15611));
      expect(data.summary.groups.single.minimum.euros, '2,0000');
      expect(data.summary.groups.single.maximum.euros, '2,6600');
      expect(data.summary.groups.single.buckets.map((b) => b.count), [40, 27]);
      expect(
        data.purchases.length,
        offset < 60
            ? 30
            : offset == 60
            ? 7
            : 0,
      );
      expect(
        data.purchases.every((p) => range.contains(p.purchase.date)),
        isTrue,
      );
      expect(
        (await h.repository.purchases(
          branch.id,
          id(10),
          range: range,
          offset: offset,
        )).map((p) => p.purchase.row.id),
        data.purchases.map((p) => p.purchase.row.id),
      );
    }
    expect(await h.repository.exportBackup(), before);
    expect((await read()).summary.totalRows, 69);
    expect(
      (await read(range: PurchaseDateRange(throughDate: range.fromDate)))
          .summary
          .totalRows,
      41,
    );
    expect(
      (await read(range: PurchaseDateRange(fromDate: range.throughDate)))
          .summary
          .totalRows,
      28,
    );
    expect(
      (await h.repository.purchaseHistory(id(999), id(10))).summary.totalRows,
      0,
    );
    expect(
      () => h.repository.purchaseHistory(branch.id, id(10), limit: 201),
      throwsArgumentError,
    );
    final empty = await read(
      range: PurchaseDateRange(fromDate: StoredReceiptDate.parse('1.1.2027')),
    );
    expect(empty.summary.totalRows, 0);
    expect(empty.summary.groups, isEmpty);
    expect(empty.purchases, isEmpty);
  });

  test('exclusions and warnings count rows; corrections, deletion and reopening affect the entire summary', () async {
    final original = await save(
      1,
      cents: 400,
      quantity: 2,
      discount: -100,
      warnings: true,
    );
    await save(2, cents: -400, quantity: -2);
    await save(3, quantified: false);
    await save(4, discount: -201);
    await save(5, discount: -200);
    var data = await read();
    expect(data.summary.totalRows, 5);
    expect(data.summary.comparableRows, 2);
    expect(data.summary.returnRows, 1);
    expect(data.summary.missingQuantityRows, 1);
    expect(data.summary.negativeEffectiveRows, 1);
    expect(data.summary.receiptDiscountRows, 1);
    expect(data.summary.adjustmentRows, 1);
    expect(data.summary.groups.single.minimum.euros, '0,0000');
    expect(data.summary.groups.single.maximum.euros, '1,5000');
    final unlinked = snapshot(
      number: 1010,
      branch: branch,
      items: [row(number: 1011)],
      total: BigInt.from(200),
    );
    await h.repository.saveManual(
      command(unlinked, mutation: 6000, heads: [original.revision]),
    );
    data = await read();
    expect(data.summary.totalRows, 4);
    expect(data.summary.receiptDiscountRows, 0);
    expect(data.summary.adjustmentRows, 0);
    final free = data.purchases
        .firstWhere((p) => p.purchase.row.id == id(1051))
        .receipt;
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: free.document,
        expectedHead: free.revision,
        mutationId: id(6001),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(3000), appVersion: 'test'),
    );
    await h.reopen();
    data = await read();
    expect(data.summary.totalRows, 3);
    expect(data.summary.comparableRows, 0);
    expect(data.summary.groups, isEmpty);
    await h.repository.verifyIntegrity();
  });

  test('more than 64 piece revisions fails explicitly instead of returning a truncated history', () async {
    for (var i = 0; i < 65; i++) {
      if (i > 0) {
        await h.repository.saveProduct(
          productDocument(branch, head: product.revision, at: 1000 + i),
          mutationId: id(5000 + i),
        );
        product = (await h.repository.readProduct(id(10)))!;
      }
      await save(
        i,
        unit: QuantityUnit.piece,
        date: i == 64 ? '18.11.2026' : '17.11.2026',
      );
    }
    await expectLater(
      read(),
      throwsA(
        isA<StorageFailure>().having(
          (e) => e.code,
          'code',
          'purchaseGroupLimit',
        ),
      ),
    );
    final narrowed = await read(
      range: PurchaseDateRange(
        throughDate: StoredReceiptDate.parse('17.11.2026'),
      ),
    );
    expect(narrowed.summary.totalRows, 64);
    expect(narrowed.summary.groups, hasLength(64));
    expect(narrowed.purchases, hasLength(30));
  });
}
