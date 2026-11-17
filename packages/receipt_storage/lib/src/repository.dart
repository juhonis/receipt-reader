import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:sqlite3/common.dart' as sqlite;

import 'database.dart';
import 'history_filter.dart';

part 'integrity.dart';
part 'backup.dart';
part 'catalog.dart';
part 'purchases.dart';

final class StorageFailure implements Exception {
  const StorageFailure(this.code);
  final String code;
  @override
  String toString() => 'StorageFailure($code)';
}

final class DatasetIdentity {
  const DatasetIdentity(this.datasetId, this.deviceId, this.nextLocalSequence);
  final DurableId datasetId, deviceId;
  final BigInt nextLocalSequence;
}

final class StoredReceipt {
  const StoredReceipt(this.document, this.revision);
  final ReceiptDocument document;
  final RevisionId revision;
}

final class DeletedReceipt {
  const DeletedReceipt(this.tombstone, this.revision);
  final ReceiptTombstone tombstone;
  final RevisionId revision;
}

final class SaveResult {
  const SaveResult(this.revision, {required this.replayed});
  final RevisionId revision;
  final bool replayed;
}

/// Owns a private database connection. No writes occur until explicitly opened.
/// Receipt imports/OCR must never be relabelled as manual to use this repository.
final class ReceiptRepository {
  ReceiptRepository._(this._db);
  final ReceiptDatabase _db;

  static Future<ReceiptRepository> open(File file) =>
      connect(ReceiptDatabase.file(file));

