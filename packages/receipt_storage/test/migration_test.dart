import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_domain/receipt_domain.dart';

import '../../receipt_domain/test/ocr_support.dart';

import 'package:receipt_storage/src/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'support.dart';

class FailingUpgrade extends ReceiptDatabase {
  FailingUpgrade(super.executor);
  @override
  Future<void> upgradeTombstones(Migrator m) async {
    await super.upgradeTombstones(m);
    throw StateError('synthetic migration failure');
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('receipt-migration-');
    file = File('${directory.path}/receipts.sqlite');
  });
  tearDown(() async {
    expect(directory.parent.absolute.path, Directory.systemTemp.absolute.path);
    expect(directory.path.contains('receipt-migration-'), isTrue);
    await directory.delete(recursive: true);
  });
  Map<String, Object?> capture(sqlite.Database db) => {
    for (final table in [
      'dataset_state',
      'change_log',
      'revision_parents',
      'event_dependencies',
      'entity_heads',
      'stores',
      'receipts',
      'row_identities',
      'receipt_items',
      'receipt_reviews',
      'received_cursors',
      'local_mutations',
    ])
      table: db
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((r) => (Map<String, Object?>.from(r)..remove('is_deleted')))
          .toList(),
  };
  Future<void> seedReleased(int version) async {
    final seed = File('${directory.path}/seed.sqlite');
    final repository = await ReceiptRepository.open(seed);
    await repository.saveManual(command(snapshot()));
    if (version == 2) {
      final f = OcrFixture(), branch = (await repository.branches()).single;
      final ids = ReviewRowIds()..retain(f.rows.single.id, id(21));
      final audit = f.audit();
      final checks = OcrReviewChecks(
        audit: audit,
        branch: branch,
        receiptId: id(20),
        rowIds: ids,
        rowDetails: const {},
        expectedHeads: const [],
        mutationId: id(22),
        dateReviewed: true,
        totalReviewed: true,
      );
      await repository.saveOcr(
        ReviewedReceipt.ocr(
          current: audit,
          branch: branch,
          rowDetails: const {},
          expectedHeads: const [],
          confirmation: checks.confirm(
            reviewedAtMs: BigInt.from(456),
            appVersion: 'released-fixture',
          ),
        ),
      );
    }
    await repository.close();
    final rawSeed = sqlite.sqlite3.open(seed.path);
    final data = capture(rawSeed);
    rawSeed.close();
    final GeneratedDatabase old = version == 1
        ? v1.DatabaseAtV1(NativeDatabase(file, setup: configureSqlite))
        : v2.DatabaseAtV2(NativeDatabase(file, setup: configureSqlite));
    await old.customSelect('SELECT 1').get();
    await old.close();
    final raw = sqlite.sqlite3.open(file.path);
    try {
      raw.execute('BEGIN');
      for (final entry in data.entries) {
        for (final row in entry.value! as List<Map<String, Object?>>) {
          raw.execute(
            'INSERT INTO ${entry.key} (${row.keys.join(', ')}) VALUES (${List.filled(row.length, '?').join(', ')})',
            row.values.toList(),
          );
        }
      }
      raw.execute('COMMIT');
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      raw.close();
    }
  }

  for (final version in [1, 2]) {
    test(
      'populated released v$version migrates without changing any persisted values or retry identity',
      () async {
        await seedReleased(version);
        final raw = sqlite.sqlite3.open(file.path);
        expect(raw.userVersion, version);
        final before = capture(raw);
        raw.close();
        final db = ReceiptDatabase.file(file);
        final verifier = SchemaVerifier(
          GeneratedHelper(),
          setup: configureSqlite,
        );
        await verifier.migrateAndValidate(db, 3);
        final repository = await ReceiptRepository.connect(db);
        final migrated = sqlite.sqlite3.open(file.path);
        expect(migrated.userVersion, 3);
        expect(capture(migrated), before);
        expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await repository.saveManual(command(snapshot()))).replayed,
          isTrue,
        );
        expect(capture(migrated), before);
        for (final pair in [
          (1, 'ocr'),
          (2, 'manual'),
          (3, 'ocr'),
          (2, 'unknown'),
        ]) {
          expect(
            () => migrated.execute(
              'UPDATE receipt_reviews SET policy_version = ?, source = ?',
              [pair.$1, pair.$2],
            ),
            throwsA(isA<sqlite.SqliteException>()),
          );
        }
        migrated.close();
        await repository.close();
        final reopened = await ReceiptRepository.open(file);
        await reopened.verifyIntegrity();
        await reopened.close();
      },
    );
    test(
      'failed v$version migration rolls back DDL, values and version; reopening can retry',
      () async {
        await seedReleased(version);
        final raw = sqlite.sqlite3.open(file.path);
        final before = capture(raw);
        final schema = raw
            .select('SELECT sql FROM sqlite_schema ORDER BY name')
            .map((r) => r['sql'])
            .toList();
        raw.close();
        final broken = FailingUpgrade(
          NativeDatabase(file, setup: configureSqlite),
        );
        await expectLater(
          broken.customSelect('SELECT 1').get(),
          throwsA(anything),
        );
        await broken.close();
        final rolledBack = sqlite.sqlite3.open(file.path);
        expect(rolledBack.userVersion, version);
        expect(capture(rolledBack), before);
        expect(
          rolledBack
              .select('SELECT sql FROM sqlite_schema ORDER BY name')
              .map((r) => r['sql'])
              .toList(),
          schema,
        );
        rolledBack.close();
        final recovered = await ReceiptRepository.open(file);
        await recovered.verifyIntegrity();
        expect(
          (await recovered.saveManual(command(snapshot()))).replayed,
          isTrue,
        );
        await recovered.close();
      },
    );
  }
}
