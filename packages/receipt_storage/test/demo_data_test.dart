import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:test/test.dart';
import 'package:receipt_storage/receipt_storage.dart';

import '../../../tools/demo_receipts/demo_data.dart';
import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  final anchor = StoredReceiptDate.parse('24.11.2026');
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());
  test('adds ten linked synthetic receipts, preserves existing data and repeats without writes', () async {
    await h.repository.saveManual(command(snapshot()));
    final original = (await h.repository.read(id(1)))!;
    final bytes = ReceiptDocumentCodec.encode(original.document);
    final result = await loadDemoReceipts(h.repository, anchor);
    expect(result.createdReceipts, 10);
    expect(result.linkedReceipts, 10);
    expect(result.createdProducts, greaterThan(15));
    expect(result.weekCents, BigInt.from(4159));
    expect(result.monthCents, BigInt.from(12688));
    expect(result.yearCents, BigInt.from(18744));
    expect((await h.repository.history(limit: 100)).length, 11);
    expect(
      ReceiptDocumentCodec.encode((await h.repository.read(id(1)))!.document),
      bytes,
    );
    for (var i = 0; i < 10; i++) {
      final saved = (await h.repository.read(demoDataId(200 + i)))!;
      expect(saved.document.review.appVersion, demoDataVersion);
      expect(saved.document.review.source, 'manual');
      expect(
        saved.document.snapshot.items.where((row) => row.product != null),
        isNotEmpty,
      );
    }
    final all = await h.repository.spendingDashboard(
      SpendingDashboardQuery(
        unit: SpendingPeriodUnit.month,
        anchor: anchor,
        today: anchor,
      ),
    );
    expect(all.selected.totalCents, result.monthCents + BigInt.from(200));
    expect(
      all.categories.groups.where((g) => g.category.name != null).length,
      5,
    );
    final beforeRetry = await h.repository.exportBackup();
    final retry = await loadDemoReceipts(h.repository, anchor);
    expect(retry.createdReceipts, 0);
    expect(retry.createdProducts, 0);
    expect(retry.linkedReceipts, 0);
    expect(await h.repository.exportBackup(), beforeRetry);
  });
  test('reserved branch collision fails before any write', () async {
    await h.repository.saveManual(
      command(
        snapshot(
          branch: ReceiptBranch(id: demoDataId(100), name: 'USER BRANCH'),
        ),
      ),
    );
    final before = await h.repository.exportBackup();
    await expectLater(loadDemoReceipts(h.repository, anchor), throwsStateError);
    expect(await h.repository.exportBackup(), before);
  });
  test('edited demo catalog records are preserved rather than reset', () async {
    await loadDemoReceipts(h.repository, anchor);
    final product = (await h.repository.readProduct(demoDataId(1000)))!;
    await h.repository.saveProduct(
      ProductDocument(
        product: ProductSnapshot(
          id: product.link.id,
          storeId: product.link.storeId,
          canonicalName: 'USER EDIT',
        ),
        storeRevision: product.document.storeRevision,
        expectedHead: product.revision,
        reviewedAtMs: BigInt.from(1),
        appVersion: 'normal-app',
      ),
      mutationId: id(90000),
    );
    final before = await h.repository.exportBackup();
    await expectLater(loadDemoReceipts(h.repository, anchor), throwsStateError);
    expect(await h.repository.exportBackup(), before);
  });
  test('deleted demo receipts are not resurrected and another anchor cannot overwrite the sample', () async {
    await loadDemoReceipts(h.repository, anchor);
    final before = await h.repository.exportBackup();
    await expectLater(
      loadDemoReceipts(h.repository, StoredReceiptDate.parse('25.11.2026')),
      throwsStateError,
    );
    expect(await h.repository.exportBackup(), before);
    final receipt = (await h.repository.read(demoDataId(200)))!;
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: receipt.document,
        expectedHead: receipt.revision,
        mutationId: id(90001),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(2), appVersion: 'normal-app'),
    );
    final deleted = await h.repository.exportBackup();
    await expectLater(loadDemoReceipts(h.repository, anchor), throwsStateError);
    expect(await h.repository.exportBackup(), deleted);
  });
}