  /// Internal connection seam for migration/failure tests, not UI SQL access.
  static Future<ReceiptRepository> connect(ReceiptDatabase database) async {
    final repository = ReceiptRepository._(database);
    try {
      await repository._guard(
        () => database.transaction(() async {
          final rows = await repository._rows('SELECT * FROM dataset_state');
          if (rows.isEmpty) {
            // Only a genuinely empty dataset can receive a fresh installation ID.
            _check(
              (await repository._rows('SELECT 1 FROM change_log LIMIT 1'))
                  .isEmpty,
              'missingIdentity',
            );
            final dataset = DurableId.generate(), device = DurableId.generate();
            await repository._insert('dataset_state', {
              'singleton': 1,
              'dataset_id': dataset.value,
              'device_id': device.value,
              'next_local_seq': 1,
            });
            await repository._insert('received_cursors', {
              'origin_device_id': device.value,
              'committed_seq': 0,
            });
          }
          await repository._verifyIntegrity();
        }),
      );
      return repository;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  /// A consistent structured snapshot. Contains financial history; not encrypted.
  /// No user-facing export policy or file picker is implied by this core API.
  Future<Uint8List> exportBackup() => _guard(
    () => _db.transaction(() async {
      await _checkBackupSize();
      await _verifyIntegrity();
      return _encodeBackup(await _backupContent());
    }),
  );

  /// Validates/rebuilds in a new private staging directory. Never activates,
  /// replaces, or opens an existing application dataset. Caller owns successful
  /// staging output; failed attempts close and remove only their own directory.
  static Future<RestoredReceiptBackup> restoreBackup(
    Uint8List bytes, {
    required Directory stagingParent,
  }) => _restoreBackup(bytes, stagingParent);

  Future<void> close() => _db.close();

  Future<DatasetIdentity> identity() => _guard(_identity);
  Future<DatasetIdentity> _identity() async {
    final rows = await _rows('SELECT * FROM dataset_state');
    _check(rows.length == 1, 'identityCount');
    final row = rows.single;
    return DatasetIdentity(
      DurableId.parse(row['dataset_id']! as String),
      DurableId.parse(row['device_id']! as String),
      BigInt.from(row['next_local_seq']! as int),
    );
  }

  Future<List<ReceiptBranch>> branches() => _guard(() async {
    final rows = await _rows('SELECT * FROM stores ORDER BY display_name, id');
    return List.unmodifiable(rows.map(_branch));
  });

  /// One consistent, bounded page, ordered by printed Helsinki civil date.
  /// Date-only receipts precede earlier days without inventing an instant.
  /// Ties use the durable ID so pagination is deterministic.
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) {
    if (limit < 1 || limit > 200 || offset < 0) {
      throw ArgumentError('invalid_history_page');
    }
    final conditions = <String>['is_deleted = 0'];
    final args = <Object>[];
    if (filter?.branchId case final branch?) {
      conditions.add('store_id = ?');
      args.add(branch.value);
    }
    for (final bound in [
      (filter?.fromDate, '>='),
      (filter?.throughDate, '<='),
    ]) {
      if (bound.$1 case final date?) {
        conditions.add(
          '(printed_year, printed_month, printed_day) ${bound.$2} (?, ?, ?)',
        );
        args.addAll([date.year, date.month, date.day]);
      }
    }
    for (final bound in [
      (filter?.minTotalCents, '>='),
      (filter?.maxTotalCents, '<='),
    ]) {
      if (bound.$1 case final amount?) {
        conditions.add('total_amount_cents ${bound.$2} ?');
        args.add(amount.toInt());
      }
    }
    final where = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')} ';
    return _guard(
      () => _db.transaction(() async {
        final rows = await _rows(
          'SELECT id FROM receipts ${where}ORDER BY printed_year DESC, printed_month DESC, '
          'printed_day DESC, COALESCE(printed_hour, -1) DESC, '
          'COALESCE(printed_minute, -1) DESC, COALESCE(printed_second, -1) DESC, '
          'id ASC LIMIT ? OFFSET ?',
          [...args, limit, offset],
        );
        return List.unmodifiable([
          for (final row in rows)
            (await _read(DurableId.parse(row['id']! as String)))!,
        ]);
      }),
    );
  }

  Future<StoredReceipt?> read(DurableId id) =>
      _guard(() => _db.transaction(() => _read(id)));

  Future<StoredReceipt?> _read(DurableId id) async {
    final rows = await _rows('SELECT * FROM receipts WHERE id = ?', [id.value]);
    if (rows.isEmpty) return null;
    final receipt = rows.single;
    if (receipt['is_deleted'] == 1) {
      await _readDeleted(id);
      return null;
    }
    final reviews = await _rows(
      'SELECT * FROM receipt_reviews WHERE receipt_id = ?',
      [id.value],
    );
    _check(reviews.length == 1, 'missingReview');
    final review = reviews.single;
    final document = ReceiptDocumentCodec.decode(
      review['canonical_document']! as String,
    );
    _check(
      document.snapshot.id == id &&
          document.sha256Hex == review['approved_sha256'],
      'reviewDigest',
    );
    final revision = _revision(receipt);
    final events = await _rows(
      'SELECT * FROM change_log WHERE origin_device_id = ? AND origin_seq = ?',
      [revision.origin.value, revision.sequence.toInt()],
    );
    _check(
      events.length == 1 &&
          events.single['entity_kind'] == 'receipt' &&
          events.single['entity_id'] == id.value &&
          events.single['payload'] == review['canonical_document'],
      'receiptEvent',
    );
    _check(
      _sameFields(
        receipt,
        _receiptFields(document, revision, receipt['created_at_ms']! as int),
      ),
      'receiptProjection',
    );
    _check(_sameFields(review, _reviewFields(document)), 'reviewProjection');
    final items = await _rows(
      'SELECT * FROM receipt_items WHERE receipt_id = ? ORDER BY position',
      [id.value],
    );
    _check(items.length == document.snapshot.items.length, 'itemCount');
    for (var i = 0; i < items.length; i++) {
      _check(
        _sameFields(items[i], _itemFields(document.snapshot, i)),
        'itemProjection',
      );
    }
    final heads = await _heads('receipt', id);
    _check(heads.length == 1 && heads.single == revision, 'receiptHeads');
    return StoredReceipt(document, revision);
  }

  Future<DeletedReceipt?> readDeleted(DurableId id) =>
      _guard(() => _db.transaction(() => _readDeleted(id)));

  Future<DeletedReceipt?> _readDeleted(DurableId id) async {
    final rows = await _rows('SELECT * FROM receipts WHERE id = ?', [id.value]);
    if (rows.isEmpty || rows.single['is_deleted'] != 1) return null;
    final receipt = rows.single, revision = _revision(rows.single);
    final events = await _rows(
      'SELECT * FROM change_log WHERE origin_device_id = ? AND origin_seq = ?',
      [revision.origin.value, revision.sequence.toInt()],
    );
    _check(
      events.length == 1 &&
          events.single['entity_kind'] == 'receipt' &&
          events.single['entity_id'] == id.value &&
          events.single['operation'] == 'tombstone',
      'tombstoneEvent',
    );
    final tombstone = ReceiptTombstoneCodec.decode(
      events.single['payload']! as String,
    );
    _check(
      tombstone.receiptId == id &&
          tombstone.deletedAtMs ==
              BigInt.from(events.single['audit_at_ms']! as int),
      'tombstonePayload',
    );
    _check(
      _sameFields(
        receipt,
        _tombstoneFields(tombstone, revision, receipt['created_at_ms']! as int),
      ),
      'tombstoneProjection',
    );
    _check(
      (await _rows('SELECT 1 FROM receipt_items WHERE receipt_id = ?', [
            id.value,
          ])).isEmpty &&
          (await _rows('SELECT 1 FROM receipt_reviews WHERE receipt_id = ?', [
            id.value,
          ])).isEmpty,
      'tombstoneChildren',
    );
    final heads = await _heads('receipt', id);
    _check(heads.length == 1 && heads.single == revision, 'receiptHeads');
    return DeletedReceipt(tombstone, revision);
  }

  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) => _guard(
    () => _db.transaction(() async {
      final json = ReceiptTombstoneCodec.encode(command.tombstone);
      final tombstone = ReceiptTombstoneCodec.decode(json);
      final id = tombstone.receiptId;
      _check(
        (await _rows('SELECT 1 FROM catalog_mutations WHERE mutation_id = ?', [
          command.mutationId.value,
        ])).isEmpty,
        'mutationIdentityReused',
      );
      final retry = await _rows(
        'SELECT * FROM local_mutations WHERE mutation_id = ?',
        [command.mutationId.value],
      );
      if (retry.isNotEmpty) {
        final row = retry.single;
        _check(
          row['command_sha256'] == tombstone.sha256Hex &&
              row['receipt_id'] == id.value,
          'mutationIdentityReused',
        );
        final revision = RevisionId(
          DurableId.parse(row['result_origin']! as String),
          BigInt.from(row['result_seq']! as int),
        );
        final events = await _rows(
          'SELECT operation, payload FROM change_log WHERE origin_device_id = ? AND origin_seq = ?',
          [revision.origin.value, revision.sequence.toInt()],
        );
        _check(
          events.length == 1 &&
              events.single['operation'] == 'tombstone' &&
              events.single['payload'] == json,
          'retryEvent',
        );
        return SaveResult(revision, replayed: true);
      }
      final current = await _read(id);
      _check(
        current != null &&
            current.revision == tombstone.expectedHead &&
            current.document.sha256Hex == tombstone.documentSha256 &&
            current.document.review.source == tombstone.source,
        'staleReceipt',
      );
      final state = await _identity();
      final next = state.nextLocalSequence + BigInt.one;
      _check(next <= sqliteInt64Max, 'sequenceExhausted');
      await _db.customStatement(
        'UPDATE dataset_state SET next_local_seq = ? WHERE singleton = 1',
        [next.toInt()],
      );
      final revision = RevisionId(state.deviceId, state.nextLocalSequence);
      await _appendEvent(
        state,
        revision,
        'receipt',
        id,
        json,
        command.mutationId,
        0,
        1,
        tombstone.deletedAtMs.toInt(),
        [tombstone.expectedHead],
        [],
        operation: 'tombstone',
      );
      await _db.customStatement(
        'DELETE FROM receipt_items WHERE receipt_id = ?',
        [id.value],
      );
      await _db.customStatement(
        'DELETE FROM receipt_reviews WHERE receipt_id = ?',
        [id.value],
      );
      final created =
          (await _rows('SELECT created_at_ms FROM receipts WHERE id = ?', [
                id.value,
              ])).single['created_at_ms']!
              as int;
      await _upsertReceipt(
        _tombstoneFields(tombstone, revision, created),
        true,
      );
      await _selectHead('receipt', id, revision);
      await _db.customStatement(
        'UPDATE received_cursors SET committed_seq = ? WHERE origin_device_id = ?',
        [revision.sequence.toInt(), state.deviceId.value],
      );
      await _insert('local_mutations', {
        'mutation_id': command.mutationId.value,
        'command_sha256': tombstone.sha256Hex,
        'receipt_id': id.value,
        'result_origin': revision.origin.value,
        'result_seq': revision.sequence.toInt(),
      });
      await _readDeleted(id);
      return SaveResult(revision, replayed: false);
    }),
  );

