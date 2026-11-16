import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

part 'database.g.dart';

/// Internal connection; application code uses ReceiptRepository, not raw SQL.
@DriftDatabase(include: {'schema.drift'})
class ReceiptDatabase extends _$ReceiptDatabase {
  ReceiptDatabase(QueryExecutor executor) : super(executor);

  factory ReceiptDatabase.file(File file) => ReceiptDatabase(
    NativeDatabase.createInBackground(file, setup: configureSqlite),
  );

  @override
  int get schemaVersion => 1;

  Future<void> createInitialSchema(Migrator migrator) => migrator.createAll();

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await createInitialSchema(m);
      // Keep schema and version atomic, including a crash before Drift's own
      // redundant version assignment after this callback returns.
      await customStatement('PRAGMA user_version = 1');
    }),
    onUpgrade: (_, from, to) async => throw StateError('unsupported_schema'),
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
      1) {
    throw StateError('unsupported_schema');
  }
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA synchronous = FULL');
  database.execute('PRAGMA busy_timeout = 5000');
}
