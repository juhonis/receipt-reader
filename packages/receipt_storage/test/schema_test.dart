import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_storage/src/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test(
    'a damaged event digest blocks reopen without resetting history',
    () async {
      await h.repository.saveManual(command(snapshot()));
      h.raw.execute('DROP TRIGGER change_log_no_update');
      h.raw.execute('UPDATE change_log SET event_sha256 = ?', ['0' * 64]);
      await expectLater(
        h.repository.verifyIntegrity(),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'eventDigest'),
        ),
      );
      await h.closeConnection();
      await expectLater(
        ReceiptRepository.open(h.file),
        throwsA(isA<StorageFailure>()),
      );
    },
  );

  test(
    'fresh schema matches the committed Drift version-eight snapshot',
    () async {
      final verifier = SchemaVerifier(
        GeneratedHelper(),
        setup: configureSqlite,
      );
      await verifier.migrateAndValidate(h.database, 8);
      await h.database.validateDatabaseSchema();
      final tables = h.raw.select(
        "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      final modes = {
        for (final row in h.raw.select('PRAGMA table_list'))
          row['name']: row['strict'],
      };
      for (final table in tables) {
        expect(modes[table['name']], 1, reason: table['name'] as String);
      }
      expect(h.raw.select('PRAGMA user_version').single['user_version'], 8);
    },
  );

  test(
    'SQL itself rejects invalid storage classes, dates, signs and references',
    () async {
      final first = await h.repository.saveManual(command(snapshot()));
      final badSql = <(String, List<Object?>)>[
        ('UPDATE dataset_state SET singleton = 2', []),
        ('UPDATE dataset_state SET device_id = ?', ['INVALID']),
        ('UPDATE dataset_state SET next_local_seq = 1.5', []),
        ('UPDATE receipts SET total_amount_cents = 2.5', []),
        ('UPDATE receipts SET total_amount_cents = ?', ['9223372036854775808']),
        ("UPDATE receipts SET currency = 'USD'", []),
        ('UPDATE receipts SET printed_month = 13', []),
        ('UPDATE receipts SET printed_day = 0', []),
        ('UPDATE receipts SET printed_hour = 0', []),
        ('UPDATE receipts SET store_id = ?', [id(99).value]),
        ('UPDATE receipt_items SET receipt_id = ?', [id(99).value]),
        ('UPDATE receipt_items SET parent_item_id = ?', [id(99).value]),
        ("UPDATE receipt_items SET kind = 'discount'", []),
        ("UPDATE receipt_items SET kind = 'adjustment'", []),
        ("UPDATE receipt_items SET discount_scope = 'receipt'", []),
        ('UPDATE receipt_items SET quantity_value = 1', []),
        ('UPDATE receipt_items SET product_id = ?', [id(99).value]),
        ("UPDATE receipt_reviews SET source = 'ocr'", []),
        ('UPDATE entity_heads SET origin_seq = 99', []),
        ("UPDATE change_log SET payload = '{}'", []),
        ('DELETE FROM change_log', []),
        ('DELETE FROM row_identities', []),
        ('DELETE FROM local_mutations', []),
      ];
      for (final (sql, args) in badSql) {
        expect(
          () => h.raw.execute(sql, args),
          throwsA(isA<sqlite.SqliteException>()),
          reason: sql,
        );
      }
      expect((await h.repository.read(id(1)))!.revision, first.revision);
      await h.repository.verifyIntegrity();
    },
  );

  for (final corruption in <String>[
    'UPDATE receipts SET total_amount_cents = 201',
    "UPDATE receipt_items SET name = 'OTHER'",
    'DELETE FROM entity_heads',
    'UPDATE received_cursors SET committed_seq = 0',
    'UPDATE dataset_state SET next_local_seq = 99',
    'DELETE FROM receipt_reviews',
  ]) {
    test(
      'open refuses inconsistent projections/history: $corruption',
      () async {
        await h.repository.saveManual(command(snapshot()));
        h.raw.execute(corruption);
        await expectLater(
          h.repository.verifyIntegrity(),
          throwsA(isA<StorageFailure>()),
        );
        await h.closeConnection();
        await expectLater(
          ReceiptRepository.open(h.file),
          throwsA(isA<StorageFailure>()),
        );
        final raw = sqlite.sqlite3.open(h.file.path);
        expect(
          raw
              .select('SELECT COUNT(*) AS count FROM change_log')
              .single['count'],
          2,
        );
        raw.close();
      },
    );
  }

  test(
    'a future schema is rejected without changing its data or version',
    () async {
      await h.repository.saveManual(command(snapshot()));
      await h.closeConnection();
      final raw = sqlite.sqlite3.open(h.file.path);
      raw.execute('PRAGMA user_version = 9');
      raw.close();
      await expectLater(
        ReceiptRepository.open(h.file),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.code,
            'code',
            'unsupportedSchema',
          ),
        ),
      );
      final original = sqlite.sqlite3.open(h.file.path);
      expect(original.select('PRAGMA user_version').single['user_version'], 9);
      expect(
        original
            .select('SELECT COUNT(*) AS count FROM change_log')
            .single['count'],
        2,
      );
      original.close();
    },
  );

  test(
    'failed first creation rolls back DDL rather than leaving a partial schema',
    () async {
      final path = File('${h.directory.path}/migration-failure.sqlite');
      final failed = _FailingCreate(
        NativeDatabase.createInBackground(path, setup: configureSqlite),
      );
      try {
        await expectLater(
          failed.customSelect('SELECT 1').get(),
          throwsA(anything),
        );
      } finally {
        await failed.close();
      }
      final raw = sqlite.sqlite3.open(path.path);
      expect(
        raw.select("SELECT name FROM sqlite_schema WHERE type = 'table'"),
        isEmpty,
      );
      expect(raw.select('PRAGMA user_version').single['user_version'], 0);
      raw.close();
      final recovered = await ReceiptRepository.open(path);
      await recovered.verifyIntegrity();
      await recovered.close();
    },
  );
}

// Exercise Drift's actual migration transaction without production fail hooks.
class _FailingCreate extends ReceiptDatabase {
  _FailingCreate(super.executor);
  @override
  Future<void> createInitialSchema(Migrator migrator) async {
    await super.createInitialSchema(migrator);
    throw StateError('synthetic_migration_failure');
  }
}
