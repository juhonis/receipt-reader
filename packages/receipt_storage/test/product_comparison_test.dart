import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  late List<ReceiptBranch> branches;
  setUp(() async {
    h = await Harness.create();
    await h.repository.saveManual(command(snapshot()));
    await h.repository.saveManual(
      command(
        snapshot(
          number: 20,
          branch: ReceiptBranch(id: id(22), name: 'OTHER'),
          items: [row(number: 23)],
        ),
        mutation: 24,
      ),
    );
    branches = await h.repository.branches();
  });
  tearDown(() => h.dispose());
  Future<StoredProduct> product(
    int n,
    ReceiptBranch branch, {
    String? key = 'Exact product',
    int size = 500,
    RevisionId? head,
  }) async {
    final d = ProductDocument(
      product: ProductSnapshot(
        id: id(n),
        storeId: branch.id,
        canonicalName: 'SAME NAME',
        comparisonKey: key,
        packageValue: BigInt.from(size),
        packageScale: 3,
        packageUnit: QuantityUnit.kg,
      ),
      storeRevision: branch.revision!,
      expectedHead: head,
      reviewedAtMs: BigInt.one,
      appVersion: 'compare-test',
    );
    await h.repository.saveProduct(d, mutationId: DurableId.generate());
    return (await h.repository.readProduct(id(n)))!;
  }

  Future<StoredReceipt> save(
    int n,
    StoredProduct p, {
    String date = '16.11.2026',
    int cents = 300,
  }) async {
    final r = ReceiptItemSnapshot(
      id: id(n + 1),
      name: 'PRINTED',
      kind: LineKind.product,
      cents: BigInt.from(cents),
      quantityValue: BigInt.two,
      quantityScale: 0,
      quantityUnit: QuantityUnit.piece,
      rateMicros: BigInt.from(cents * 5000),
      product: p.link,
    );
    final snap = snapshot(
      number: n,
      date: date,
      branch: branches.firstWhere((b) => b.id == p.document.product.storeId),
      items: [r],
      total: BigInt.from(cents),
    );
    await h.repository.saveManual(command(snap, mutation: n + 2));
    return (await h.repository.read(snap.id))!;
  }

  test('current explicit membership, historical pack sizes, full scans and backup6 round-trip', () async {
    final a = await product(100, branches[0]),
        b = await product(200, branches[1]);
    final unrelated = await product(300, branches[1], key: null);
    for (var i = 0; i < 35; i++) {
      await save(1000 + i * 10, a);
    }
    await save(2000, b, cents: 500);
    await save(2010, unrelated, cents: 99999);
    final bytes = await h.repository.exportBackup();
    expect(jsonDecode(utf8.decode(bytes))['format_version'], '6');
    var data = await h.repository.productComparison(a.document.product.id);
    expect(data.members, hasLength(2));
    expect(data.summary.totalRows, 36);
    expect(data.summary.series.map((g) => g.weightedMean.euros), [
      '3,0000',
      '5,0000',
    ]);
    expect(await h.repository.exportBackup(), bytes);
    await product(100, branches[0], size: 1000, head: a.revision);
    data = await h.repository.productComparison(a.document.product.id);
    expect(data.summary.series.first.weightedMean.euros, '3,0000');
    await h.reopen();
    expect(
      (await h.repository.productComparison(a.document.product.id)).members,
      hasLength(2),
    );
    final restored = await ReceiptRepository.restoreBackup(
      bytes,
      stagingParent: h.directory,
    );
    final repo = await ReceiptRepository.open(restored.databaseFile);
    try {
      expect(await repo.exportBackup(), bytes);
      expect(
        (await repo.productComparison(a.document.product.id)).summary.totalRows,
        36,
      );
    } finally {
      await repo.close();
    }
  });
  test(
    'range bounds, regrouping, clearing and receipts remain independent',
    () async {
      final a = await product(100, branches[0]),
          b = await product(200, branches[1]);
      final receipt = await save(1000, a, date: '16.11.2026 23:59:59');
      await save(1100, b, date: '17.11.2026');
      final canonical = ReceiptDocumentCodec.encode(receipt.document);
      final ranged = await h.repository.productComparison(
        a.document.product.id,
        range: PurchaseDateRange(
          fromDate: StoredReceiptDate.parse('16.11.2026'),
          throughDate: StoredReceiptDate.parse('16.11.2026'),
        ),
      );
      expect(ranged.summary.totalRows, 1);
      await product(200, branches[1], key: 'Other group', head: b.revision);
      expect(
        (await h.repository.productComparison(a.document.product.id)).members,
        hasLength(1),
      );
      await product(100, branches[0], key: null, head: a.revision);
      final cleared = await h.repository.productComparison(
        a.document.product.id,
      );
      expect(cleared.anchor.document.product.comparisonKey, isNull);
      expect(cleared.summary.series, isEmpty);
      expect(
        ReceiptDocumentCodec.encode(
          (await h.repository.read(receipt.document.snapshot.id))!.document,
        ),
        canonical,
      );
    },
  );
  test(
    'complete membership across catalog batches refuses more than 64 products',
    () async {
      for (var i = 0; i < 65; i++) {
        await product(100 + i, branches[0]);
      }
      await expectLater(
        h.repository.productComparison(id(100)),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.code,
            'code',
            'comparisonGroupLimit',
          ),
        ),
      );
    },
  );
}
