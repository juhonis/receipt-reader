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
  late ReceiptBranch branch;
  setUp(() async {
    h = await Harness.create();
    await h.repository.saveManual(command(snapshot()));
    branch = (await h.repository.branches()).single;
  });
  tearDown(() => h.dispose());
  ProductDocument product({String? category, RevisionId? head}) =>
      ProductDocument(
        product: ProductSnapshot(
          id: id(10),
          storeId: branch.id,
          canonicalName: 'TEST',
          category: category,
        ),
        storeRevision: branch.revision!,
        expectedHead: head,
        reviewedAtMs: BigInt.from(2000),
        appVersion: 'category-test',
      );
  SpendingDashboardQuery query() => SpendingDashboardQuery(
    unit: SpendingPeriodUnit.month,
    anchor: StoredReceiptDate.parse('18.11.2026'),
    today: StoredReceiptDate.parse('18.11.2026'),
  );
  Future<StoredReceipt> saveLinked(
    int n,
    StoredProduct product, {
    String date = '18.11.2026',
  }) async {
    final item = ReceiptItemSnapshot(
      id: id(1001 + n * 10),
      name: 'TEST',
      kind: LineKind.product,
      cents: BigInt.from(200),
      product: product.link,
    );
    final value = snapshot(
      number: 1000 + n * 10,
      branch: branch,
      date: date,
      items: [item],
    );
    await h.repository.saveManual(command(value, mutation: 1002 + n * 10));
    return (await h.repository.read(value.id))!;
  }

  test('category edit regroups earlier links, preserves receipt bytes, retries and reopen', () async {
    final initial = await h.repository.saveProduct(
      product(),
      mutationId: id(11),
    );
    final linked = await saveLinked(
      1,
      (await h.repository.products(branch.id)).single,
    );
    final text = ReceiptDocumentCodec.encode(linked.document);
    final doc = product(category: 'Ruoka ja juoma', head: initial.revision);
    final result = await h.repository.saveProduct(doc, mutationId: id(12));
    expect(
      (await h.repository.spendingDashboard(query()))
          .categories
          .categorizedProductRows,
      1,
    );
    expect(
      (await h.repository.history(
        filter: HistoryFilter(
          category: ReceiptCategory.product('Ruoka ja juoma'),
        ),
      )).single.document.snapshot.id,
      linked.document.snapshot.id,
    );
    expect(
      (await h.repository.spendingSummary(
        filter: HistoryFilter(
          category: ReceiptCategory.product('Ruoka ja juoma'),
        ),
      )).totals.totalCents,
      linked.document.snapshot.totalCents,
    );
    expect(
      ReceiptDocumentCodec.encode(
        (await h.repository.read(linked.document.snapshot.id))!.document,
      ),
      text,
    );
    expect(
      (await h.repository.saveProduct(doc, mutationId: id(12))).revision,
      result.revision,
    );
    await h.reopen();
    expect(
      (await h.repository.readProduct(id(10)))!.document.product.category,
      'Ruoka ja juoma',
    );
    final changed = await h.repository.saveProduct(
      product(category: 'Oma luokka', head: result.revision),
      mutationId: id(13),
    );
    expect(
      await h.repository.history(
        filter: HistoryFilter(
          category: ReceiptCategory.product('Ruoka ja juoma'),
        ),
      ),
      isEmpty,
    );
    expect(
      (await h.repository.history(
        filter: HistoryFilter(category: ReceiptCategory.product('Oma luokka')),
      )).single.document.snapshot.id,
      linked.document.snapshot.id,
    );
    await h.repository.saveProduct(
      product(head: changed.revision),
      mutationId: id(14),
    );
    expect(
      (await h.repository.readProduct(id(10)))!.document.product.category,
      isNull,
    );
    expect(
      jsonDecode(
        utf8.decode(await h.repository.exportBackup()),
      )['format_version'],
      '4',
    );
  });
  test('category history filters before pagination across batches and date precision', () async {
    await h.repository.saveProduct(
      product(category: 'TEST'),
      mutationId: id(11),
    );
    final p = (await h.repository.products(branch.id)).single;
    for (var i = 0; i < 75; i++) {
      await saveLinked(
        i,
        p,
        date: i % 2 == 0 ? '18.11.2026' : '18.11.2026 12:00:00',
      );
    }
    final filter = HistoryFilter(
      category: ReceiptCategory.product('TEST'),
      fromDate: StoredReceiptDate.parse('18.11.2026'),
      throughDate: StoredReceiptDate.parse('18.11.2026'),
    );
    final first = await h.repository.history(limit: 30, filter: filter);
    final second = await h.repository.history(
      limit: 30,
      offset: 30,
      filter: filter,
    );
    final third = await h.repository.history(
      limit: 30,
      offset: 60,
      filter: filter,
    );
    expect((first.length, second.length, third.length), (30, 30, 15));
    expect(
      {
        ...first,
        ...second,
        ...third,
      }.map((r) => r.document.snapshot.id).toSet(),
      hasLength(75),
    );
    expect(
      (await h.repository.spendingDashboard(query()))
          .categories
          .categorizedProductRows,
      75,
    );
    expect(
      await h.repository.history(
        filter: HistoryFilter(category: ReceiptCategory.product('OTHER')),
      ),
      isEmpty,
    );
  });
  test(
    'inner backup v4 restores categories, earlier links and later clearing',
    () async {
      final saved = await h.repository.saveProduct(
        product(category: 'Ruoka ja juoma'),
        mutationId: id(11),
      );
      await saveLinked(1, (await h.repository.products(branch.id)).single);
      final bytes = await h.repository.exportBackup();
      expect(jsonDecode(utf8.decode(bytes))['format_version'], '4');
      final restored = await ReceiptRepository.restoreBackup(
        bytes,
        stagingParent: h.directory,
      );
      final repo = await ReceiptRepository.open(restored.databaseFile);
      try {
        expect(
          (await repo.readProduct(id(10)))!.document.product.category,
          'Ruoka ja juoma',
        );
        expect(
          (await repo.spendingDashboard(query()))
              .categories
              .categorizedProductRows,
          1,
        );
        await repo.saveProduct(
          product(head: saved.revision),
          mutationId: id(12),
        );
        expect(
          jsonDecode(utf8.decode(await repo.exportBackup()))['format_version'],
          '4',
        );
        expect(
          (await repo.spendingDashboard(query()))
              .categories
              .categorizedProductRows,
          0,
        );
        final downgraded =
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        downgraded['format_version'] = '3';
        await expectLater(
          ReceiptRepository.restoreBackup(
            utf8.encode(jsonEncode(downgraded)),
            stagingParent: h.directory,
          ),
          throwsA(isA<StorageFailure>()),
        );
      } finally {
        await repo.close();
      }
    },
  );
}
