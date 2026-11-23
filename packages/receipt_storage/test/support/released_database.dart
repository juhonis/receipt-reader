import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, Migrator;
import 'package:drift/native.dart';
import 'package:receipt_storage/src/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../generated/schema_v1.dart' as v1;
import '../generated/schema_v2.dart' as v2;
import '../generated/schema_v3.dart' as v3;
import '../generated/schema_v4.dart' as v4;
import '../generated/schema_v5.dart' as v5;
import '../generated/schema_v6.dart' as v6;

/// Only synthetic fixture databases may be passed to these test helpers.
Map<String, List<Map<String, Object?>>> captureReleasedTables(
  sqlite.Database db,
) => {
  for (final table in [
    'dataset_state',
    'change_log',
    'revision_parents',
    'event_dependencies',
    'entity_heads',
    'stores',
    'products',
    'receipts',
    'row_identities',
    'receipt_items',
    'receipt_reviews',
    'received_cursors',
    'local_mutations',
    'product_aliases',
    'catalog_mutations',
  ])
    if (db.select(
      "SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = ?",
      [table],
    ).isNotEmpty)
      table: db
          .select('SELECT * FROM $table ORDER BY rowid')
          .map(
            (row) => <String, Object?>{
              // Schema 3 adds this default to existing receipt projections.
              if (table == 'receipts') 'is_deleted': 0,
              ...row,
            },
          )
          .toList(),
};

/// Build a real historical schema, not a current DB with a lowered version flag.
/// Source must contain only features representable by the requested version.
Future<void> copyToReleasedSchema(File source, File target, int version) async {
  if (version < 1 ||
      version > 6 ||
      await target.exists() ||
      source.parent.absolute.path != target.parent.absolute.path) {
    throw StateError('unsafe_released_fixture_target');
  }
  final seed = sqlite.sqlite3.open(source.path);
  late Map<String, List<Map<String, Object?>>> data;
  try {
    data = captureReleasedTables(seed);
  } finally {
    seed.close();
  }
  final GeneratedDatabase old = switch (version) {
    1 => v1.DatabaseAtV1(NativeDatabase(target, setup: configureSqlite)),
    2 => v2.DatabaseAtV2(NativeDatabase(target, setup: configureSqlite)),
    3 => v3.DatabaseAtV3(NativeDatabase(target, setup: configureSqlite)),
    4 => v4.DatabaseAtV4(NativeDatabase(target, setup: configureSqlite)),
    5 => v5.DatabaseAtV5(NativeDatabase(target, setup: configureSqlite)),
    _ => v6.DatabaseAtV6(NativeDatabase(target, setup: configureSqlite)),
  };
  try {
    await old.customSelect('SELECT 1').get();
  } finally {
    await old.close();
  }
  final raw = sqlite.sqlite3.open(target.path);
  try {
    raw.execute('PRAGMA foreign_keys = ON');
    raw.execute('BEGIN');
    try {
      for (final entry in data.entries) {
        if (version < 4 &&
            {
              'products',
              'product_aliases',
              'catalog_mutations',
            }.contains(entry.key)) {
          if (entry.value.isNotEmpty)
            throw StateError('incompatible_fixture_catalog');
          continue;
        }
        for (final original in entry.value) {
          final row = Map<String, Object?>.from(original);
          if (version < 3) {
            if (entry.key == 'receipts' && row['is_deleted'] != 0)
              throw StateError('incompatible_fixture_deletion');
            row.remove('is_deleted');
          }
          raw.execute(
            'INSERT INTO ${entry.key} (${row.keys.join(', ')}) VALUES (${List.filled(row.length, '?').join(', ')})',
            row.values.toList(),
          );
        }
      }
      if (raw.select('PRAGMA foreign_key_check').isNotEmpty)
        throw StateError('fixture_foreign_keys');
      raw.execute('COMMIT');
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    raw.close();
  }
}

/// Failure after the last DDL step exercises the enclosing migration transaction.
class FailingReviewUpgrade extends ReceiptDatabase {
  FailingReviewUpgrade(super.executor);
  @override
  Future<void> upgradeProductCategories(Migrator m) async {
    await super.upgradeProductCategories(m);
    throw StateError('synthetic migration failure');
  }
}

Future<void> failReleasedUpgrade(File file) async {
  final broken = FailingReviewUpgrade(
    NativeDatabase(file, setup: configureSqlite),
  );
  try {
    await broken.customSelect('SELECT 1').get();
  } finally {
    await broken.close();
  }
}
