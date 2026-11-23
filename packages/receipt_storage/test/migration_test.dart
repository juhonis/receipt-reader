import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_domain/receipt_domain.dart';

import '../../receipt_domain/test/ocr_support.dart';

import 'package:receipt_storage/src/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'support.dart';
import 'catalog_support.dart';
import 'support/released_database.dart';

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
  Map<String, Object?> capture(sqlite.Database db) => captureReleasedTables(db);
  Future<void> seedReleased(int version) async {
    final seed = File('${directory.path}/seed.sqlite');
    final repository = await ReceiptRepository.open(seed);
    await repository.saveManual(command(snapshot()));
    if (version >= 2) {
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
    if (version >= 3) {
      final receipt = (await repository.read(id(1)))!;
      final deletion = ReceiptDeletionChecks(
        document: receipt.document,
        expectedHead: receipt.revision,
        mutationId: id(30),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(789), appVersion: 'migration-test');
      await repository.deleteReceipt(deletion);
    }
    if (version >= 4) {
      final branch = (await repository.branches()).first;
      final p = await repository.saveProduct(
        productDocument(branch, number: 60),
        mutationId: id(61),
      );
      await repository.saveAlias(
        aliasDocument(branch, p.revision, number: 62, product: 60),
        mutationId: id(63),
      );
    }
    await repository.close();
    await copyToReleasedSchema(seed, file, version);
  }

  for (final version in [1, 2, 3, 4, 5, 6]) {
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
        await verifier.migrateAndValidate(db, 7);
        final repository = await ReceiptRepository.connect(db);
        final migrated = sqlite.sqlite3.open(file.path);
        expect(migrated.userVersion, 7);
        expect({
          for (final key in before.keys) key: capture(migrated)[key],
        }, before);
        expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await repository.saveManual(command(snapshot()))).replayed,
          isTrue,
        );
        expect({
          for (final key in before.keys) key: capture(migrated)[key],
        }, before);
        for (final pair in [
          (1, 'ocr'),
          (2, 'manual'),
          (4, 'ocr'),
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
        migrated.execute('PRAGMA foreign_keys = ON');
        final branch = (await repository.branches()).firstWhere(
          (b) => b.id == id(2),
        );
        final product = await repository.saveProduct(
          productDocument(branch),
          mutationId: id(40),
        );
        await repository.saveAlias(
          aliasDocument(branch, product.revision, name: 'new migration alias'),
          mutationId: id(41),
        );
        expect(
          () => migrated.execute('UPDATE product_aliases SET store_id = ?', [
            id(99).value,
          ]),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          () => migrated.execute('DELETE FROM catalog_mutations'),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          () => migrated.execute('DELETE FROM change_log'),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          () => migrated.execute(
            'INSERT INTO product_aliases SELECT ?, store_id, normalized_name, normalizer_version, product_id, is_active, current_revision_origin, current_revision_seq, created_at_ms, updated_at_ms FROM product_aliases',
            [id(90).value],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        if (version >= 3) {
          expect(await repository.readDeleted(id(1)), isNotNull);
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
        await expectLater(
          failReleasedUpgrade(file),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'synthetic migration failure',
            ),
          ),
        );
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
