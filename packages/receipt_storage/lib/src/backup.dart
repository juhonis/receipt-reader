part of 'repository.dart';

/// Initial bounded, plaintext core format. User-facing export/encryption policy
/// and activation are separate; these bytes contain retained financial history.
abstract final class ReceiptBackupLimits {
  static const maxBytes = 64 * 1024 * 1024;
  static const maxEvents = 20000;
  static const maxEventBytes = 1024 * 1024;
  static const maxOrigins = 128;
  static const maxRowIdentities = 200000;
}

/// Closed, integrity-checked database in a newly created staging directory.
/// Caller owns successful output. It has not replaced the active application.
final class RestoredReceiptBackup {
  const RestoredReceiptBackup._(
    this.directory,
    this.databaseFile,
    this.identity,
    this.eventCount,
    this.receiptCount,
    this.deletedReceiptCount,
  );
  final Directory directory;
  final File databaseFile;
  final DatasetIdentity identity;
  final int eventCount, receiptCount, deletedReceiptCount;
}

const _countKeys = [
  'events',
  'stores',
  'receipts',
  'deleted_receipts',
  'row_identities',
  'heads',
];

Uint8List _encodeBackup(Map<String, Object?> content) {
  final text = jsonEncode({
    'format': 'receipt_reader_backup',
    'format_version': (content['counts']! as Map).containsKey('products')
        ? '2'
        : '1',
    'content_sha256': _sha(jsonEncode(content)),
    'content': content,
  });
  final bytes = utf8.encode(text);
  _check(bytes.length <= ReceiptBackupLimits.maxBytes, 'backupTooLarge');
  return bytes;
}

Map<String, Object?> _backupObject(Object? value, List<String> keys) {
  _check(value is Map<String, Object?>, 'invalidBackup');
  final map = value! as Map<String, Object?>;
  final actual = map.keys.toList();
  _check(actual.length == keys.length, 'invalidBackup');
  for (var i = 0; i < keys.length; i++) {
    _check(actual[i] == keys[i], 'invalidBackup');
  }
  return map;
}

String _backupString(Object? value) {
  _check(value is String, 'invalidBackup');
  return value! as String;
}

BigInt _backupNumber(Object? value) {
  final text = _backupString(value);
  _check(
    RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(text) && text.length <= 19,
    'invalidBackup',
  );
  final number = BigInt.parse(text);
  _check(number <= sqliteInt64Max, 'invalidBackup');
  return number;
}

final class _BackupEvent {
  _BackupEvent(
    this.canonical,
    this.dataset,
    this.revision,
    this.kind,
    this.id,
    this.operation,
    this.auditAt,
    this.mutation,
    this.index,
    this.count,
    this.parents,
    this.dependencies,
    this.payload,
  );
  final String canonical, kind, operation, payload;
  final DurableId dataset, id, mutation;
  final RevisionId revision;
  final int auditAt, index, count;
  final List<RevisionId> parents, dependencies;

  static _BackupEvent decode(Object? value, DurableId dataset) {
    final entry = _backupObject(value, ['canonical_event', 'event_sha256']);
    final canonical = _backupString(entry['canonical_event']);
    _check(
      utf8.encode(canonical).length <= ReceiptBackupLimits.maxEventBytes,
      'backupTooLarge',
    );
    _check(entry['event_sha256'] == _sha(canonical), 'backupChecksum');
    final event = _backupObject(jsonDecode(canonical), [
      'event_version',
      'dataset_id',
      'origin',
      'sequence',
      'entity_kind',
      'entity_id',
      'payload_version',
      'operation',
      'audit_at_ms',
      'mutation_id',
      'mutation_index',
      'mutation_count',
      'parents',
      'dependencies',
      'payload',
    ]);
    _check(
      event['event_version'] == '1' && event['payload_version'] == '1',
      'unsupportedBackup',
    );
    _check(event['dataset_id'] == dataset.value, 'invalidBackup');
    RevisionId revision(Object? origin, Object? sequence) {
      final number = _backupNumber(sequence);
      _check(number > BigInt.zero && number < sqliteInt64Max, 'invalidBackup');
      return RevisionId(DurableId.parse(_backupString(origin)), number);
    }

    List<RevisionId> references(Object? value, int limit) {
      _check(value is List && value.length <= limit, 'invalidBackup');
      final result = <RevisionId>[];
      for (final ref in value! as List) {
        final map = _backupObject(ref, ['origin', 'sequence']);
        result.add(revision(map['origin'], map['sequence']));
      }
      return result;
    }

    final result = _BackupEvent(
      canonical,
      dataset,
      revision(event['origin'], event['sequence']),
      _backupString(event['entity_kind']),
      DurableId.parse(_backupString(event['entity_id'])),
      _backupString(event['operation']),
      _backupNumber(event['audit_at_ms']).toInt(),
      DurableId.parse(_backupString(event['mutation_id'])),
      _backupNumber(event['mutation_index']).toInt(),
      _backupNumber(event['mutation_count']).toInt(),
      references(event['parents'], 1),
      references(event['dependencies'], 2),
      jsonEncode(event['payload']),
    );
    _check(
      ['store', 'receipt', 'product', 'alias'].contains(result.kind) &&
          ['snapshot', 'tombstone'].contains(result.operation) &&
          (result.operation != 'tombstone' || result.kind == 'receipt') &&
          result.count >= 1 &&
          result.count <= 2 &&
          result.index < result.count,
      'invalidBackup',
    );
    _check(
      canonical ==
          _eventJson(
            dataset,
            result.revision,
            result.kind,
            result.id,
            result.payload,
            result.mutation,
            result.index,
            result.count,
            result.auditAt,
            result.parents,
            result.dependencies,
            operation: result.operation,
          ),
      'invalidBackup',
    );
    return result;
  }
}

