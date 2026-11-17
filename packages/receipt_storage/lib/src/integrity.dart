part of 'repository.dart';

extension _Integrity on ReceiptRepository {
  /// Audits complete local/recovered history. Multiple historical origins are
  /// supported for explicit restore; there is no incoming sync/conflict API.
  Future<void> _verifyIntegrity() async {
    final integrity = await _rows('PRAGMA integrity_check');
    _check(
      integrity.length == 1 && integrity.single.values.single == 'ok',
      'sqliteIntegrity',
    );
    _check((await _rows('PRAGMA foreign_key_check')).isEmpty, 'foreignKeys');
    final state = await _identity();
    final events = await _orderedEvents();
    final sequences = <DurableId, BigInt>{};
    final latest = <String, RevisionId>{};
    final documents = <DurableId, ReceiptDocument>{};
    final deletions = <DurableId, ReceiptTombstone>{};
    final firstReceiptTimes = <DurableId, int>{};
    final storePayloads = <DurableId, String>{};
    final catalog = <String, _CatalogRecord>{};
    final catalogCreated = <String, int>{};
    final activeAliasKeys = <String, DurableId>{};
    final knownRevisions = <RevisionId, Map<String, Object?>>{};
    final groups = <String, List<Map<String, Object?>>>{};
    final rowOwners = <DurableId, (DurableId, RevisionId)>{};
    final activeRows = <DurableId, Set<DurableId>>{};
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final revision = RevisionId(
        DurableId.parse(event['origin_device_id']! as String),
        BigInt.from(event['origin_seq']! as int),
      );
      _check(
        revision.sequence ==
                (sequences[revision.origin] ?? BigInt.zero) + BigInt.one &&
            event['dataset_id'] == state.datasetId.value,
        'eventContinuity',
      );
      sequences[revision.origin] = revision.sequence;
      final id = DurableId.parse(event['entity_id']! as String);
      final kind = event['entity_kind']! as String;
      final parents = await _references('revision_parents', 'parent', revision);
      final dependencies = await _references(
        'event_dependencies',
        'dependency',
        revision,
      );
      final key = '$kind:${id.value}';
      final previous = latest[key];
      _check(
        previous == null
            ? parents.isEmpty
            : parents.length == 1 && parents.single == previous,
        'eventAncestry',
      );
      _check(
        parents.every(knownRevisions.containsKey) &&
            dependencies.every(knownRevisions.containsKey),
        'missingHistory',
      );
      final mutation = DurableId.parse(event['mutation_id']! as String);
      final payload = event['payload']! as String;
      final canonical = _eventJson(
        state.datasetId,
        revision,
        kind,
        id,
        payload,
        mutation,
        event['mutation_index']! as int,
        event['mutation_count']! as int,
        event['audit_at_ms']! as int,
        parents,
        dependencies,
        operation: event['operation']! as String,
      );
      _check(
        canonical == event['canonical_event'] &&
            _sha(canonical) == event['event_sha256'],
        'eventDigest',
      );
      _check(
        event['payload_version'] == 1 &&
            ['snapshot', 'tombstone'].contains(event['operation']),
        'unsupportedEvent',
      );
      if (kind == 'store') {
        _check(
          previous == null &&
              dependencies.isEmpty &&
              event['operation'] == 'snapshot',
          'unsupportedCatalogEdit',
        );
        final fields = jsonDecode(payload) as Map<String, Object?>;
        final branch = ReceiptBranch(
          id: DurableId.parse(fields['id']! as String),
          name: fields['name']! as String,
          chain: fields['chain'] as String?,
          address: fields['address'] as String?,
          printedIdentifier: fields['printed_identifier'] as String?,
        );
        _check(
          branch.id == id && _branchPayload(branch) == payload,
          'storePayload',
        );
        storePayloads[id] = payload;
      } else if (kind == 'product' || kind == 'alias') {
        _check(
          event['operation'] == 'snapshot' &&
              event['mutation_count'] == 1 &&
              event['mutation_index'] == 0,
          'catalogMutationShape',
        );
        final record = _CatalogRecord.decode(kind, payload);
        _check(
          record.id == id &&
              record.auditAt == event['audit_at_ms'] &&
              record.expectedHead == previous,
          'catalogPayload',
        );
        if (catalog[key] != null) record.checkOwnership(catalog[key]!);
        _check(
          dependencies.length == record.dependencies.length &&
              record.dependencies.every(dependencies.contains),
          'catalogDependencies',
        );
        final store = knownRevisions[record.storeRevision]!;
        _check(
          store['entity_kind'] == 'store' &&
              store['entity_id'] == record.storeId.value,
          'branchDependency',
        );
        if (record.alias case final alias?) {
          final productEvent = knownRevisions[alias.productRevision]!;
          _check(
            productEvent['entity_kind'] == 'product' &&
                productEvent['entity_id'] == alias.alias.productId.value,
            'productDependency',
          );
          final product = ProductDocumentCodec.decode(
            productEvent['payload']! as String,
          );
          _check(
            product.product.storeId == record.storeId,
            'crossStoreProduct',
          );
          final aliasKey =
              '${record.storeId.value}:${alias.alias.normalizedName}';
          if (activeAliasKeys[aliasKey] == id) activeAliasKeys.remove(aliasKey);
          if (alias.alias.isActive) {
            _check(!activeAliasKeys.containsKey(aliasKey), 'aliasCollision');
            activeAliasKeys[aliasKey] = id;
          }
        }
        catalog[key] = record;
        catalogCreated.putIfAbsent(key, () => record.auditAt);
      } else if (event['operation'] == 'tombstone') {
        _check(
          kind == 'receipt' &&
              !deletions.containsKey(id) &&
              documents.containsKey(id),
          'invalidDeletion',
        );
        final tombstone = ReceiptTombstoneCodec.decode(payload);
        _check(
          tombstone.receiptId == id &&
              tombstone.expectedHead == previous &&
              tombstone.documentSha256 == documents[id]!.sha256Hex &&
              tombstone.source == documents[id]!.review.source &&
              tombstone.deletedAtMs ==
                  BigInt.from(event['audit_at_ms']! as int) &&
              dependencies.isEmpty &&
              event['mutation_count'] == 1 &&
              event['mutation_index'] == 0,
          'tombstonePayload',
        );
        deletions[id] = tombstone;
        activeRows[id] = <DurableId>{};
      } else {
        _check(kind == 'receipt', 'unsupportedEvent');
        _check(!deletions.containsKey(id), 'historicalResurrection');
        final document = ReceiptDocumentCodec.decode(payload);
        final snapshot = document.snapshot;
        _check(
          snapshot.id == id &&
              snapshot.items.every((row) => row.product == null) &&
              document.review.reviewedAtMs ==
                  BigInt.from(event['audit_at_ms']! as int),
          'receiptPayload',
        );
        final expected = document.review.expectedHeads;
        _check(
          expected.length == parents.length && expected.every(parents.contains),
          'reviewParents',
        );
        _check(dependencies.length == 1, 'receiptDependencies');
        final branchRevision = dependencies.single;
        final branchEvent = knownRevisions[branchRevision]!;
        _check(
          branchEvent['entity_kind'] == 'store' &&
              branchEvent['entity_id'] == snapshot.branch.id.value &&
              storePayloads[snapshot.branch.id] ==
                  _branchPayload(snapshot.branch),
          'branchDependency',
        );
        _check(
          snapshot.branch.revision == null ||
              snapshot.branch.revision == branchRevision,
          'branchRevision',
        );
        if (snapshot.branch.revision == null) {
          _check(
            branchEvent['mutation_id'] == event['mutation_id'],
            'pendingBranchDependency',
          );
        }
        _check(
          documents[id] == null ||
              documents[id]!.review.source == document.review.source,
          'historicalProvenanceChange',
        );
        final before = activeRows[id] ?? <DurableId>{};
        for (final rowId in _documentRowIds(document)) {
          final owner = rowOwners[rowId];
          _check(
            owner == null || (owner.$1 == id && before.contains(rowId)),
            'historicalRowReuse',
          );
          rowOwners.putIfAbsent(rowId, () => (id, revision));
        }
        activeRows[id] = _documentRowIds(document);
        documents[id] = document;
        firstReceiptTimes.putIfAbsent(id, () => event['audit_at_ms']! as int);
      }
      latest[key] = revision;
      knownRevisions[revision] = event;
      groups.putIfAbsent(mutation.value, () => []).add(event);
    }
    _check(
      state.nextLocalSequence ==
          (sequences[state.deviceId] ?? BigInt.zero) + BigInt.one,
      'nextSequence',
    );
    final cursors = await _rows('SELECT * FROM received_cursors');
    final expectedCursors = {state.deviceId: BigInt.zero, ...sequences};
    _check(cursors.length == expectedCursors.length, 'committedCursor');
    for (final cursor in cursors) {
      _check(
        expectedCursors[DurableId.parse(
              cursor['origin_device_id']! as String,
            )] ==
            BigInt.from(cursor['committed_seq']! as int),
        'committedCursor',
      );
    }
    final allHeads = await _rows('SELECT * FROM entity_heads');
    _check(allHeads.length == latest.length, 'headCount');
    for (final head in allHeads) {
      _check(
        latest['${head['entity_kind']}:${head['entity_id']}'] ==
            RevisionId(
              DurableId.parse(head['origin_device_id']! as String),
              BigInt.from(head['origin_seq']! as int),
            ),
        'headProjection',
      );
    }
    final stores = await _rows('SELECT * FROM stores');
    _check(stores.length == storePayloads.length, 'storeCount');
    for (final store in stores) {
      final branch = _branch(store);
      _check(
        _branchPayload(branch) == storePayloads[branch.id] &&
            branch.revision == latest['store:${branch.id.value}'],
        'storeProjection',
      );
      final event = knownRevisions[branch.revision]!;
      _check(
        store['created_at_ms'] == event['audit_at_ms'] &&
            store['updated_at_ms'] == event['audit_at_ms'],
        'storeAudit',
      );
    }
    for (final kind in ['product', 'alias']) {
      final rows = await _rows('SELECT * FROM ${_catalogTable(kind)}');
      _check(
        rows.length == catalog.values.where((v) => v.kind == kind).length,
        'catalogCount',
      );
      for (final row in rows) {
        final id = DurableId.parse(row['id']! as String),
            key = '$kind:${row['id']}';
        final record = catalog[key];
        _check(
          record != null &&
              _sameFields(
                row,
                record.fields(latest[key]!, catalogCreated[key]!),
              ),
          'catalogProjection',
        );
        await _readCatalog(kind, id);
      }
    }
    final receipts = await _rows(
      'SELECT id, created_at_ms, is_deleted FROM receipts',
    );
    _check(receipts.length == documents.length, 'receiptCount');
    for (final receipt in receipts) {
      final id = DurableId.parse(receipt['id']! as String);
      _check(
        receipt['is_deleted'] == (deletions.containsKey(id) ? 1 : 0),
        'deletionProjection',
      );
      await _read(id);
      _check(receipt['created_at_ms'] == firstReceiptTimes[id], 'receiptAudit');
    }
    final identities = await _rows('SELECT * FROM row_identities');
    _check(identities.length == rowOwners.length, 'rowIdentityCount');
    for (final identity in identities) {
      final owner = rowOwners[DurableId.parse(identity['row_id']! as String)];
      _check(
        owner != null &&
            owner.$1.value == identity['receipt_id'] &&
            owner.$2.origin.value == identity['first_origin'] &&
            owner.$2.sequence == BigInt.from(identity['first_seq']! as int),
        'rowOwnership',
      );
    }
    final mutations = [
      ...await _rows('SELECT * FROM local_mutations'),
      ...await _rows('SELECT * FROM catalog_mutations'),
    ];
    _check(mutations.length == groups.length, 'mutationCount');
    for (final mutation in mutations) {
      final group = groups[mutation['mutation_id']];
      _check(group != null && group.isNotEmpty, 'mutationGroup');
      final members = group!;
      _check(
        members.length == members.first['mutation_count'],
        'incompleteMutation',
      );
      for (var i = 0; i < members.length; i++) {
        _check(
          members[i]['origin_device_id'] == members.first['origin_device_id'] &&
              members[i]['mutation_index'] == i &&
              members[i]['mutation_count'] == members.length &&
              members[i]['origin_seq'] ==
                  (members.first['origin_seq']! as int) + i,
          'mutationOrder',
        );
      }
      final last = members.last;
      final kind = mutation['entity_kind'] ?? 'receipt';
      _check(
        last['entity_kind'] == kind &&
            last['entity_id'] ==
                (mutation['entity_id'] ?? mutation['receipt_id']) &&
            last['origin_device_id'] == mutation['result_origin'] &&
            last['origin_seq'] == mutation['result_seq'] &&
            _sha(last['payload']! as String) == mutation['command_sha256'],
        'mutationResult',
      );
      _check(
        members.length == 1 ||
            (kind == 'receipt' && members.first['entity_kind'] == 'store'),
        'mutationShape',
      );
      if (members.length == 2) {
        final receipt = ReceiptDocumentCodec.decode(last['payload']! as String)
            .snapshot;
        _check(
          members.first['entity_id'] == receipt.branch.id.value &&
              receipt.branch.revision == null,
          'mutationBranch',
        );
      }
    }
  }

  /// Stable topological order includes the implicit previous sequence on every
  /// origin stream. Neither row insertion order nor audit clocks choose heads.
  Future<List<Map<String, Object?>>> _orderedEvents() async {
    final rows = await _rows('SELECT * FROM change_log');
    final nodes = <RevisionId, Map<String, Object?>>{};
    final needs = <RevisionId, Set<RevisionId>>{};
    for (final row in rows) {
      final revision = RevisionId(
        DurableId.parse(row['origin_device_id']! as String),
        BigInt.from(row['origin_seq']! as int),
      );
      nodes[revision] = row;
      needs[revision] = {
        if (revision.sequence > BigInt.one)
          RevisionId(revision.origin, revision.sequence - BigInt.one),
      };
    }
    for (final pair in [
      ('revision_parents', 'parent'),
      ('event_dependencies', 'dependency'),
    ]) {
      for (final row in await _rows('SELECT * FROM ${pair.$1}')) {
        final child = RevisionId(
          DurableId.parse(row['child_origin']! as String),
          BigInt.from(row['child_seq']! as int),
        );
        final target = RevisionId(
          DurableId.parse(row['${pair.$2}_origin']! as String),
          BigInt.from(row['${pair.$2}_seq']! as int),
        );
        _check(needs.containsKey(child), 'missingHistory');
        needs[child]!.add(target);
      }
    }
    final dependents = <RevisionId, List<RevisionId>>{};
    final ready = SplayTreeMap<RevisionId, Map<String, Object?>>();
    for (final entry in needs.entries) {
      for (final target in entry.value) {
        _check(nodes.containsKey(target), 'missingHistory');
        dependents.putIfAbsent(target, () => []).add(entry.key);
      }
      if (entry.value.isEmpty) ready[entry.key] = nodes[entry.key]!;
    }
    final ordered = <Map<String, Object?>>[];
    while (ready.isNotEmpty) {
      final revision = ready.firstKey()!;
      ordered.add(ready.remove(revision)!);
      for (final child in dependents[revision] ?? <RevisionId>[]) {
        needs[child]!.remove(revision);
        if (needs[child]!.isEmpty) ready[child] = nodes[child]!;
      }
    }
    _check(ordered.length == rows.length, 'cyclicHistory');
    return ordered;
  }

  Future<List<RevisionId>> _references(
    String table,
    String prefix,
    RevisionId revision,
  ) async =>
      (await _rows(
            'SELECT ${prefix}_origin AS origin, ${prefix}_seq AS seq FROM $table WHERE child_origin = ? AND child_seq = ? ORDER BY origin, seq',
            [revision.origin.value, revision.sequence.toInt()],
          ))
          .map(
            (row) => RevisionId(
              DurableId.parse(row['origin']! as String),
              BigInt.from(row['seq']! as int),
            ),
          )
          .toList();
}