  Future<void> verifyIntegrity() =>
      _guard(() => _db.transaction(_verifyIntegrity));

  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      _save(command, 'manual');
  Future<SaveResult> saveOcr(ReviewedReceipt command) => _save(command, 'ocr');

  Future<SaveResult> _save(ReviewedReceipt command, String source) => _guard(
    () => _db.transaction(() async {
      _check(command.document.review.source == source, 'unsupportedSource');
      // Re-parse the immutable command at the storage boundary, under its policy.
      final json = ReceiptDocumentCodec.encode(command.document);
      final document = ReceiptDocumentCodec.decode(json);
      final snapshot = document.snapshot;
      final digest = document.sha256Hex;
      _check(
        (await _rows('SELECT 1 FROM catalog_mutations WHERE mutation_id = ?', [
          command.mutationId.value,
        ])).isEmpty,
        'mutationIdentityReused',
      );
      final retry = await _rows(
        'SELECT * FROM local_mutations WHERE mutation_id = ?',
        [command.mutationId.value],
      );
      if (retry.isNotEmpty) {
        _check(
          retry.single['command_sha256'] == digest &&
              retry.single['receipt_id'] == snapshot.id.value,
          'mutationIdentityReused',
        );
        final row = retry.single;
        final revision = RevisionId(
          DurableId.parse(row['result_origin']! as String),
          BigInt.from(row['result_seq']! as int),
        );
        final event = await _rows(
          'SELECT payload FROM change_log WHERE origin_device_id = ? AND origin_seq = ?',
          [revision.origin.value, revision.sequence.toInt()],
        );
        _check(
          event.length == 1 && event.single['payload'] == json,
          'retryEvent',
        );
        return SaveResult(revision, replayed: true);
      }
      final productRevisions = <RevisionId>{};
      final productHeads = <DurableId, RevisionId>{};
      for (final row in snapshot.items) {
        if (row.product case final link?) {
          final product = await _product(link.id);
          _check(
            product.document.product.storeId == snapshot.branch.id &&
                link.storeId == snapshot.branch.id,
            'crossStoreProduct',
          );
          _check(product.revision == link.revision, 'staleProduct');
          _check(
            productHeads[link.id] == null ||
                productHeads[link.id] == link.revision,
            'staleProduct',
          );
          productHeads[link.id] = link.revision;
          productRevisions.add(link.revision);
        }
      }
      _check(
        (await _rows('SELECT is_deleted FROM receipts WHERE id = ?', [
          snapshot.id.value,
        ])).every((r) => r['is_deleted'] == 0),
        'receiptDeleted',
      );
      final current = await _read(snapshot.id);
      _check(
        current == null || current.document.review.source == source,
        'provenanceChange',
      );
      final expected = document.review.expectedHeads;
      _check(
        current == null
            ? expected.isEmpty
            : expected.length == 1 && expected.single == current.revision,
        'staleReceipt',
      );
      final oldIds = current == null
          ? <DurableId>{}
          : _documentRowIds(current.document);
      final rowIds = _documentRowIds(document);
      for (final rowId in rowIds) {
        final owners = await _rows(
          'SELECT receipt_id FROM row_identities WHERE row_id = ?',
          [rowId.value],
        );
        if (owners.isNotEmpty) {
          _check(
            owners.single['receipt_id'] == snapshot.id.value &&
                oldIds.contains(rowId),
            'rowIdentityReused',
          );
        }
      }
      final storeRows = await _rows('SELECT * FROM stores WHERE id = ?', [
        snapshot.branch.id.value,
      ]);
      final createsBranch = storeRows.isEmpty;
      if (createsBranch) {
        _check(snapshot.branch.revision == null, 'missingBranch');
        _check(
          (await _heads('store', snapshot.branch.id)).isEmpty,
          'branchHistory',
        );
      } else {
        final branch = _branch(storeRows.single);
        final branchHeads = await _heads('store', branch.id);
        _check(
          snapshot.branch.revision == branch.revision &&
              branchHeads.length == 1 &&
              branchHeads.single == branch.revision &&
              _branchPayload(snapshot.branch) == _branchPayload(branch),
          'staleBranch',
        );
      }
      final state = await _identity();
      final count = createsBranch ? 2 : 1;
      final next = state.nextLocalSequence + BigInt.from(count);
      _check(next <= sqliteInt64Max, 'sequenceExhausted');
      await _db.customStatement(
        'UPDATE dataset_state SET next_local_seq = ? WHERE singleton = 1',
        [next.toInt()],
      );
      final auditAt = document.review.reviewedAtMs.toInt();
      RevisionId branchRevision;
      if (createsBranch) {
        branchRevision = RevisionId(state.deviceId, state.nextLocalSequence);
        await _appendEvent(
          state,
          branchRevision,
          'store',
          snapshot.branch.id,
          _branchPayload(snapshot.branch),
          command.mutationId,
          0,
          count,
          auditAt,
          [],
          [],
        );
        await _insert('stores', {
          'id': snapshot.branch.id.value,
          'display_name': snapshot.branch.name,
          'chain': snapshot.branch.chain,
          'address': snapshot.branch.address,
          'printed_identifier': snapshot.branch.printedIdentifier,
          'current_revision_origin': branchRevision.origin.value,
          'current_revision_seq': branchRevision.sequence.toInt(),
          'created_at_ms': auditAt,
          'updated_at_ms': auditAt,
        });
        await _selectHead('store', snapshot.branch.id, branchRevision);
      } else {
        branchRevision = snapshot.branch.revision!;
      }
      final revision = RevisionId(state.deviceId, next - BigInt.one);
      await _appendEvent(
        state,
        revision,
        'receipt',
        snapshot.id,
        json,
        command.mutationId,
        count - 1,
        count,
        auditAt,
        expected,
        [branchRevision, ...productRevisions],
      );
      // Deferred self-foreign keys permit a discount to precede its product, and
      // allow the complete collection to be replaced without partial projections.
      await _db.customStatement(
        'DELETE FROM receipt_items WHERE receipt_id = ?',
        [snapshot.id.value],
      );
      await _db.customStatement(
        'DELETE FROM receipt_reviews WHERE receipt_id = ?',
        [snapshot.id.value],
      );
      final createdAt = current == null
          ? auditAt
          : (await _rows('SELECT created_at_ms FROM receipts WHERE id = ?', [
                  snapshot.id.value,
                ])).single['created_at_ms']!
                as int;
      await _upsertReceipt(
        _receiptFields(document, revision, createdAt),
        current != null,
      );
      for (final rowId in rowIds.difference(oldIds)) {
        await _insert('row_identities', {
          'row_id': rowId.value,
          'receipt_id': snapshot.id.value,
          'first_origin': revision.origin.value,
          'first_seq': revision.sequence.toInt(),
        });
      }
      for (var i = 0; i < snapshot.items.length; i++) {
        await _insert('receipt_items', _itemFields(snapshot, i));
      }
      await _insert('receipt_reviews', _reviewFields(document));
      await _selectHead('receipt', snapshot.id, revision);
      await _db.customStatement(
        'UPDATE received_cursors SET committed_seq = ? WHERE origin_device_id = ?',
        [revision.sequence.toInt(), state.deviceId.value],
      );
      await _insert('local_mutations', {
        'mutation_id': command.mutationId.value,
        'command_sha256': digest,
        'receipt_id': snapshot.id.value,
        'result_origin': revision.origin.value,
        'result_seq': revision.sequence.toInt(),
      });
      // The read path checks projection/domain agreement before commit too.
      await _read(snapshot.id);
      return SaveResult(revision, replayed: false);
    }),
  );

