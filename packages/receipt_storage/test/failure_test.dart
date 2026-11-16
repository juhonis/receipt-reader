import 'package:drift/drift.dart';
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
    'database failures never expose bound names or SQL through the API',
    () async {
      h.raw.execute(
        "CREATE TRIGGER fail_private BEFORE INSERT ON receipt_items BEGIN SELECT RAISE(ABORT, 'PRIVATE RECEIPT NOTE'); END",
      );
      try {
        await h.repository.saveManual(
          command(snapshot(items: [row(name: 'PRIVATE PRODUCT')])),
        );
        fail('Expected failure');
      } on StorageFailure catch (error) {
        expect(error.code, 'constraint');
        expect(error.toString(), isNot(contains('PRIVATE')));
        expect(error.toString(), isNot(contains('INSERT')));
      }
      expect(h.count('change_log'), 0);
    },
  );

  for (final target in [
    ('UPDATE', 'dataset_state'),
    ('INSERT', 'change_log'),
    ('INSERT', 'stores'),
    ('INSERT', 'receipts'),
    ('INSERT', 'row_identities'),
    ('INSERT', 'receipt_items'),
    ('INSERT', 'receipt_reviews'),
    ('INSERT', 'entity_heads'),
    ('UPDATE', 'received_cursors'),
    ('INSERT', 'local_mutations'),
  ]) {
    test('rollback at ${target.$2} preserves identity, sequence and retryability', () async {
      final identity = await h.repository.identity();
      h.raw.execute(
        "CREATE TRIGGER fail_write BEFORE ${target.$1} ON ${target.$2} BEGIN SELECT RAISE(ABORT, 'synthetic_failure'); END",
      );
      final pending = command(snapshot());
      await expectLater(
        h.repository.saveManual(pending),
        throwsA(isA<StorageFailure>()),
      );
      expect(h.count('change_log'), 0);
      expect(h.count('stores'), 0);
      expect(h.count('receipts'), 0);
      expect(h.count('receipt_items'), 0);
      expect(h.count('receipt_reviews'), 0);
      expect(h.count('row_identities'), 0);
      expect(h.count('local_mutations'), 0);
      expect((await h.repository.identity()).nextLocalSequence, BigInt.one);
      expect(
        h.raw
            .select('SELECT committed_seq FROM received_cursors')
            .single['committed_seq'],
        0,
      );
      h.raw.execute('DROP TRIGGER fail_write');
      await h.reopen();
      expect((await h.repository.identity()).deviceId, identity.deviceId);
      final saved = await h.repository.saveManual(pending);
      expect(saved.revision.sequence, BigInt.two);
      expect(saved.replayed, isFalse);
      await h.repository.verifyIntegrity();
    });
  }

  for (final target in [
    ('DELETE', 'receipt_items'),
    ('UPDATE', 'receipts'),
    ('INSERT', 'receipt_items'),
    ('INSERT', 'receipt_reviews'),
    ('DELETE', 'entity_heads'),
  ]) {
    test(
      'failed edit at ${target.$1} ${target.$2} retains the entire prior revision',
      () async {
        final initial = command(snapshot());
        final first = await h.repository.saveManual(initial);
        final branch = (await h.repository.branches()).single;
        final pending = command(
          snapshot(
            branch: branch,
            items: [row(number: 5, name: 'Replacement')],
          ),
          mutation: 6,
          heads: [first.revision],
        );
        h.raw.execute(
          "CREATE TRIGGER fail_edit BEFORE ${target.$1} ON ${target.$2} BEGIN SELECT RAISE(ABORT, 'synthetic_failure'); END",
        );
        await expectLater(
          h.repository.saveManual(pending),
          throwsA(isA<StorageFailure>()),
        );
        h.raw.execute('DROP TRIGGER fail_edit');
        expect(h.count('change_log'), 2);
        expect(h.count('row_identities'), 1);
        expect(
          (await h.repository.read(id(1)))!.document.sha256Hex,
          initial.document.sha256Hex,
        );
        expect(
          (await h.repository.identity()).nextLocalSequence,
          BigInt.from(3),
        );
        await h.reopen();
        final saved = await h.repository.saveManual(pending);
        expect(saved.revision.sequence, BigInt.from(3));
        expect(h.count('receipt_items'), 1);
        expect(h.count('row_identities'), 2);
      },
    );
  }

  test(
    'actual SQLite FULL rolls back a large save without losing the review',
    () async {
      final pages =
          h.raw.select('PRAGMA page_count').single['page_count'] as int;
      await h.database.customStatement('PRAGMA max_page_count = $pages');
      final pending = command(snapshot(items: [row(name: 'A' * 200000)]));
      await expectLater(
        h.repository.saveManual(pending),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'storageFull'),
        ),
      );
      expect(h.count('change_log'), 0);
      expect(h.count('receipts'), 0);
      expect((await h.repository.identity()).nextLocalSequence, BigInt.one);
      await h.database.customStatement('PRAGMA max_page_count = 1073741823');
      final saved = await h.repository.saveManual(pending);
      expect(saved.revision.sequence, BigInt.two);
      await h.reopen();
      expect(
        (await h.repository.read(id(1)))!
            .document
            .snapshot
            .items
            .single
            .name
            .length,
        200000,
      );
    },
  );

  test(
    'sequence exhaustion stops before creating an event or wrapping',
    () async {
      h.raw.execute('UPDATE dataset_state SET next_local_seq = ?', [
        sqliteInt64Max.toInt(),
      ]);
      await expectLater(
        h.repository.saveManual(command(snapshot())),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.code,
            'code',
            'sequenceExhausted',
          ),
        ),
      );
      expect(h.count('change_log'), 0);
      h.raw.execute('UPDATE dataset_state SET next_local_seq = 1');
      await h.repository.verifyIntegrity();
    },
  );
}
