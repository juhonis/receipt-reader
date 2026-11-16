import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import '../../receipt_domain/test/ocr_support.dart';
import 'support.dart';

Matcher fails(String code) =>
    throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));
ReviewedReceiptDeletion deletion(
  StoredReceipt receipt, {
  int mutation = 80,
  int at = 456,
}) => ReceiptDeletionChecks(
  document: receipt.document,
  expectedHead: receipt.revision,
  mutationId: id(mutation),
  receiptReviewed: true,
).confirm(deletedAtMs: BigInt.from(at), appVersion: 'storage-deletion-test');

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  for (final source in ['manual', 'ocr']) {
    test(
      '$source deletion preserves immutable history and ownership through reopening and retries',
      () async {
        final initial = source == 'manual'
            ? command(snapshot())
            : OcrFixture().save();
        final first = source == 'manual'
            ? await h.repository.saveManual(initial)
            : await h.repository.saveOcr(initial);
        final receipt = (await h.repository.history()).single;
        final eventsBefore = h.raw
            .select('SELECT * FROM change_log ORDER BY origin_seq')
            .map((r) => Map<String, Object?>.from(r))
            .toList();
        final delete = deletion(receipt);
        final result = await h.repository.deleteReceipt(delete);
        expect(result.replayed, isFalse);
        expect(h.count('receipts'), 1);
        expect(h.count('receipt_items'), 0);
        expect(h.count('receipt_reviews'), 0);
        expect(h.count('row_identities'), 1);
        expect(h.count('stores'), 1);
        expect(h.count('change_log'), 3);
        expect(
          h.raw
              .select('SELECT * FROM change_log ORDER BY origin_seq')
              .take(2)
              .map((r) => Map<String, Object?>.from(r)),
          eventsBefore,
        );
        final shell = h.raw.select('SELECT * FROM receipts').single;
        for (final field in [
          'store_id',
          'printed_year',
          'printed_month',
          'printed_day',
          'date_precision',
          'currency',
          'total_amount_cents',
          'reviewed_at_ms',
        ]) {
          expect(shell[field], isNull, reason: field);
        }
        expect(
          (await h.repository.readDeleted(receipt.document.snapshot.id))!
              .revision,
          result.revision,
        );
        expect(await h.repository.read(receipt.document.snapshot.id), isNull);
        expect(await h.repository.history(), isEmpty);
        await h.reopen();
        expect((await h.repository.deleteReceipt(delete)).replayed, isTrue);
        final replay = source == 'manual'
            ? await h.repository.saveManual(initial)
            : await h.repository.saveOcr(initial);
        expect(replay.revision, first.revision);
        expect(await h.repository.history(), isEmpty);
        expect(h.count('change_log'), 3);
        final branch = (await h.repository.branches()).single;
        await expectLater(
          h.repository.saveManual(
            command(
              snapshot(branch: branch),
              mutation: 90,
              heads: [result.revision],
            ),
          ),
          fails('receiptDeleted'),
        );
        await expectLater(
          h.repository.saveManual(
            command(snapshot(branch: branch), mutation: 91),
          ),
          fails('receiptDeleted'),
        );
        await expectLater(
          h.repository.saveManual(
            command(snapshot(number: 60, branch: branch), mutation: 92),
          ),
          fails('rowIdentityReused'),
        );
        await expectLater(
          h.repository.deleteReceipt(deletion(receipt, mutation: 93)),
          fails('staleReceipt'),
        );
        await h.repository.verifyIntegrity();
      },
    );
  }

  test('stale head or mismatched displayed document cannot delete a changed receipt', () async {
    await h.repository.saveManual(command(snapshot()));
    final prior = (await h.repository.history()).single;
    final branch = (await h.repository.branches()).single;
    final changed = command(
      snapshot(
        branch: branch,
        items: [row(name: 'CORRECTED')],
      ),
      mutation: 10,
      heads: [prior.revision],
    );
    await h.repository.saveManual(changed);
    await expectLater(
      h.repository.deleteReceipt(deletion(prior)),
      fails('staleReceipt'),
    );
    final current = (await h.repository.history()).single;
    final wrong = StoredReceipt(prior.document, current.revision);
    await expectLater(
      h.repository.deleteReceipt(deletion(wrong, mutation: 81)),
      fails('staleReceipt'),
    );
    expect(
      (await h.repository.history()).single.document.sha256Hex,
      changed.document.sha256Hex,
    );
    expect(h.count('change_log'), 3);
  });

  test(
    'mutation identities cannot be reused across saves or different deletions',
    () async {
      await h.repository.saveManual(command(snapshot()));
      final receipt = (await h.repository.history()).single;
      await expectLater(
        h.repository.deleteReceipt(deletion(receipt, mutation: 4)),
        fails('mutationIdentityReused'),
      );
      await h.repository.deleteReceipt(deletion(receipt));
      await expectLater(
        h.repository.deleteReceipt(deletion(receipt, at: 457)),
        fails('mutationIdentityReused'),
      );
      expect(h.count('change_log'), 3);
    },
  );

  test('deletion excludes rows before filtered pagination without removing other branch receipts', () async {
    await h.repository.saveManual(command(snapshot()));
    final branch = (await h.repository.branches()).single;
    for (var n = 10; n <= 12; n++) {
      await h.repository.saveManual(
        command(
          snapshot(
            number: n,
            branch: branch,
            items: [row(number: n + 10)],
          ),
          mutation: n + 30,
        ),
      );
    }
    final prior = (await h.repository.history()).first;
    await h.repository.deleteReceipt(deletion(prior));
    final filter = HistoryFilter(
      branchId: branch.id,
      minTotalCents: BigInt.from(200),
      fromDate: StoredReceiptDate.parse('16.11.2026'),
    );
    final first = await h.repository.history(filter: filter, limit: 2);
    final next = await h.repository.history(
      filter: filter,
      limit: 2,
      offset: 2,
    );
    expect(first, hasLength(2));
    expect(next, hasLength(1));
    expect(
      {...first, ...next}.map((r) => r.document.snapshot.id),
      isNot(contains(prior.document.snapshot.id)),
    );
    await h.reopen();
    expect(await h.repository.history(filter: filter), hasLength(3));
  });

  for (final point in [
    'UPDATE dataset_state',
    'INSERT ON change_log',
    'DELETE ON receipt_items',
    'DELETE ON receipt_reviews',
    'UPDATE receipts',
    'DELETE ON entity_heads',
    'UPDATE received_cursors',
    'INSERT ON local_mutations',
  ]) {
    test(
      'deletion rollback at $point preserves projection, identity and exact retry',
      () async {
        await h.repository.saveManual(command(snapshot()));
        final receipt = (await h.repository.history()).single;
        final delete = deletion(receipt);
        final statement = point.startsWith('UPDATE ')
            ? point.replaceFirst('UPDATE ', 'UPDATE ON ')
            : point;
        h.raw.execute(
          "CREATE TRIGGER synthetic_deletion BEFORE $statement BEGIN SELECT RAISE(ABORT, 'synthetic deletion failure'); END",
        );
        await expectLater(
          h.repository.deleteReceipt(delete),
          fails('constraint'),
        );
        expect(h.count('change_log'), 2);
        expect(h.count('local_mutations'), 1);
        expect(h.count('receipt_items'), 1);
        expect(h.count('receipt_reviews'), 1);
        expect(
          (await h.repository.read(receipt.document.snapshot.id))!
              .document
              .sha256Hex,
          receipt.document.sha256Hex,
        );
        await h.repository.verifyIntegrity();
        h.raw.execute('DROP TRIGGER synthetic_deletion');
        await h.repository.deleteReceipt(delete);
        await h.reopen();
        expect((await h.repository.deleteReceipt(delete)).replayed, isTrue);
        expect(h.count('change_log'), 3);
      },
    );
  }

  test('integrity rejects live review children attached to a deleted shell', () async {
    await h.repository.saveManual(command(snapshot()));
    final receipt = (await h.repository.history()).single;
    final review = Map<String, Object?>.from(
      h.raw.select('SELECT * FROM receipt_reviews').single,
    );
    await h.repository.deleteReceipt(deletion(receipt));
    h.raw.execute(
      'INSERT INTO receipt_reviews (${review.keys.join(', ')}) VALUES (${List.filled(review.length, '?').join(', ')})',
      review.values.toList(),
    );
    await expectLater(
      h.repository.verifyIntegrity(),
      fails('tombstoneChildren'),
    );
    await h.closeConnection();
    await expectLater(
      ReceiptRepository.open(h.file),
      fails('tombstoneChildren'),
    );
  });
}