  Future<void> _appendEvent(
    DatasetIdentity state,
    RevisionId revision,
    String kind,
    DurableId id,
    String payload,
    DurableId mutation,
    int index,
    int count,
    int auditAt,
    List<RevisionId> parents,
    List<RevisionId> dependencies, {
    String operation = 'snapshot',
  }) async {
    final event = _eventJson(
      state.datasetId,
      revision,
      kind,
      id,
      payload,
      mutation,
      index,
      count,
      auditAt,
      parents,
      dependencies,
      operation: operation,
    );
    await _insert('change_log', {
      'origin_device_id': revision.origin.value,
      'origin_seq': revision.sequence.toInt(),
      'dataset_id': state.datasetId.value,
      'entity_kind': kind,
      'entity_id': id.value,
      'payload_version': 1,
      'operation': operation,
      'payload': payload,
      'canonical_event': event,
      'event_sha256': _sha(event),
      'audit_at_ms': auditAt,
      'mutation_id': mutation.value,
      'mutation_index': index,
      'mutation_count': count,
    });
    for (final parent in parents) {
      await _insert('revision_parents', {
        'child_origin': revision.origin.value,
        'child_seq': revision.sequence.toInt(),
        'parent_origin': parent.origin.value,
        'parent_seq': parent.sequence.toInt(),
      });
    }
    for (final dependency in dependencies) {
      await _insert('event_dependencies', {
        'child_origin': revision.origin.value,
        'child_seq': revision.sequence.toInt(),
        'dependency_origin': dependency.origin.value,
        'dependency_seq': dependency.sequence.toInt(),
      });
    }
  }

