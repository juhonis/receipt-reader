import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

part 'database.g.dart';

/// Internal connection; application code uses ReceiptRepository, not raw SQL.
@DriftDatabase(include: {'schema.drift'})
class ReceiptDatabase extends _$ReceiptDatabase {
  ReceiptDatabase(QueryExecutor executor) : super(executor);

  factory ReceiptDatabase.file(File file) {
    // Every call creates a distinct executor. Restore deliberately opens an
    // isolated candidate alongside the active DB; Drift's shared-executor
    // warning cannot apply here. Restore the global option synchronously.
    final warning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    try {
      return ReceiptDatabase(
        NativeDatabase.createInBackground(file, setup: configureSqlite),
      );
    } finally {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = warning;
    }
  }

  @override
  int get schemaVersion => 9;

  Future<void> createInitialSchema(Migrator migrator) => migrator.createAll();

  /// Rebuild only the review projection. Existing canonical bytes and events
  /// remain unchanged; rollback must retain the original schema on any failure.
  Future<void> upgradeReviewPolicy(Migrator migrator) async {
    await customStatement(
      'ALTER TABLE receipt_reviews RENAME TO receipt_reviews_previous',
    );
    await migrator.createTable(receiptReviews);
    await customStatement(
      'INSERT INTO receipt_reviews SELECT * FROM receipt_reviews_previous',
    );
    await customStatement('DROP TABLE receipt_reviews_previous');
  }

  /// Rebuild constraints while preserving every existing event and identity.
  /// Foreign keys are disabled only outside the encompassing DDL transaction.
  Future<void> upgradeTombstones(Migrator migrator) async {
    await migrator.alterTable(TableMigration(changeLog));
    await migrator.alterTable(
      TableMigration(receipts, newColumns: [receipts.isDeleted]),
    );
  }

  Future<void> upgradeCatalog(Migrator migrator) async {
    await migrator.alterTable(TableMigration(changeLog));
    await migrator.alterTable(TableMigration(entityHeads));
    await migrator.createTable(products);
    await migrator.createTable(productAliases);
    await migrator.createTable(catalogMutations);
    // createTable does not create the associated indexes and triggers.
    for (final entity in allSchemaEntities.where(
      (e) =>
          e is! TableInfo &&
          (e.entityName.startsWith('products_') ||
              e.entityName.startsWith('product_aliases_') ||
              e.entityName.startsWith('catalog_mutations_')),
    )) {
      await migrator.create(entity);
    }
  }

  Future<void> upgradeProductLinks(Migrator migrator) async {
    await migrator.alterTable(TableMigration(receiptItems));
  }

  Future<void> upgradeProductCategories(Migrator migrator) async {
    await migrator.alterTable(TableMigration(changeLog));
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await createInitialSchema(m);
      // Keep schema and version atomic, including a crash before Drift's own
      // redundant version assignment after this callback returns.
      await customStatement('PRAGMA user_version = 9');
    }),
    onUpgrade: (m, from, to) async {
      if ((from < 1 || from > 8) || to != 9) {
        throw StateError('unsupported_schema');
      }
      await customStatement('PRAGMA foreign_keys = OFF');
      try {
        await transaction(() async {
          if (from < 3) await upgradeTombstones(m);
          if (from < 4) await upgradeCatalog(m);
          if (from < 5) await upgradeProductLinks(m);
          await upgradeReviewPolicy(m);
          if (from < 9) await upgradeProductCategories(m);
          if ((await customSelect(
            'PRAGMA foreign_key_check',
          ).get()).isNotEmpty) {
            throw StateError('migration_foreign_keys');
          }
          await customStatement('PRAGMA user_version = 9');
        });
      } finally {
        await customStatement('PRAGMA foreign_keys = ON');
      }
    },
    beforeOpen: (_) async {
      final fk = await customSelect('PRAGMA foreign_keys').getSingle();
      final mode = await customSelect('PRAGMA journal_mode').getSingle();
      final sync = await customSelect('PRAGMA synchronous').getSingle();
      if (fk.read<int>('foreign_keys') != 1 ||
          mode.read<String>('journal_mode') != 'wal' ||
          sync.read<int>('synchronous') != 2) {
        throw StateError('sqlite_configuration');
      }
    },
  );
}

void configureSqlite(sqlite.Database database) {
  // Reject future databases before Drift can run any version migration.
  if ((database.select('PRAGMA user_version').single['user_version'] as int) >
      9) {
    throw StateError('unsupported_schema');
  }
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA synchronous = FULL');
  database.execute('PRAGMA busy_timeout = 5000');
}
