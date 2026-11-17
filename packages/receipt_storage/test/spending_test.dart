import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
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
  Future<StoredReceipt> save(
    int n, {
    int cents = 200,
    String date = '17.11.2026',
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
    'all pages, signed totals, monthly/branch separation and no writes',
    () async {
      for (var n = 0; n < 35; n++) {
        await save(n);
      }
      final first = (await h.repository.branches()).single;
      await save(40, cents: -50, date: '31.10.2026 23:59:59', branch: first);
      await save(
        41,
        cents: 0,
        date: '1.12.2026',
        branch: ReceiptBranch(id: id(99), name: first.name),
      );
      final before = await h.repository.exportBackup();
      final result = await h.repository.spendingSummary();
      expect(result.totals.receiptCount, 37);
      expect(result.totals.totalCents, BigInt.from(6950));
      expect(result.totals.negativeReceipts, 1);
      expect(result.totals.unlinkedReceipts, 37);
      expect(result.branches, hasLength(2));
      expect(result.months.map((m) => (m.year, m.month)), [
        (2026, 12),
        (2026, 11),
        (2026, 10),
      ]);
      expect(result.months.map((m) => m.totals.totalCents), [
        BigInt.zero,
        BigInt.from(7000),
        BigInt.from(-50),
      ]);
      expect(await h.repository.exportBackup(), before);
      final selected = await h.repository.spendingSummary(
        filter: HistoryFilter(
          branchId: first.id,
          fromDate: StoredReceiptDate.parse('31.10.2026'),
          throughDate: StoredReceiptDate.parse('31.10.2026'),
        ),
      );
      expect(selected.totals.receiptCount, 1);
      expect(selected.totals.totalCents, BigInt.from(-50));
      expect(
        (await h.repository.spendingSummary(
          filter: HistoryFilter(branchId: id(999)),
        )).totals.receiptCount,
        0,
      );
      expect(
        (await h.repository.spendingSummary(
          filter: HistoryFilter(fromDate: StoredReceiptDate.parse('1.12.2026')),
        )).totals.receiptCount,
        1,
      );
      expect(
        (await h.repository.spendingSummary(
          filter: HistoryFilter(maxTotalCents: BigInt.from(-1)),
        )).totals.receiptCount,
        1,
      );
    },
  );
  test(
    'correction replaces, deletion removes and reopen preserves totals',
    () async {
      final original = await save(1);
      final changed = snapshot(
        number: 1010,
        branch: (await h.repository.branches()).single,
        date: '1.1.2027',
        items: [row(number: 1011, cents: BigInt.from(-150))],
        total: BigInt.from(-150),
      );
      await h.repository.saveManual(
        command(changed, mutation: 500, heads: [original.revision]),
      );
      await h.reopen();
      final summary = await h.repository.spendingSummary();
      expect(summary.totals.receiptCount, 1);
      expect(summary.totals.totalCents, BigInt.from(-150));
      expect(summary.months.single.year, 2027);
      final saved = (await h.repository.read(changed.id))!;
      await h.repository.deleteReceipt(
        ReceiptDeletionChecks(
          document: saved.document,
          expectedHead: saved.revision,
          mutationId: id(501),
          receiptReviewed: true,
        ).confirm(deletedAtMs: BigInt.from(300), appVersion: 'spending-test'),
      );
      await h.reopen();
      final empty = await h.repository.spendingSummary();
      expect(empty.totals.receiptCount, 0);
      expect(empty.totals.totalCents, BigInt.zero);
      expect(empty.months, isEmpty);
      expect(empty.branches, isEmpty);
    },
  );
  test('exact sum beyond int64 and complete mixed rows counted once', () async {
    final maximum = sqliteInt64Max;
    for (var n = 0; n < 2; n++) {
      final s = snapshot(
        number: 200 + n,
        branch: (await h.repository.branches()).firstOrNull,
        items: [row(number: 300 + n, cents: maximum)],
        total: maximum,
      );
      await h.repository.saveManual(command(s, mutation: 400 + n));
    }
    final product = row(number: 600, cents: BigInt.from(1000));
    final rows = [
      product,
      row(
        number: 601,
        cents: BigInt.from(-100),
        kind: LineKind.discount,
        scope: DiscountScope.receipt,
      ),
      row(
        number: 602,
        cents: BigInt.from(40),
        kind: LineKind.deposit,
        parent: product.id,
      ),
      row(number: 603, cents: BigInt.from(-200)),
      ReceiptItemSnapshot(
        id: id(604),
        name: 'Reviewed',
        kind: LineKind.adjustment,
        cents: BigInt.from(10),
        adjustmentReason: 'checked rounding',
      ),
    ];
    final s = snapshot(
      number: 605,
      branch: (await h.repository.branches()).single,
      items: rows,
      total: BigInt.from(750),
    );
    await h.repository.saveManual(command(s, mutation: 606));
    final summary = await h.repository.spendingSummary();
    expect(summary.totals.totalCents, maximum * BigInt.two + BigInt.from(750));
    expect(summary.totals.receiptCount, 3);
    expect(summary.totals.negativeReceipts, 0);
    expect(summary.totals.adjustedReceipts, 1);
    expect(summary.months.single.totals.totalCents, summary.totals.totalCents);
  });
  test('integrity failure never becomes a partial total', () async {
    await save(1);
    await save(2);
    h.raw.execute('UPDATE receipts SET total_amount_cents = 99 WHERE id = ?', [
      id(1020).value,
    ]);
    await expectLater(
      h.repository.spendingSummary(),
      throwsA(isA<StorageFailure>()),
    );
  });
  test('branch bound fails the whole result; a filter can recover', () async {
    for (var n = 0; n < 129; n++) {
      await save(
        n,
        branch: ReceiptBranch(id: id(10000 + n), name: 'BRANCH'),
      );
    }
    await expectLater(
      h.repository.spendingSummary(),
      throwsA(
        isA<StorageFailure>().having(
          (e) => e.code,
          'code',
          'spendingGroupLimit',
        ),
      ),
    );
    expect(
      (await h.repository.spendingSummary(
        filter: HistoryFilter(branchId: id(10000)),
      )).totals.receiptCount,
      1,
    );
  });
}