  Future<List<RevisionId>> _heads(String kind, DurableId id) async =>
      (await _rows(
            'SELECT origin_device_id, origin_seq FROM entity_heads WHERE entity_kind = ? AND entity_id = ? ORDER BY origin_device_id, origin_seq',
            [kind, id.value],
          ))
          .map(
            (row) => RevisionId(
              DurableId.parse(row['origin_device_id']! as String),
              BigInt.from(row['origin_seq']! as int),
            ),
          )
          .toList();

  Future<void> _selectHead(
    String kind,
    DurableId id,
    RevisionId revision,
  ) async {
    await _db.customStatement(
      'DELETE FROM entity_heads WHERE entity_kind = ? AND entity_id = ?',
      [kind, id.value],
    );
    await _insert('entity_heads', {
      'entity_kind': kind,
      'entity_id': id.value,
      'origin_device_id': revision.origin.value,
      'origin_seq': revision.sequence.toInt(),
    });
  }

  Future<void> _upsertReceipt(
    Map<String, Object?> fields,
    bool existing,
  ) async {
    if (!existing) return _insert('receipts', fields);
    final keys = fields.keys.where((key) => key != 'id').toList();
    await _db.customStatement(
      'UPDATE receipts SET ${keys.map((key) => '$key = ?').join(', ')} WHERE id = ?',
      [...keys.map((key) => fields[key]), fields['id']],
    );
  }

