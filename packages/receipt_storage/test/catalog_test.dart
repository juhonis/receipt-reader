import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'catalog_support.dart';
import 'support.dart';

Matcher failure(String code) =>
    throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));

Uint8List tamper(Uint8List bytes, void Function(Map<String, dynamic>) change) {
  final backup = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  change(backup);
  for (final entry in backup['content']['events'] as List) {
    entry['event_sha256'] = sha256
        .convert(utf8.encode(entry['canonical_event'] as String))
        .toString();
  }
  backup['content_sha256'] = sha256
      .convert(utf8.encode(jsonEncode(backup['content'])))
      .toString();
  return utf8.encode(jsonEncode(backup));
}

void changeCatalogEvent(
  Map<String, dynamic> backup,
  int index,
  void Function(Map<String, dynamic>) change,
) {
  final entry = backup['content']['events'][index] as Map<String, dynamic>;
  final event =
      jsonDecode(entry['canonical_event'] as String) as Map<String, dynamic>;
  change(event);
  entry['canonical_event'] = jsonEncode(event);
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  late ReceiptBranch branch;
  setUp(() async {
    h = await Harness.create();
    await h.repository.saveManual(command(snapshot()));
    branch = (await h.repository.branches()).single;
  });
  tearDown(() => h.dispose());

  test(
    'exact aliases suggest a branch-owned product without changing receipts',
    () async {
      final before = (await h.repository.read(id(1)))!;
      expect(await h.repository.products(branch.id), isEmpty);
      expect(await h.repository.matchAlias(branch.id, 'TEST MILK'), isNull);
      final saved = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final alias = await h.repository.saveAlias(
        aliasDocument(branch, saved.revision),
        mutationId: id(13),
      );
      final match = (await h.repository.matchAlias(
        branch.id,
        '  TEST\tMILK  ',
      ))!;
      expect(match.product.revision, saved.revision);
      expect(match.product.link.storeId, branch.id);
      expect(match.alias.revision, alias.revision);
      expect(await h.repository.matchAlias(id(90), 'TEST MILK'), isNull);
      expect(await h.repository.matchAlias(branch.id, 'TEST MILK 1L'), isNull);
      expect((await h.repository.read(id(1)))!.revision, before.revision);
      expect(
        (await h.repository.read(id(1)))!
            .document
            .snapshot
            .items
            .single
            .product,
        isNull,
      );
      await h.reopen();
      expect(
        (await h.repository.products(branch.id)).single.document.product.id,
        id(10),
      );
      expect(
        (await h.repository.aliases(branch.id)).single.document.alias.id,
        id(11),
      );
      await h.repository.verifyIntegrity();
    },
  );

  test(
    'same product names remain separate identities, even within one branch',
    () async {
      await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      await h.repository.saveProduct(
        productDocument(branch, number: 20),
        mutationId: id(21),
      );
      expect((await h.repository.products(branch.id)).length, 2);
      expect(
        (await h.repository.products(
          branch.id,
          limit: 1,
          offset: 1,
        )).single.document.product.id,
        id(20),
      );
      expect(await h.repository.readProduct(id(99)), isNull);
      expect(await h.repository.readAlias(id(99)), isNull);
      expect(
        () => h.repository.products(branch.id, limit: 201),
        throwsArgumentError,
      );
      expect(
        () => h.repository.aliases(branch.id, offset: -1),
        throwsArgumentError,
      );
    },
  );

  test('product edits preserve history, reject stale heads and replay original retries', () async {
    final original = productDocument(branch);
    final first = await h.repository.saveProduct(original, mutationId: id(12));
    final edited = productDocument(
      branch,
      name: 'CORRECTED MILK',
      head: first.revision,
      at: 900,
    );
    final next = await h.repository.saveProduct(edited, mutationId: id(13));
    expect(next.revision.sequence, first.revision.sequence + BigInt.one);
    expect(
      (await h.repository.saveProduct(original, mutationId: id(12))).replayed,
      isTrue,
    );
    expect(
      (await h.repository.readProduct(id(10)))!.document.product.canonicalName,
      'CORRECTED MILK',
    );
    await expectLater(
      h.repository.saveProduct(edited, mutationId: id(14)),
      failure('staleCatalog'),
    );
    await expectLater(
      h.repository.saveProduct(original, mutationId: id(13)),
      failure('mutationIdentityReused'),
    );
    final row = h.raw.select('SELECT * FROM products').single;
    expect(row['created_at_ms'], 1000);
    expect(row['updated_at_ms'], 900); // Audit clocks do not choose revisions.
    expect(h.count('revision_parents'), 1);
    await h.reopen();
    await h.repository.verifyIntegrity();
  });

  test(
    'aliases can be reviewed, deactivated, reassigned and reactivated',
    () async {
      final first = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final second = await h.repository.saveProduct(
        productDocument(branch, number: 20),
        mutationId: id(21),
      );
      final alias = await h.repository.saveAlias(
        aliasDocument(branch, first.revision),
        mutationId: id(13),
      );
      final off = await h.repository.saveAlias(
        aliasDocument(
          branch,
          first.revision,
          active: false,
          head: alias.revision,
        ),
        mutationId: id(14),
      );
      expect(await h.repository.matchAlias(branch.id, 'test milk'), isNull);
      expect(await h.repository.aliases(branch.id), isEmpty);
      expect(
        (await h.repository.aliases(branch.id, activeOnly: false)).length,
        1,
      );
      await h.repository.saveAlias(
        aliasDocument(branch, second.revision, product: 20, head: off.revision),
        mutationId: id(15),
      );
      expect(
        (await h.repository.matchAlias(
          branch.id,
          'test milk',
        ))!.product.document.product.id,
        id(20),
      );
      expect(
        (await h.repository.saveAlias(
          aliasDocument(branch, first.revision),
          mutationId: id(13),
        )).replayed,
        isTrue,
      );
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(branch, first.revision),
          mutationId: id(16),
        ),
        failure('staleCatalog'),
      );
      await h.reopen();
    },
  );

  test(
    'active alias collisions fail without silently replacing either identity',
    () async {
      final product = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final first = await h.repository.saveAlias(
        aliasDocument(branch, product.revision),
        mutationId: id(13),
      );
      final identity = await h.repository.identity();
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(branch, product.revision, number: 20),
          mutationId: id(21),
        ),
        failure('aliasCollision'),
      );
      expect(
        (await h.repository.identity()).nextLocalSequence,
        identity.nextLocalSequence,
      );
      final second = await h.repository.saveAlias(
        aliasDocument(branch, product.revision, number: 20, active: false),
        mutationId: id(21),
      );
      await h.repository.saveAlias(
        aliasDocument(
          branch,
          product.revision,
          active: false,
          head: first.revision,
        ),
        mutationId: id(14),
      );
      await h.repository.saveAlias(
        aliasDocument(
          branch,
          product.revision,
          number: 20,
          head: second.revision,
        ),
        mutationId: id(22),
      );
      final off = (await h.repository.readAlias(id(11)))!;
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(branch, product.revision, head: off.revision),
          mutationId: id(15),
        ),
        failure('aliasCollision'),
      );
      expect(
        (await h.repository.matchAlias(
          branch.id,
          'test milk',
        ))!.alias.document.alias.id,
        id(20),
      );
      await h.repository.verifyIntegrity();
    },
  );

  test(
    'branch ownership, alias keys and dependency revisions cannot drift',
    () async {
      await h.repository.saveManual(
        command(
          snapshot(
            number: 30,
            branch: ReceiptBranch(id: id(31), name: 'OTHER BRANCH'),
            items: [row(number: 32)],
          ),
          mutation: 33,
        ),
      );
      final other = (await h.repository.branches()).firstWhere(
        (b) => b.id == id(31),
      );
      final product = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(other, product.revision),
          mutationId: id(13),
        ),
        failure('crossStoreProduct'),
      );
      await expectLater(
        h.repository.saveProduct(
          productDocument(other, head: product.revision),
          mutationId: id(14),
        ),
        failure('catalogOwnership'),
      );
      final alias = await h.repository.saveAlias(
        aliasDocument(branch, product.revision),
        mutationId: id(13),
      );
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(
            branch,
            product.revision,
            name: 'other name',
            head: alias.revision,
          ),
          mutationId: id(14),
        ),
        failure('aliasKeyChanged'),
      );
      final changed = await h.repository.saveProduct(
        productDocument(branch, head: product.revision, name: 'NEW NAME'),
        mutationId: id(15),
      );
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(branch, product.revision, head: alias.revision),
          mutationId: id(16),
        ),
        failure('staleProduct'),
      );
      expect(
        (await h.repository.matchAlias(
          branch.id,
          'test milk',
        ))!.product.revision,
        changed.revision,
      );
      final missing = ReceiptBranch(
        id: id(99),
        name: 'MISSING',
        revision: branch.revision,
      );
      await expectLater(
        h.repository.saveProduct(
          productDocument(missing, number: 90),
          mutationId: id(17),
        ),
        failure('staleBranch'),
      );
      final stale = ReceiptBranch(
        id: branch.id,
        name: branch.name,
        revision: product.revision,
      );
      await expectLater(
        h.repository.saveProduct(
          productDocument(stale, number: 90),
          mutationId: id(17),
        ),
        failure('staleBranch'),
      );
      await h.reopen();
    },
  );

  test('SQL enforces branch references, package groups, active uniqueness and immutable retry rows', () async {
    final product = await h.repository.saveProduct(
      productDocument(branch),
      mutationId: id(12),
    );
    await h.repository.saveAlias(
      aliasDocument(branch, product.revision),
      mutationId: id(13),
    );
    for (final sql in [
      'UPDATE product_aliases SET store_id = ?1',
      'UPDATE product_aliases SET product_id = ?1',
      'UPDATE products SET store_id = ?1',
    ]) {
      expect(
        () => h.raw.execute(sql, [id(99).value]),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    for (final sql in [
      'UPDATE products SET package_value = 1',
      "UPDATE products SET package_value = 1, package_scale = 0, package_unit = 'unknown'",
      "UPDATE products SET package_value = 0, package_scale = 0, package_unit = 'kg'",
      'UPDATE product_aliases SET normalizer_version = 2',
      'UPDATE product_aliases SET is_active = 2',
      "UPDATE catalog_mutations SET command_sha256 = '${'0' * 64}'",
      'DELETE FROM catalog_mutations',
    ]) {
      expect(
        () => h.raw.execute(sql),
        throwsA(isA<sqlite.SqliteException>()),
        reason: sql,
      );
    }
    await h.repository.verifyIntegrity();
  });

  test(
    'mutation IDs are unique across receipts, products, aliases and deletions',
    () async {
      await expectLater(
        h.repository.saveProduct(productDocument(branch), mutationId: id(4)),
        failure('mutationIdentityReused'),
      );
      final product = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      await expectLater(
        h.repository.saveAlias(
          aliasDocument(branch, product.revision),
          mutationId: id(12),
        ),
        failure('mutationIdentityReused'),
      );
      await expectLater(
        h.repository.saveManual(command(snapshot(), mutation: 12)),
        failure('mutationIdentityReused'),
      );
      final receipt = (await h.repository.read(id(1)))!;
      final deletion = ReceiptDeletionChecks(
        document: receipt.document,
        expectedHead: receipt.revision,
        mutationId: id(12),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(2000), appVersion: 'catalog-test');
      await expectLater(
        h.repository.deleteReceipt(deletion),
        failure('mutationIdentityReused'),
      );
      await h.repository.verifyIntegrity();
    },
  );

  test('encrypted catalog backups preserve all immutable events and retry identities', () async {
    final product = productDocument(branch);
    final saved = await h.repository.saveProduct(product, mutationId: id(12));
    final alias = aliasDocument(branch, saved.revision);
    final created = await h.repository.saveAlias(alias, mutationId: id(13));
    await h.repository.saveAlias(
      aliasDocument(
        branch,
        saved.revision,
        active: false,
        head: created.revision,
      ),
      mutationId: id(14),
    );
    final bytes = await h.repository.exportBackup();
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(map['format_version'], '2');
    expect(map['content']['counts']['products'], '1');
    expect(map['content']['counts']['aliases'], '1');
    final encrypted = await ProtectedBackup.encrypt(
      bytes,
      'synthetic test password',
    );
    final restored = await ReceiptRepository.restoreBackup(
      await ProtectedBackup.decrypt(encrypted, 'synthetic test password'),
      stagingParent: h.directory,
    );
    final recovered = await ReceiptRepository.open(restored.databaseFile);
    try {
      expect(await recovered.exportBackup(), bytes);
      expect(
        (await recovered.saveProduct(product, mutationId: id(12))).replayed,
        isTrue,
      );
      expect(
        (await recovered.saveAlias(alias, mutationId: id(13))).replayed,
        isTrue,
      );
      expect(await recovered.matchAlias(branch.id, 'test milk'), isNull);
      final edited = await recovered.saveProduct(
        productDocument(branch, name: 'RESTORED EDIT', head: saved.revision),
        mutationId: id(15),
      );
      expect(edited.revision.origin, restored.identity.deviceId);
      expect(edited.revision.sequence, BigInt.one);
      final again = await ReceiptRepository.restoreBackup(
        await recovered.exportBackup(),
        stagingParent: h.directory,
      );
      final twice = await ReceiptRepository.open(again.databaseFile);
      try {
        await twice.verifyIntegrity();
      } finally {
        await twice.close();
      }
    } finally {
      await recovered.close();
    }
  });

  for (final invalid in <String, void Function(Map<String, dynamic>)>{
    'downgraded format': (b) => b['format_version'] = '1',
    'future format': (b) => b['format_version'] = '4',
    'missing catalog manifest': (b) =>
        b['content']['counts'].remove('products'),
    'wrong product count': (b) => b['content']['counts']['products'] = '0',
    'wrong alias count': (b) => b['content']['counts']['aliases'] = '2',
    'unsupported normalizer': (b) => changeCatalogEvent(
      b,
      3,
      (e) => e['payload']['alias']['normalizer_version'] = '2',
    ),
    'noncanonical alias': (b) => changeCatalogEvent(
      b,
      3,
      (e) => e['payload']['alias']['normalized_name'] = 'UPPER',
    ),
    'wrong product dependency kind': (b) => changeCatalogEvent(b, 3, (e) {
      e['payload']['product_revision']['sequence'] = '2';
      e['dependencies'][1]['sequence'] = '2';
    }),
    'missing product dependency': (b) => changeCatalogEvent(
      b,
      3,
      (e) => (e['dependencies'] as List).removeLast(),
    ),
    'duplicate dependency': (b) => changeCatalogEvent(
      b,
      3,
      (e) => e['dependencies'][1] = e['dependencies'][0],
    ),
    'changed alias key': (b) => changeCatalogEvent(
      b,
      5,
      (e) => e['payload']['alias']['normalized_name'] = 'changed key',
    ),
    'changed product ownership': (b) => changeCatalogEvent(
      b,
      4,
      (e) => e['payload']['product']['store_id'] = id(99).value,
    ),
    'wrong reviewed head': (b) => changeCatalogEvent(
      b,
      4,
      (e) => e['payload']['review']['expected_head']['sequence'] = '1',
    ),
    'non-product alias target': (b) => changeCatalogEvent(
      b,
      3,
      (e) => e['payload']['alias']['product_id'] = id(1).value,
    ),
    'wrong catalog operation': (b) =>
        changeCatalogEvent(b, 2, (e) => e['operation'] = 'tombstone'),
    'missing retry group member': (b) =>
        changeCatalogEvent(b, 2, (e) => e['mutation_count'] = '2'),
  }.entries) {
    test('modified catalog backup is rejected: ${invalid.key}', () async {
      final product = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final alias = await h.repository.saveAlias(
        aliasDocument(branch, product.revision),
        mutationId: id(13),
      );
      final edited = await h.repository.saveProduct(
        productDocument(branch, head: product.revision, name: 'EDITED'),
        mutationId: id(14),
      );
      await h.repository.saveAlias(
        aliasDocument(
          branch,
          edited.revision,
          active: false,
          head: alias.revision,
        ),
        mutationId: id(15),
      );
      final before = await h.repository.exportBackup();
      final entries = (await h.directory.list().map((e) => e.path).toList())
        ..sort();
      await expectLater(
        ReceiptRepository.restoreBackup(
          tamper(before, invalid.value),
          stagingParent: h.directory,
        ),
        throwsA(isA<StorageFailure>()),
      );
      expect(await h.repository.exportBackup(), before);
      expect(
        (await h.directory.list().map((e) => e.path).toList())..sort(),
        entries,
      );
    });
  }

  test('catalog writes invalidate a prepared workspace replacement', () async {
    final directory = await h.directory.createTemp('catalog-workspace-');
    final workspace = await ReceiptWorkspace.open(directory);
    try {
      await workspace.repository.saveManual(command(snapshot()));
      final branch = (await workspace.repository.branches()).single;
      await workspace.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final encrypted = await workspace.exportProtected(
        'synthetic test password',
      );
      final preview = await workspace.prepare(
        encrypted,
        'synthetic test password',
      );
      final product = (await workspace.repository.readProduct(id(10)))!;
      await workspace.repository.saveAlias(
        aliasDocument(branch, product.revision),
        mutationId: id(13),
      );
      await expectLater(workspace.activate(preview), failure('staleRestore'));
      expect(
        await workspace.repository.matchAlias(branch.id, 'test milk'),
        isNotNull,
      );
      await workspace.discard(preview);
    } finally {
      await workspace.close();
    }
  });

  test(
    'independent writers cannot silently overwrite the same product revision',
    () async {
      final saved = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final other = await ReceiptRepository.open(h.file);
      try {
        final outcomes = await Future.wait<Object>([
          h.repository
              .saveProduct(
                productDocument(branch, name: 'FIRST', head: saved.revision),
                mutationId: id(13),
              )
              .then<Object>((r) => r, onError: (Object e) => e),
          other
              .saveProduct(
                productDocument(branch, name: 'SECOND', head: saved.revision),
                mutationId: id(14),
              )
              .then<Object>((r) => r, onError: (Object e) => e),
        ]);
        expect(outcomes.whereType<SaveResult>(), hasLength(1));
        expect(
          outcomes.whereType<StorageFailure>().single.code,
          anyOf('busy', 'staleCatalog'),
        );
        expect(h.count('catalog_mutations'), 2);
        await h.repository.verifyIntegrity();
      } finally {
        await other.close();
      }
    },
  );

  for (final target in [
    ('INSERT', 'product_aliases'),
    ('UPDATE', 'product_aliases'),
    ('INSERT', 'event_dependencies'),
    ('INSERT', 'revision_parents'),
  ]) {
    test(
      'alias edit rollback at ${target.$1} ${target.$2} preserves the previous mapping',
      () async {
        final product = await h.repository.saveProduct(
          productDocument(branch),
          mutationId: id(12),
        );
        final first = await h.repository.saveAlias(
          aliasDocument(branch, product.revision),
          mutationId: id(13),
        );
        final before = await h.repository.exportBackup();
        final pending = aliasDocument(
          branch,
          product.revision,
          number: target.$1 == 'INSERT' && target.$2 == 'product_aliases'
              ? 20
              : 11,
          active: false,
          head: target.$1 == 'INSERT' && target.$2 == 'product_aliases'
              ? null
              : first.revision,
        );
        h.raw.execute(
          "CREATE TRIGGER fail_alias BEFORE ${target.$1} ON ${target.$2} BEGIN SELECT RAISE(ABORT, 'synthetic_failure'); END",
        );
        await expectLater(
          h.repository.saveAlias(pending, mutationId: id(14)),
          failure('constraint'),
        );
        expect(await h.repository.exportBackup(), before);
        h.raw.execute('DROP TRIGGER fail_alias');
        await h.repository.saveAlias(pending, mutationId: id(14));
        await h.reopen();
      },
    );
  }

  for (final corruption in [
    "UPDATE products SET canonical_name = 'DRIFT'",
    'DELETE FROM product_aliases',
    'UPDATE product_aliases SET is_active = 0',
    "DELETE FROM entity_heads WHERE entity_kind = 'product'",
  ]) {
    test('integrity rejects catalog drift: $corruption', () async {
      final product = await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      await h.repository.saveAlias(
        aliasDocument(branch, product.revision),
        mutationId: id(13),
      );
      h.raw.execute(corruption);
      await expectLater(
        h.repository.verifyIntegrity(),
        throwsA(isA<StorageFailure>()),
      );
      await h.closeConnection();
      await expectLater(
        ReceiptRepository.open(h.file),
        throwsA(isA<StorageFailure>()),
      );
    });
  }

  for (final target in [
    ('UPDATE', 'dataset_state'),
    ('INSERT', 'change_log'),
    ('INSERT', 'products'),
    ('INSERT', 'entity_heads'),
    ('UPDATE', 'received_cursors'),
    ('INSERT', 'catalog_mutations'),
  ]) {
    test('catalog rollback at ${target.$2} preserves retryability', () async {
      final before = await h.repository.exportBackup();
      final identity = await h.repository.identity();
      h.raw.execute(
        "CREATE TRIGGER fail_catalog BEFORE ${target.$1} ON ${target.$2} BEGIN SELECT RAISE(ABORT, 'PRIVATE CATALOG NOTE'); END",
      );
      await expectLater(
        h.repository.saveProduct(productDocument(branch), mutationId: id(12)),
        failure('constraint'),
      );
      expect(await h.repository.exportBackup(), before);
      expect(
        (await h.repository.identity()).nextLocalSequence,
        identity.nextLocalSequence,
      );
      h.raw.execute('DROP TRIGGER fail_catalog');
      await h.reopen();
      expect(
        (await h.repository.saveProduct(
          productDocument(branch),
          mutationId: id(12),
        )).replayed,
        isFalse,
      );
      await h.repository.verifyIntegrity();
    });
  }
}