final class _DecodedBackup {
  _DecodedBackup(this.dataset, this.content, this.counts, this.events);
  final DurableId dataset;
  final Map<String, Object?> content;
  final Map<String, int> counts;
  final List<_BackupEvent> events;
}

_DecodedBackup _decodeBackup(Uint8List bytes) {
  _check(bytes.length <= ReceiptBackupLimits.maxBytes, 'backupTooLarge');
  try {
    _check(
      !(bytes.length >= 3 &&
          bytes[0] == 239 &&
          bytes[1] == 187 &&
          bytes[2] == 191),
      'invalidBackup',
    );
    final text = utf8.decode(bytes);
    final root = _backupObject(jsonDecode(text), [
      'format',
      'format_version',
      'content_sha256',
      'content',
    ]);
    _check(
      root['format'] == 'receipt_reader_backup' &&
          ['1', '2'].contains(root['format_version']),
      'unsupportedBackup',
    );
    _check(jsonEncode(root) == text, 'invalidBackup');
    final content = _backupObject(root['content'], [
      'dataset_id',
      'event_version',
      'counts',
      'events',
      'heads',
    ]);
    _check(content['event_version'] == '1', 'unsupportedBackup');
    _check(
      root['content_sha256'] == _sha(jsonEncode(content)),
      'backupChecksum',
    );
    final dataset = DurableId.parse(_backupString(content['dataset_id']));
    final countKeys = [
      ..._countKeys,
      if (root['format_version'] == '2') ...['products', 'aliases'],
    ];
    final countsObject = _backupObject(content['counts'], countKeys);
    final counts = {
      for (final key in countKeys)
        key: _backupNumber(countsObject[key]).toInt(),
    };
    _check(
      counts.entries.every(
        (e) =>
            e.value <=
            (e.key == 'row_identities'
                ? ReceiptBackupLimits.maxRowIdentities
                : ReceiptBackupLimits.maxEvents),
      ),
      'backupTooLarge',
    );
    _check(
      content['events'] is List && content['heads'] is List,
      'invalidBackup',
    );
    final raw = content['events']! as List;
    final heads = content['heads']! as List;
    _check(
      raw.length <= ReceiptBackupLimits.maxEvents &&
          heads.length <= ReceiptBackupLimits.maxEvents,
      'backupTooLarge',
    );
    _check(
      raw.length == counts['events'] && heads.length == counts['heads'],
      'invalidBackup',
    );
    final events = [
      for (final entry in raw) _BackupEvent.decode(entry, dataset),
    ];
    _check(
      root['format_version'] == '2' ||
          events.every((e) => e.kind == 'store' || e.kind == 'receipt'),
      'unsupportedBackup',
    );
    _check(
      events.map((e) => e.revision.origin).toSet().length <=
          ReceiptBackupLimits.maxOrigins,
      'backupTooLarge',
    );
    return _DecodedBackup(dataset, content, counts, events);
  } on StorageFailure {
    rethrow;
  } catch (_) {
    throw const StorageFailure('invalidBackup');
  }
}

Future<RestoredReceiptBackup> _restoreBackup(
  Uint8List bytes,
  Directory parent,
) async {
  final decoded = _decodeBackup(bytes);
  try {
    return await _stageBackup(decoded, parent);
  } on StorageFailure {
    rethrow;
  } catch (_) {
    throw const StorageFailure('backupStorage');
  }
}