  Future<void> _insert(
    String table,
    Map<String, Object?> fields,
  ) => _db.customStatement(
    'INSERT INTO $table (${fields.keys.join(', ')}) VALUES (${List.filled(fields.length, '?').join(', ')})',
    fields.values.toList(),
  );

  Future<List<Map<String, Object?>>> _rows(
    String sql, [
    List<Object> args = const [],
  ]) async =>
      (await _db
              .customSelect(
                sql,
                variables: args
                    .map(
                      (value) => switch (value) {
                        String v => Variable<String>(v),
                        int v => Variable<int>(v),
                        _ => throw const StorageFailure('queryArgument'),
                      },
                    )
                    .toList(),
              )
              .get())
          .map((row) => row.data)
          .toList();

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on StorageFailure {
      rethrow;
    } on ReceiptDataException {
      throw const StorageFailure('invalidData');
    } on CouldNotRollBackException catch (error) {
      // SQLITE_FULL can already roll back SQLite's transaction. Drift's second
      // ROLLBACK then fails; report the original storage failure, never its SQL.
      final cause = error.cause;
      throw _failure(cause);
    } on DriftRemoteException catch (error) {
      throw _failure(error.remoteCause);
    } on StateError catch (error) {
      throw StorageFailure(
        error.message == 'unsupported_schema'
            ? 'unsupportedSchema'
            : error.message == 'sqlite_configuration'
            ? 'sqliteConfiguration'
            : 'database',
      );
    } on sqlite.SqliteException catch (error) {
      throw _sqliteFailure(error);
    } catch (_) {
      // Drift/native exceptions can contain SQL and bound receipt values.
      throw const StorageFailure('database');
    }
  }
}

