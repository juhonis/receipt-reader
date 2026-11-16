import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test(
    'filter bounds reject times, inverted ranges and out-of-range cents',
    () {
      for (final date in ['16.11.2026 12:34', '16.11.2026 12:34:56']) {
        expect(
          () => HistoryFilter(fromDate: StoredReceiptDate.parse(date)),
          throwsArgumentError,
        );
        expect(
          () => HistoryFilter(throughDate: StoredReceiptDate.parse(date)),
          throwsArgumentError,
        );
      }
      expect(
        () => HistoryFilter(
          fromDate: StoredReceiptDate.parse('1.12.2026'),
          throughDate: StoredReceiptDate.parse('30.11.2026'),
        ),
        throwsArgumentError,
      );
      expect(
        () => HistoryFilter(
          minTotalCents: BigInt.one,
          maxTotalCents: BigInt.zero,
        ),
        throwsArgumentError,
      );
      for (final amount in [
        sqliteInt64Min - BigInt.one,
        sqliteInt64Max + BigInt.one,
      ]) {
        expect(
          () => HistoryFilter(minTotalCents: amount),
          throwsA(isA<ReceiptDataException>()),
        );
        expect(
          () => HistoryFilter(maxTotalCents: amount),
          throwsA(isA<ReceiptDataException>()),
        );
      }
      expect(HistoryFilter().isEmpty, isTrue);
      expect(HistoryFilter(minTotalCents: BigInt.zero).isEmpty, isFalse);
    },
  );

  test(
    'filters combine before paging with inclusive civil days and exact cents',
    () async {
      ReceiptBranch? a, b;
      // Duplicate display names are deliberately distinct durable branches.
      for (final entry in [
        (10, '15.11.2026 23:59:59', BigInt.from(100), false),
        (20, '16.11.2026', sqliteInt64Min, false),
        (30, '16.11.2026 00:00', BigInt.from(-50), false),
        (40, '16.11.2026 23:59:59', BigInt.zero, false),
        (50, '17.11.2026', BigInt.from(100), false),
        (60, '17.11.2026 23:59:59', sqliteInt64Max, false),
        (70, '18.11.2026', BigInt.from(100), false),
        (80, '16.11.2026 12:00', BigInt.from(-50), true),
      ]) {
        final branch = entry.$4
            ? b ?? ReceiptBranch(id: id(5), name: 'TEST BRANCH')
            : a ?? ReceiptBranch(id: id(2), name: 'TEST BRANCH');
        await h.repository.saveManual(
          command(
            snapshot(
              number: entry.$1,
              branch: branch,
              date: entry.$2,
              total: entry.$3,
              items: [row(number: entry.$1 + 1, cents: entry.$3)],
            ),
            mutation: entry.$1 + 2,
          ),
        );
        final branches = await h.repository.branches();
        a = branches.where((r) => r.id == id(2)).single;
        b = branches.where((r) => r.id == id(5)).firstOrNull;
      }
      await h.reopen();
      final identity = await h.repository.identity();
      final events = h.count('change_log');
      final unfiltered = await h.repository.history();
      Future<List<DurableId>> ids(
        HistoryFilter filter, {
        int limit = 30,
        int offset = 0,
      }) async => (await h.repository.history(
        filter: filter,
        limit: limit,
        offset: offset,
      )).map((r) => r.document.snapshot.id).toList();
      final from = StoredReceiptDate.parse('16.11.2026');
      final through = StoredReceiptDate.parse('17.11.2026');
      expect(await ids(HistoryFilter(fromDate: from, throughDate: from)), [
        id(40),
        id(80),
        id(30),
        id(20),
      ]);
      expect(await ids(HistoryFilter(fromDate: from, throughDate: through)), [
        id(60),
        id(50),
        id(40),
        id(80),
        id(30),
        id(20),
      ]);
      expect(await ids(HistoryFilter(throughDate: from)), [
        id(40),
        id(80),
        id(30),
        id(20),
        id(10),
      ]);
      expect(await ids(HistoryFilter(fromDate: through)), [
        id(70),
        id(60),
        id(50),
      ]);
      expect(await ids(HistoryFilter(branchId: b!.id)), [id(80)]);
      expect(await ids(HistoryFilter(branchId: id(999))), isEmpty);
      expect(
        await ids(
          HistoryFilter(
            minTotalCents: BigInt.from(-50),
            maxTotalCents: BigInt.zero,
          ),
        ),
        [id(40), id(80), id(30)],
      );
      expect(
        await ids(
          HistoryFilter(
            minTotalCents: sqliteInt64Max,
            maxTotalCents: sqliteInt64Max,
          ),
        ),
        [id(60)],
      );
      expect(
        await ids(
          HistoryFilter(
            minTotalCents: sqliteInt64Min,
            maxTotalCents: sqliteInt64Min,
          ),
        ),
        [id(20)],
      );
      expect(await ids(HistoryFilter(maxTotalCents: BigInt.from(-51))), [
        id(20),
      ]);
      expect(await ids(HistoryFilter(minTotalCents: BigInt.from(101))), [
        id(60),
      ]);
      final combined = HistoryFilter(
        branchId: a!.id,
        fromDate: from,
        throughDate: through,
        minTotalCents: BigInt.from(-50),
        maxTotalCents: BigInt.from(100),
      );
      expect(await ids(combined, limit: 2), [id(50), id(40)]);
      expect(await ids(combined, limit: 2, offset: 2), [id(30)]);
      expect(await ids(combined, offset: 3), isEmpty);
      expect(
        await ids(HistoryFilter()),
        unfiltered.map((r) => r.document.snapshot.id),
      );
      expect(h.count('change_log'), events);
      expect(
        (await h.repository.identity()).nextLocalSequence,
        identity.nextLocalSequence,
      );
      expect(
        (await h.repository.history()).map((r) => r.document.sha256Hex),
        unfiltered.map((r) => r.document.sha256Hex),
      );
      await h.repository.verifyIntegrity();
      // Filtering does not bypass projection/canonical validation of returned rows.
      h.raw.execute(
        'UPDATE receipts SET total_amount_cents = -49 WHERE id = ?',
        [id(30).value],
      );
      await expectLater(
        h.repository.history(filter: combined),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.code,
            'code',
            'receiptProjection',
          ),
        ),
      );
    },
  );

  test(
    'whole day filters include both sides of Helsinki daylight-saving changes',
    () async {
      ReceiptBranch? branch;
      for (final entry in [
        (10, '29.3.2026'),
        (20, '29.3.2026 00:00'),
        (30, '29.3.2026 23:59:59'),
        (40, '30.3.2026 00:00'),
        (50, '25.10.2026 00:00'),
        (60, '25.10.2026 23:59:59'),
      ]) {
        await h.repository.saveManual(
          command(
            snapshot(
              number: entry.$1,
              date: entry.$2,
              branch: branch,
              items: [row(number: entry.$1 + 1)],
            ),
            mutation: entry.$1 + 2,
          ),
        );
        branch = (await h.repository.branches()).single;
      }
      for (final entry in [
        ('29.3.2026', [id(30), id(20), id(10)]),
        ('25.10.2026', [id(60), id(50)]),
      ]) {
        final date = StoredReceiptDate.parse(entry.$1);
        expect(
          (await h.repository.history(
            filter: HistoryFilter(fromDate: date, throughDate: date),
          )).map((r) => r.document.snapshot.id),
          entry.$2,
        );
      }
    },
  );
}