Future<RestoredReceiptBackup> _stageBackup(
  _DecodedBackup backup,
  Directory parent,
) async {
  final resolvedParent = Directory(await parent.resolveSymbolicLinks());
  final directory = await resolvedParent.createTemp('receipt-restore-');
  ReceiptDatabase? database;
  var succeeded = false;
  try {
    final file = File('${directory.path}/receipts.sqlite');
    database = ReceiptDatabase.file(file);
    final repository = ReceiptRepository._(database);
    final origins = backup.events.map((e) => e.revision.origin).toSet();
    var device = DurableId.generate();
    while (origins.contains(device)) {
      device = DurableId.generate();
    }
    final identity = DatasetIdentity(backup.dataset, device, BigInt.one);
    await repository._guard(
      () => repository._db.transaction(() async {
        await repository._rebuildBackup(backup, identity);
        await repository._verifyIntegrity();
        _check(
          jsonEncode(await repository._backupContent()) ==
              jsonEncode(backup.content),
          'backupManifest',
        );
      }),
    );
    await database.close();
    database = null;
    succeeded = true;
    return RestoredReceiptBackup._(
      directory,
      file,
      identity,
      backup.events.length,
      backup.counts['receipts']!,
      backup.counts['deleted_receipts']!,
    );
  } finally {
    try {
      await database?.close();
    } finally {
      if (!succeeded) {
        _check(
          directory.parent.absolute.path == resolvedParent.absolute.path &&
              directory.uri.pathSegments
                  .where((s) => s.isNotEmpty)
                  .last
                  .startsWith('receipt-restore-'),
          'backupCleanup',
        );
        await directory.delete(recursive: true);
      }
    }
  }
}

extension _BackupRepository on ReceiptRepository {
  Future<void> _checkBackupSize() async {
    final sizes = (await _rows(
      'SELECT COUNT(*) AS n, COALESCE(SUM(length(CAST(canonical_event AS BLOB))), 0) AS bytes FROM change_log',
    )).single;
    _check(
      (sizes['n']! as int) <= ReceiptBackupLimits.maxEvents &&
          (sizes['bytes']! as int) <= ReceiptBackupLimits.maxBytes,
      'backupTooLarge',
    );
  }

  Future<Map<String, Object?>> _backupContent() async {
    final events = await _orderedEvents();
    _check(
      events.map((e) => e['origin_device_id']).toSet().length <=
          ReceiptBackupLimits.maxOrigins,
      'backupTooLarge',
    );
    _check(
      events.every(
        (e) =>
            utf8.encode(e['canonical_event']! as String).length <=
            ReceiptBackupLimits.maxEventBytes,
      ),
      'backupTooLarge',
    );
    final heads = await _rows(
      'SELECT * FROM entity_heads ORDER BY entity_kind, entity_id, origin_device_id, origin_seq',
    );
    final countQueries = {
      'events': 'SELECT COUNT(*) AS n FROM change_log',
      'stores': 'SELECT COUNT(*) AS n FROM stores',
      'receipts': 'SELECT COUNT(*) AS n FROM receipts',
      'deleted_receipts':
          'SELECT COUNT(*) AS n FROM receipts WHERE is_deleted = 1',
      'row_identities': 'SELECT COUNT(*) AS n FROM row_identities',
      'heads': 'SELECT COUNT(*) AS n FROM entity_heads',
    };
    final catalogCounts = {
      'products':
          (await _rows('SELECT COUNT(*) AS n FROM products')).single['n']!
              as int,
      'aliases':
          (await _rows('SELECT COUNT(*) AS n FROM product_aliases'))
                  .single['n']!
              as int,
    };
    if (catalogCounts.values.any((n) => n > 0)) {
      countQueries.addAll({
        'products': 'SELECT COUNT(*) AS n FROM products',
        'aliases': 'SELECT COUNT(*) AS n FROM product_aliases',
      });
    }
    final counts = <String, String>{};
    for (final entry in countQueries.entries) {
      final count = (await _rows(entry.value)).single['n']! as int;
      _check(
        count <=
            (entry.key == 'row_identities'
                ? ReceiptBackupLimits.maxRowIdentities
                : ReceiptBackupLimits.maxEvents),
        'backupTooLarge',
      );
      counts[entry.key] = count.toString();
    }
    return {
      'dataset_id': (await _identity()).datasetId.value,
      'event_version': '1',
      'counts': counts,
      'events': [
        for (final event in events)
          {
            'canonical_event': event['canonical_event'],
            'event_sha256': event['event_sha256'],
          },
      ],
      'heads': [
        for (final head in heads)
          {
            'entity_kind': head['entity_kind'],
            'entity_id': head['entity_id'],
            'origin': head['origin_device_id'],
            'sequence': head['origin_seq'].toString(),
          },
      ],
    };
  }

