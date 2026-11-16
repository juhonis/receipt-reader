import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_storage/src/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'support.dart';

class ReleasedConnection extends ReceiptDatabase {
  ReleasedConnection(super.executor);
  @override
  int get schemaVersion => 1;
}

class FailingUpgrade extends ReceiptDatabase {
  FailingUpgrade(super.executor);
  @override
  Future<void> upgradeReviewPolicy(Migrator m) async {
    await super.upgradeReviewPolicy(m);
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
    final old = v1.DatabaseAtV1(NativeDatabase(file, setup: configureSqlite));
    await old.customSelect('SELECT 1').get();
    await old.close();
    final repository = await ReceiptRepository.connect(
      ReleasedConnection(NativeDatabase(file, setup: configureSqlite)),
    );
    await repository.saveManual(command(snapshot()));
    await repository.close();
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
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
  };
  test('populated released v1 migrates without changing any persisted values or retry identity', () async {
    final raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 1);
    final before = capture(raw);
    raw.close();
    final db = ReceiptDatabase.file(file);
    final verifier = SchemaVerifier(GeneratedHelper(), setup: configureSqlite);
    await verifier.migrateAndValidate(db, 2);
    final repository = await ReceiptRepository.connect(db);
    final migrated = sqlite.sqlite3.open(file.path);
    expect(migrated.userVersion, 2);
    expect(capture(migrated), before);
    expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
    expect((await repository.saveManual(command(snapshot()))).replayed, isTrue);
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
  });
  test(
    'failed migration rolls back DDL, values and version; reopening can retry',
    () async {
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
      expect(rolledBack.userVersion, 1);
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
