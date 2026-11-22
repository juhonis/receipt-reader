import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async {
    h = await Harness.create();
  });
  tearDown(() => h.dispose());
  SpendingDashboardQuery query({DurableId? branch}) => SpendingDashboardQuery(
    unit: SpendingPeriodUnit.month,
    anchor: StoredReceiptDate.parse('18.11.2026'),
    today: StoredReceiptDate.parse('18.11.2026'),
    branchId: branch,
  );
  Future<StoredReceipt> save(
    int n,
    int cents,
    String date, {
    ReceiptBranch? branch,
  }) async {
    branch ??= (await h.repository.branches()).firstOrNull;
    final value = snapshot(
      number: 1000 + n * 10,
      branch: branch,
      date: date,
      items: [row(number: 1001 + n * 10, cents: BigInt.from(cents))],
      total: BigInt.from(cents),
    );
    await h.repository.saveManual(command(value, mutation: 1002 + n * 10));
    return (await h.repository.read(value.id))!;
  }

  test(
    'all batches, matched days, branch selection and read-only export',
    () async {
      for (var n = 0; n < 35; n++) {
        await save(n, 200, '18.11.2026 23:59:59');
      }
      final branch = (await h.repository.branches()).single;
      await save(40, 1000, '18.10.2026');
      await save(41, 999, '19.10.2026');
      await save(42, 999, '19.11.2026');
      await save(
        43,
        -50,
        '17.11.2026',
        branch: ReceiptBranch(id: id(99), name: branch.name),
      );
      final before = await h.repository.exportBackup();
      final result = await h.repository.spendingDashboard(query());
      expect(result.selected.receiptCount, 36);
      expect(result.selected.totalCents, BigInt.from(6950));
      expect(result.selected.negativeReceipts, 1);
      expect(result.comparisonPrevious.totalCents, BigInt.from(1000));
      expect(result.changeTenthsPercent, BigInt.from(5950));
      expect(
        result.periods[result.periods.length - 2].totals.totalCents,
        BigInt.from(1999),
      );
      final selected = await h.repository.spendingDashboard(
        query(branch: branch.id),
      );
      expect(selected.selected.receiptCount, 35);
      expect(selected.selected.totalCents, BigInt.from(7000));
      expect(await h.repository.exportBackup(), before);
    },
  );
  test(
    'correction, deletion and reopen update buckets and comparison',
    () async {
      final original = await save(1, 100, '18.11.2026');
      final changed = snapshot(
        number: 1010,
        branch: (await h.repository.branches()).single,
        date: '18.10.2026',
        items: [row(number: 1011, cents: BigInt.from(-50))],
        total: BigInt.from(-50),
      );
      await h.repository.saveManual(
        command(changed, mutation: 500, heads: [original.revision]),
      );
      await h.reopen();
      var data = await h.repository.spendingDashboard(query());
      expect(data.selected.receiptCount, 0);
      expect(data.comparisonPrevious.totalCents, BigInt.from(-50));
      final stored = (await h.repository.read(changed.id))!;
      await h.repository.deleteReceipt(
        ReceiptDeletionChecks(
          document: stored.document,
          expectedHead: stored.revision,
          mutationId: id(501),
          receiptReviewed: true,
        ).confirm(deletedAtMs: BigInt.from(300), appVersion: 'dashboard-test'),
      );
      await h.reopen();
      data = await h.repository.spendingDashboard(query());
      expect(data.periods.every((p) => p.totals.receiptCount == 0), isTrue);
    },
  );
  test('corrupt selected projection fails the whole dashboard', () async {
    final saved = await save(1, 100, '18.11.2026');
    h.raw.execute('UPDATE receipts SET total_amount_cents = 999 WHERE id = ?', [
      saved.document.snapshot.id.value,
    ]);
    await expectLater(
      h.repository.spendingDashboard(query()),
      throwsA(isA<StorageFailure>()),
    );
  });
}
