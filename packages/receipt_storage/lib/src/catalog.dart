part of 'repository.dart';

final class StoredProduct {
  const StoredProduct(this.document, this.revision);
  final ProductDocument document;
  final RevisionId revision;
  ReceiptProductLink get link => ReceiptProductLink(
    id: document.product.id,
    storeId: document.product.storeId,
    revision: revision,
  );
}

final class StoredProductAlias {
  const StoredProductAlias(this.document, this.revision);
  final ProductAliasDocument document;
  final RevisionId revision;
}

/// A suggestion only. Callers must obtain review before linking a receipt row.
final class ProductAliasMatch {
  const ProductAliasMatch(this.alias, this.product);
  final StoredProductAlias alias;
  final StoredProduct product;
}

extension ProductCatalog on ReceiptRepository {
  Future<StoredProduct?> readProduct(DurableId id) => _guard(
    () => _db.transaction(() async {
      final record = await _readCatalog('product', id);
      return record == null
          ? null
          : StoredProduct(record.$1.product!, record.$2);
    }),
  );

  Future<StoredProductAlias?> readAlias(DurableId id) => _guard(
    () => _db.transaction(() async {
      final record = await _readCatalog('alias', id);
      return record == null
          ? null
          : StoredProductAlias(record.$1.alias!, record.$2);
    }),
  );

  Future<List<StoredProduct>> products(
    DurableId storeId, {
    int limit = 100,
    int offset = 0,
    String query = '',
  }) {
    _catalogPage(limit, offset);
    return _guard(
      () => _db.transaction(
        () async => List.unmodifiable([
          for (final row in await _catalogSearchRows(
            storeId,
            false,
            false,
            query,
            limit,
            offset,
          ))
            await _product(DurableId.parse(row['id']! as String)),
        ]),
      ),
    );
  }

  Future<List<Map<String, Object?>>> _catalogSearchRows(
    DurableId storeId,
    bool alias,
    bool activeOnly,
    String query,
    int limit,
    int offset,
  ) async {
    final search = TextSearchQuery(query);
    final table = alias ? 'product_aliases' : 'products';
    final name = alias ? 'normalized_name' : 'canonical_name';
    final active = alias && activeOnly ? 'AND is_active = 1' : '';
    if (search.isEmpty) {
      return _rows(
        'SELECT id FROM $table WHERE store_id = ? $active ORDER BY $name, id LIMIT ? OFFSET ?',
        [storeId.value, limit, offset],
      );
    }
    final matches = <Map<String, Object?>>[];
    var skipped = 0;
    String? lastName, lastId;
    while (true) {
      final rows = await _rows(
        'SELECT id, $name AS name FROM $table WHERE store_id = ? $active '
        '${lastId == null ? '' : 'AND ($name, id) > (?, ?) '}ORDER BY $name, id LIMIT 64',
        [
          storeId.value,
          if (lastId != null) ...[lastName!, lastId],
        ],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        lastName = row['name']! as String;
        lastId = row['id']! as String;
        final names = [lastName];
        if (!alias && !search.matches(names)) {
          names.addAll(
            (await _rows(
              'SELECT normalized_name FROM product_aliases WHERE store_id = ? AND product_id = ? AND is_active = 1',
              [storeId.value, lastId],
            )).map((a) => a['normalized_name']! as String),
          );
        }
        if (!search.matches(names)) continue;
        if (skipped++ < offset) continue;
        matches.add(row);
        if (matches.length == limit) return matches;
      }
    }
    return matches;
  }

  Future<List<StoredProductAlias>> aliases(
    DurableId storeId, {
    bool activeOnly = true,
    int limit = 100,
    int offset = 0,
    String query = '',
  }) {
    _catalogPage(limit, offset);
    return _guard(
      () => _db.transaction(
        () async => List.unmodifiable([
          for (final row in await _catalogSearchRows(
            storeId,
            true,
            activeOnly,
            query,
            limit,
            offset,
          ))
            await _alias(DurableId.parse(row['id']! as String)),
        ]),
      ),
    );
  }

  Future<ProductAliasMatch?> matchAlias(
    DurableId storeId,
    String receiptName,
  ) => _guard(
    () => _db.transaction(() async {
      final key = normalizeReceiptNameV1(receiptName);
      final rows = await _rows(
        'SELECT id FROM product_aliases WHERE store_id = ? AND normalized_name = ? AND is_active = 1',
        [storeId.value, key],
      );
      if (rows.isEmpty) return null;
      _check(rows.length == 1, 'aliasCollision');
      final alias = await _alias(DurableId.parse(rows.single['id']! as String));
      return ProductAliasMatch(
        alias,
        await _product(alias.document.alias.productId),
      );
    }),
  );