void _check(bool valid, String code) {
  if (!valid) throw StorageFailure(code);
}

StorageFailure _sqliteFailure(sqlite.SqliteException error) =>
    StorageFailure(switch (error.resultCode) {
      5 || 6 => 'busy',
      13 => 'storageFull',
      8 => 'readOnly',
      19 => 'constraint',
      11 || 26 => 'corruptDatabase',
      _ => 'database',
    });
StorageFailure _failure(Object error) {
  if (error is DriftRemoteException) return _failure(error.remoteCause);
  if (error is CouldNotRollBackException) return _failure(error.cause);
  if (error is sqlite.SqliteException) return _sqliteFailure(error);
  if (error is StorageFailure) return error;
  if (error is StateError && error.message == 'unsupported_schema') {
    return const StorageFailure('unsupportedSchema');
  }
  return const StorageFailure('database');
}

String _sha(String json) => sha256.convert(utf8.encode(json)).toString();
RevisionId _revision(Map<String, Object?> row) => RevisionId(
  DurableId.parse(row['current_revision_origin']! as String),
  BigInt.from(row['current_revision_seq']! as int),
);
ReceiptBranch _branch(Map<String, Object?> row) => ReceiptBranch(
  id: DurableId.parse(row['id']! as String),
  name: row['display_name']! as String,
  revision: _revision(row),
  chain: row['chain'] as String?,
  address: row['address'] as String?,
  printedIdentifier: row['printed_identifier'] as String?,
);
String _branchPayload(ReceiptBranch branch) => jsonEncode({
  'id': branch.id.value,
  'name': branch.name,
  'chain': branch.chain,
  'address': branch.address,
  'printed_identifier': branch.printedIdentifier,
});

String _eventJson(
  DurableId dataset,
  RevisionId revision,
  String kind,
  DurableId id,
  String payload,
  DurableId mutation,
  int index,
  int count,
  int auditAt,
  List<RevisionId> parents,
  List<RevisionId> dependencies, {
  String operation = 'snapshot',
}) {
  List<Map<String, String>> references(
    List<RevisionId> values,
  ) => (values.toList()..sort())
      .map((v) => {'origin': v.origin.value, 'sequence': v.sequence.toString()})
      .toList();
  return jsonEncode({
    'event_version': '1',
    'dataset_id': dataset.value,
    'origin': revision.origin.value,
    'sequence': revision.sequence.toString(),
    'entity_kind': kind,
    'entity_id': id.value,
    'payload_version': '1',
    'operation': operation,
    'audit_at_ms': auditAt.toString(),
    'mutation_id': mutation.value,
    'mutation_index': index.toString(),
    'mutation_count': count.toString(),
    'parents': references(parents),
    'dependencies': references(dependencies),
    'payload': jsonDecode(payload),
  });
}