  Future<void> _rebuildBackup(
    _DecodedBackup backup,
    DatasetIdentity identity,
  ) async {
    await _insert('dataset_state', {
      'singleton': 1,
      'dataset_id': identity.datasetId.value,
      'device_id': identity.deviceId.value,
      'next_local_seq': 1,
    });
    final sequences = <DurableId, BigInt>{identity.deviceId: BigInt.zero};
    final owners = <DurableId>{};
    final created = <DurableId, int>{};
    final receipts = <DurableId>{};
    for (final event in backup.events) {
      final previous = sequences[event.revision.origin] ?? BigInt.zero;
      _check(
        event.revision.sequence == previous + BigInt.one,
        'eventContinuity',
      );
      sequences[event.revision.origin] = event.revision.sequence;
      await _appendEvent(
        identity,
        event.revision,
        event.kind,
        event.id,
        event.payload,
        event.mutation,
        event.index,
        event.count,
        event.auditAt,
        event.parents,
        event.dependencies,
        operation: event.operation,
      );
      if (event.kind == 'store') {
        final fields = _backupObject(jsonDecode(event.payload), [
          'id',
          'name',
          'chain',
          'address',
          'printed_identifier',
        ]);
        final branch = ReceiptBranch(
          id: DurableId.parse(_backupString(fields['id'])),
          name: _backupString(fields['name']),
          chain: fields['chain'] as String?,
          address: fields['address'] as String?,
          printedIdentifier: fields['printed_identifier'] as String?,
        );
        _check(
          branch.id == event.id &&
              event.operation == 'snapshot' &&
              _branchPayload(branch) == event.payload,
          'invalidBackup',
        );
        await _insert('stores', {
          'id': branch.id.value,
          'display_name': branch.name,
          'chain': branch.chain,
          'address': branch.address,
          'printed_identifier': branch.printedIdentifier,
          'current_revision_origin': event.revision.origin.value,
          'current_revision_seq': event.revision.sequence.toInt(),
          'created_at_ms': event.auditAt,
          'updated_at_ms': event.auditAt,
        });
      } else if (event.kind == 'product' || event.kind == 'alias') {
        final record = _CatalogRecord.decode(event.kind, event.payload);
        _check(
          record.id == event.id && event.operation == 'snapshot',
          'invalidBackup',
        );
        await _projectCatalog(record, event.revision);
        await _insert(
          'catalog_mutations',
          _catalogMutation(record, event.mutation, event.revision),
        );
      } else {
        final exists = receipts.contains(event.id);
        final first = created.putIfAbsent(event.id, () => event.auditAt);
        await _db.customStatement(
          'DELETE FROM receipt_items WHERE receipt_id = ?',
          [event.id.value],
        );
        await _db.customStatement(
          'DELETE FROM receipt_reviews WHERE receipt_id = ?',
          [event.id.value],
        );
        if (event.operation == 'tombstone') {
          final tombstone = ReceiptTombstoneCodec.decode(event.payload);
          _check(exists && tombstone.receiptId == event.id, 'invalidBackup');
          await _upsertReceipt(
            _tombstoneFields(tombstone, event.revision, first),
            true,
          );
        } else {
          final document = ReceiptDocumentCodec.decode(event.payload);
          _check(document.snapshot.id == event.id, 'invalidBackup');
          await _upsertReceipt(
            _receiptFields(document, event.revision, first),
            exists,
          );
          receipts.add(event.id);
          for (final row in _documentRowIds(document)) {
            if (owners.add(row)) {
              await _insert('row_identities', {
                'row_id': row.value,
                'receipt_id': event.id.value,
                'first_origin': event.revision.origin.value,
                'first_seq': event.revision.sequence.toInt(),
              });
            }
          }
          for (var i = 0; i < document.snapshot.items.length; i++) {
            await _insert('receipt_items', _itemFields(document.snapshot, i));
          }
          await _insert('receipt_reviews', _reviewFields(document));
        }
        if (event.index == event.count - 1) {
          await _insert('local_mutations', {
            'mutation_id': event.mutation.value,
            'command_sha256': _sha(event.payload),
            'receipt_id': event.id.value,
            'result_origin': event.revision.origin.value,
            'result_seq': event.revision.sequence.toInt(),
          });
        }
      }
      await _selectHead(event.kind, event.id, event.revision);
    }
    for (final cursor in sequences.entries) {
      await _insert('received_cursors', {
        'origin_device_id': cursor.key.value,
        'committed_seq': cursor.value.toInt(),
      });
    }
  }
}