  Future<SaveResult> saveProduct(
    ProductDocument document, {
    required DurableId mutationId,
  }) => _guard(
    () => _saveCatalog(
      _CatalogRecord.decode('product', ProductDocumentCodec.encode(document)),
      mutationId,
    ),
  );

  Future<SaveResult> saveAlias(
    ProductAliasDocument document, {
    required DurableId mutationId,
  }) => _guard(
    () => _saveCatalog(
      _CatalogRecord.decode(
        'alias',
        ProductAliasDocumentCodec.encode(document),
      ),
      mutationId,
    ),
  );

  Future<StoredProduct> _product(DurableId id) async {
    final record = await _readCatalog('product', id);
    _check(record != null, 'missingProduct');
    return StoredProduct(record!.$1.product!, record.$2);
  }

  Future<StoredProductAlias> _alias(DurableId id) async {
    final record = await _readCatalog('alias', id);
    _check(record != null, 'missingAlias');
    return StoredProductAlias(record!.$1.alias!, record.$2);
  }

  Future<(_CatalogRecord, RevisionId)?> _readCatalog(
    String kind,
    DurableId id,
  ) async {
    final rows = await _rows(
      'SELECT * FROM ${_catalogTable(kind)} WHERE id = ?',
      [id.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single, revision = _revision(rows.single);
    final events = await _rows(
      'SELECT * FROM change_log WHERE origin_device_id = ? AND origin_seq = ?',
      [revision.origin.value, revision.sequence.toInt()],
    );
    _check(
      events.length == 1 &&
          events.single['entity_kind'] == kind &&
          events.single['entity_id'] == id.value &&
          events.single['operation'] == 'snapshot',
      'catalogEvent',
    );
    final record = _CatalogRecord.decode(
      kind,
      events.single['payload']! as String,
    );
    _check(
      record.id == id &&
          _sameFields(
            row,
            record.fields(revision, row['created_at_ms']! as int),
          ),
      'catalogProjection',
    );
    final heads = await _heads(kind, id);
    _check(heads.length == 1 && heads.single == revision, 'catalogHeads');
    return (record, revision);
  }

  Future<SaveResult> _saveCatalog(_CatalogRecord record, DurableId mutation) =>
      _guard(
        () => _db.transaction(() async {
          _check(
            (await _rows(
              'SELECT 1 FROM local_mutations WHERE mutation_id = ?',
              [mutation.value],
            )).isEmpty,
            'mutationIdentityReused',
          );
          final retry = await _rows(
            'SELECT * FROM catalog_mutations WHERE mutation_id = ?',
            [mutation.value],
          );
          if (retry.isNotEmpty) {
            final row = retry.single;
            _check(
              row['command_sha256'] == _sha(record.payload) &&
                  row['entity_kind'] == record.kind &&
                  row['entity_id'] == record.id.value,
              'mutationIdentityReused',
            );
            final revision = RevisionId(
              DurableId.parse(row['result_origin']! as String),
              BigInt.from(row['result_seq']! as int),
            );
            final event = await _rows(
              'SELECT payload FROM change_log WHERE origin_device_id = ? AND origin_seq = ?',
              [revision.origin.value, revision.sequence.toInt()],
            );
            _check(
              event.length == 1 && event.single['payload'] == record.payload,
              'retryEvent',
            );
            return SaveResult(revision, replayed: true);
          }
          final current = await _readCatalog(record.kind, record.id);
          _check(record.expectedHead == current?.$2, 'staleCatalog');
          if (current == null) {
            _check(
              (await _rows(
                'SELECT 1 FROM change_log WHERE entity_kind = ? AND entity_id = ? LIMIT 1',
                [record.kind, record.id.value],
              )).isEmpty,
              'catalogHistory',
            );
          }
          if (current != null) record.checkOwnership(current.$1);
          final branch = await _rows('SELECT * FROM stores WHERE id = ?', [
            record.storeId.value,
          ]);
          final branchHeads = await _heads('store', record.storeId);
          _check(
            branch.length == 1 &&
                _revision(branch.single) == record.storeRevision &&
                branchHeads.length == 1 &&
                branchHeads.single == record.storeRevision,
            'staleBranch',
          );
          if (record.alias case final alias?) {
            final product = await _product(alias.alias.productId);
            _check(
              product.document.product.storeId == record.storeId,
              'crossStoreProduct',
            );
            _check(product.revision == alias.productRevision, 'staleProduct');
            if (alias.alias.isActive) {
              final collisions = await _rows(
                'SELECT id FROM product_aliases WHERE store_id = ? AND normalized_name = ? AND is_active = 1 AND id <> ?',
                [
                  record.storeId.value,
                  alias.alias.normalizedName,
                  record.id.value,
                ],
              );
              _check(collisions.isEmpty, 'aliasCollision');
            }
          }
          final state = await _identity();
          final next = state.nextLocalSequence + BigInt.one;
          _check(next <= sqliteInt64Max, 'sequenceExhausted');
          final revision = RevisionId(state.deviceId, state.nextLocalSequence);
          await _db.customStatement(
            'UPDATE dataset_state SET next_local_seq = ? WHERE singleton = 1',
            [next.toInt()],
          );
          await _appendEvent(
            state,
            revision,
            record.kind,
            record.id,
            record.payload,
            mutation,
            0,
            1,
            record.auditAt,
            [if (record.expectedHead != null) record.expectedHead!],
            record.dependencies,
          );
          await _projectCatalog(record, revision);
          await _selectHead(record.kind, record.id, revision);
          await _db.customStatement(
            'UPDATE received_cursors SET committed_seq = ? WHERE origin_device_id = ?',
            [revision.sequence.toInt(), state.deviceId.value],
          );
          await _insert(
            'catalog_mutations',
            _catalogMutation(record, mutation, revision),
          );
          await _readCatalog(record.kind, record.id);
          return SaveResult(revision, replayed: false);
        }),
      );

  Future<void> _projectCatalog(
    _CatalogRecord record,
    RevisionId revision,
  ) async {
    final table = _catalogTable(record.kind);
    final current = await _rows(
      'SELECT created_at_ms FROM $table WHERE id = ?',
      [record.id.value],
    );
    final fields = record.fields(
      revision,
      current.isEmpty
          ? record.auditAt
          : current.single['created_at_ms']! as int,
    );
    if (current.isEmpty) {
      await _insert(table, fields);
    } else {
      final keys = fields.keys.where((k) => k != 'id').toList();
      await _db.customStatement(
        'UPDATE $table SET ${keys.map((k) => '$k = ?').join(', ')} WHERE id = ?',
        [...keys.map((k) => fields[k]), record.id.value],
      );
    }
  }
}

void _catalogPage(int limit, int offset) {
  if (limit < 1 || limit > 200 || offset < 0) {
    throw ArgumentError('invalid_catalog_page');
  }
}

String _catalogTable(String kind) =>
    kind == 'product' ? 'products' : 'product_aliases';

Map<String, Object?> _catalogMutation(
  _CatalogRecord record,
  DurableId mutation,
  RevisionId revision,
) => {
  'mutation_id': mutation.value,
  'command_sha256': _sha(record.payload),
  'entity_kind': record.kind,
  'entity_id': record.id.value,
  'result_origin': revision.origin.value,
  'result_seq': revision.sequence.toInt(),
};

final class _CatalogRecord {
  _CatalogRecord._(this.kind, this.payload, this.product, this.alias);
  factory _CatalogRecord.decode(String kind, String payload) {
    _check(kind == 'product' || kind == 'alias', 'unsupportedEvent');
    return _CatalogRecord._(
      kind,
      payload,
      kind == 'product' ? ProductDocumentCodec.decode(payload) : null,
      kind == 'alias' ? ProductAliasDocumentCodec.decode(payload) : null,
    );
  }
  final String kind, payload;
  final ProductDocument? product;
  final ProductAliasDocument? alias;
  DurableId get id => product?.product.id ?? alias!.alias.id;
  DurableId get storeId => product?.product.storeId ?? alias!.alias.storeId;
  RevisionId get storeRevision =>
      product?.storeRevision ?? alias!.storeRevision;
  RevisionId? get expectedHead =>
      product != null ? product!.expectedHead : alias!.expectedHead;
  int get auditAt => (product?.reviewedAtMs ?? alias!.reviewedAtMs).toInt();
  List<RevisionId> get dependencies => [
    storeRevision,
    if (alias != null) alias!.productRevision,
  ];
  void checkOwnership(_CatalogRecord before) {
    _check(storeId == before.storeId, 'catalogOwnership');
    if (alias != null) {
      _check(
        alias!.alias.normalizedName == before.alias!.alias.normalizedName,
        'aliasKeyChanged',
      );
    }
  }

  Map<String, Object?> fields(RevisionId revision, int created) => {
    'id': id.value,
    'store_id': storeId.value,
    if (product != null) ...{
      'canonical_name': product!.product.canonicalName,
      'package_value': product!.product.packageValue?.toInt(),
      'package_scale': product!.product.packageScale,
      'package_unit': product!.product.packageUnit?.name,
    } else ...{
      'normalized_name': alias!.alias.normalizedName,
      'normalizer_version': 1,
      'product_id': alias!.alias.productId.value,
      'is_active': alias!.alias.isActive ? 1 : 0,
    },
    'current_revision_origin': revision.origin.value,
    'current_revision_seq': revision.sequence.toInt(),
    'created_at_ms': created,
    'updated_at_ms': auditAt,
  };
}