Map<String, Object?> _receiptFields(
  ReceiptDocument document,
  RevisionId revision,
  int createdAt,
) {
  final s = document.snapshot, d = s.date;
  return {
    'id': s.id.value,
    'is_deleted': 0,
    'store_id': s.branch.id.value,
    'printed_year': d.year,
    'printed_month': d.month,
    'printed_day': d.day,
    'printed_hour': d.hour,
    'printed_minute': d.minute,
    'printed_second': d.second,
    'date_precision': d.precision.name,
    'timezone_id': d.timezone,
    'utc_instant_ms': d.utcInstantMs?.toInt(),
    'currency': 'EUR',
    'total_amount_cents': s.totalCents.toInt(),
    'reviewed_at_ms': document.review.reviewedAtMs.toInt(),
    'current_revision_origin': revision.origin.value,
    'current_revision_seq': revision.sequence.toInt(),
    'created_at_ms': createdAt,
    'updated_at_ms': document.review.reviewedAtMs.toInt(),
  };
}

Map<String, Object?> _tombstoneFields(
  ReceiptTombstone tombstone,
  RevisionId revision,
  int createdAt,
) => {
  'id': tombstone.receiptId.value,
  'is_deleted': 1,
  for (final field in [
    'store_id',
    'printed_year',
    'printed_month',
    'printed_day',
    'printed_hour',
    'printed_minute',
    'printed_second',
    'date_precision',
    'timezone_id',
    'utc_instant_ms',
    'currency',
    'total_amount_cents',
    'reviewed_at_ms',
  ])
    field: null,
  'current_revision_origin': revision.origin.value,
  'current_revision_seq': revision.sequence.toInt(),
  'created_at_ms': createdAt,
  'updated_at_ms': tombstone.deletedAtMs.toInt(),
};

Map<String, Object?> _reviewFields(ReceiptDocument document) => {
  'receipt_id': document.snapshot.id.value,
  'payload_version': 1,
  'policy_version': document.review.policyVersion,
  'source': document.review.source,
  'app_version': document.review.appVersion,
  'timezone_rules_version': receiptTimezoneRulesVersion,
  'row_count': document.snapshot.items.length,
  'approved_sha256': document.sha256Hex,
  'canonical_document': ReceiptDocumentCodec.encode(document),
};
Map<String, Object?> _itemFields(ReceiptSnapshot snapshot, int position) {
  final row = snapshot.items[position];
  return {
    'id': row.id.value,
    'receipt_id': snapshot.id.value,
    'store_id': snapshot.branch.id.value,
    'position': position,
    'kind': row.kind.name,
    'parent_item_id': row.parentItemId?.value,
    'discount_scope': row.discountScope?.name,
    'product_id': row.product?.id.value,
    'raw_name': row.rawName,
    'name': row.name,
    'normalized_name': row.normalizedName,
    'normalizer_version': 1,
    'quantity_value': row.quantityValue?.toInt(),
    'quantity_scale': row.quantityScale,
    'quantity_unit': row.quantityUnit?.name,
    'rate_micros': row.rateMicros?.toInt(),
    'line_total_cents': row.cents.toInt(),
    'adjustment_reason': row.adjustmentReason,
  };
}

bool _sameFields(Map<String, Object?> actual, Map<String, Object?> expected) =>
    expected.keys.every(
      (key) => actual.containsKey(key) && actual[key] == expected[key],
    );

Set<DurableId> _documentRowIds(ReceiptDocument document) => {
  ...document.snapshot.items.map((row) => row.id),
  if (document.review case final OcrReviewRecord review)
    ...review.originalRowIds,
};
