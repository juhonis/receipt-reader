import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'catalog_support.dart';
import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test('literal partial words ignore case and preserve Finnish letters and punctuation', () {
    expect(
      TextSearchQuery('  ÄITI\tLEIP ').matches(['Äitien', 'ruisleipä']),
      isTrue,
    );
    expect(TextSearchQuery('aiti').matches(['äiti']), isFalse);
    expect(TextSearchQuery('%_').matches(['ordinary text']), isFalse);
    expect(TextSearchQuery('%_').matches(['Literal %_ text']), isTrue);
    expect(TextSearchQuery("' OR 1=1").matches(['ordinary text']), isFalse);
    expect(TextSearchQuery(' \n ').matches([]), isTrue);
    expect(HistoryFilter(query: '  ').isEmpty, isTrue);
    expect(HistoryFilter(query: 'milk').isEmpty, isFalse);
  });

  test('receipt search combines filters before keyset paging, excludes deleted and follows corrections', () async {
    ReceiptBranch? branch;
    // Cross the 64-row scan boundary. Equal timestamps exercise ID tie-breaking.
    for (var i = 0; i < 68; i++) {
      final n = 1000 + i * 10;
      await h.repository.saveManual(
        command(
          snapshot(
            number: n,
            branch: branch ?? ReceiptBranch(id: id(2), name: 'ÄITI MARKET'),
            date: '16.11.2026 12:34',
            items: [
              row(
                number: n + 1,
                name: i < 64 ? 'OTHER ITEM' : 'Ruisleipä 100%_',
              ),
            ],
          ),
          mutation: n + 2,
        ),
      );
      branch ??= (await h.repository.branches()).single;
    }
    final beforeIdentity = await h.repository.identity();
    final filter = HistoryFilter(
      query: ' äiti LEIPÄ %_',
      branchId: branch!.id,
      fromDate: StoredReceiptDate.parse('16.11.2026'),
      throughDate: StoredReceiptDate.parse('16.11.2026'),
      minTotalCents: BigInt.from(200),
      maxTotalCents: BigInt.from(200),
      category: const ReceiptCategory.uncategorized(),
    );
    final first = await h.repository.history(filter: filter, limit: 2);
    final second = await h.repository.history(
      filter: filter,
      limit: 2,
      offset: 2,
    );
    expect([...first, ...second].map((r) => r.document.snapshot.id), [
      id(1640),
      id(1650),
      id(1660),
      id(1670),
    ]);
    expect(
      (await h.repository.history(filter: filter, limit: 2, offset: 4)),
      isEmpty,
    );
    expect(
      (await h.repository.spendingSummary(filter: filter)).totals.receiptCount,
      4,
    );
    expect(
      (await h.repository.identity()).nextLocalSequence,
      beforeIdentity.nextLocalSequence,
    );
    final old = first.first;
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: old.document,
        expectedHead: old.revision,
        mutationId: id(9000),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(5000), appVersion: 'search-test'),
    );
    final corrected = first.last;
    await h.repository.saveManual(
      command(
        snapshot(
          number: 1650,
          branch: branch,
          date: '16.11.2026 12:34',
          items: [row(number: 1651, name: 'CORRECTED ITEM')],
        ),
        mutation: 9001,
        heads: [corrected.revision],
      ),
    );
    await h.reopen();
    expect(
      (await h.repository.history(filter: filter))
          .map((r) => r.document.snapshot.id),
      [id(1660), id(1670)],
    );
    expect(
      (await h.repository.history(filter: filter.withQuery('corrected')))
          .single
          .document
          .snapshot
          .id,
      id(1650),
    );
    expect(
      await h.repository.history(filter: filter.withQuery('missing')),
      isEmpty,
    );
    expect(
      (await h.repository.history(filter: filter.withQuery(''))).length,
      30,
    );
    await h.repository.verifyIntegrity();
  });

  test('product and alias search page matches, preserve identities and branch ownership, and follow alias activation', () async {
    await h.repository.saveManual(command(snapshot()));
    final branch = (await h.repository.branches()).single;
    for (var i = 0; i < 66; i++) {
      final n = 1000 + i * 10;
      await h.repository.saveProduct(
        productDocument(
          branch,
          number: n,
          name: i < 64 ? 'AAA $i' : 'ÄITI LEIPÄ',
        ),
        mutationId: id(n + 1),
      );
    }
    final target = (await h.repository.products(
      branch.id,
      query: 'LEIPÄ',
      limit: 1,
    )).single;
    final alias = aliasDocument(
      branch,
      target.revision,
      number: 8000,
      product: 1640,
      name: 'ruis 100%_',
      active: true,
    );
    final savedAlias = await h.repository.saveAlias(
      alias,
      mutationId: id(8001),
    );
    expect(
      (await h.repository.products(
        branch.id,
        query: 'leipä',
        offset: 1,
      )).single.document.product.id,
      id(1650),
    );
    expect(
      (await h.repository.products(
        branch.id,
        query: 'äiti RUIS %_',
      )).single.document.product.id,
      id(1640),
    );
    expect(await h.repository.products(branch.id, query: 'aiti'), isEmpty);
    expect(await h.repository.products(id(9999), query: 'ruis'), isEmpty);
    expect(
      (await h.repository.aliases(
        branch.id,
        query: 'RUIS %_',
      )).single.document.alias.id,
      id(8000),
    );
    await h.repository.saveAlias(
      aliasDocument(
        branch,
        target.revision,
        number: 8000,
        product: 1640,
        name: 'ruis 100%_',
        active: false,
        head: savedAlias.revision,
      ),
      mutationId: id(8002),
    );
    await h.reopen();
    expect(await h.repository.products(branch.id, query: 'ruis'), isEmpty);
    expect(await h.repository.aliases(branch.id, query: 'ruis'), isEmpty);
    expect(
      (await h.repository.aliases(
        branch.id,
        query: 'ruis',
        activeOnly: false,
      )).length,
      1,
    );
    expect((await h.repository.products(branch.id, query: '  ')).length, 66);
    await h.repository.verifyIntegrity();
  });
}
