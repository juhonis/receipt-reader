import 'dart:io';
import 'dart:typed_data';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:matcher/expect.dart';

import '../../../receipt_domain/test/ocr_support.dart';
import '../catalog_support.dart';
import '../support.dart';
import 'released_database.dart';

const _password = 'synthetic-upgrade-rehearsal-password';

class UpgradeSeed {
  UpgradeSeed(this.original, this.corrected, this.backup, this.identity);
  final ReviewedReceipt original, corrected;
  final Uint8List backup;
  final DatasetIdentity identity;
}

ReceiptSnapshot _manual(
  ReceiptBranch branch, {
  bool original = false,
  ReceiptProductLink? link,
}) {
  final rows = [
    ReceiptItemSnapshot(
      id: id(3),
      name: 'SYNTHETIC MILK',
      kind: LineKind.product,
      cents: BigInt.from(original ? 200 : 300),
      quantityValue: BigInt.two,
      quantityScale: 0,
      quantityUnit: QuantityUnit.piece,
      rateMicros: BigInt.from(original ? 1000000 : 1500000),
      product: link,
    ),
    if (original) row(number: 7, cents: BigInt.from(50)),
    row(
      number: 4,
      kind: LineKind.deposit,
      cents: BigInt.from(40),
      parent: id(3),
    ),
    row(
      number: 5,
      kind: LineKind.discount,
      cents: BigInt.from(-20),
      scope: DiscountScope.receipt,
    ),
    ReceiptItemSnapshot(
      id: id(6),
      name: 'REVIEWED DIFFERENCE',
      kind: LineKind.adjustment,
      cents: BigInt.from(5),
      adjustmentReason: 'Synthetic checked difference',
    ),
    if (link != null)
      row(
        number: 8,
        kind: LineKind.discount,
        cents: BigInt.from(-100),
        parent: id(3),
        scope: DiscountScope.item,
      ),
  ];
  return snapshot(
    branch: branch,
    date: '17.11.2026 23:59:59',
    items: rows,
    total: rows.fold<BigInt>(BigInt.zero, (sum, r) => sum + r.cents),
  );
}

ReceiptSnapshot _purchase(
  ReceiptBranch branch,
  ReceiptProductLink link, {
  int cents = 300,
}) => snapshot(
  number: 70,
  branch: branch,
  date: '18.11.2026',
  total: BigInt.from(cents),
  items: [
    ReceiptItemSnapshot(
      id: id(71),
      name: 'SYNTHETIC MILK',
      kind: LineKind.product,
      cents: BigInt.from(cents),
      quantityValue: BigInt.from(3),
      quantityScale: 0,
      quantityUnit: QuantityUnit.piece,
      rateMicros: BigInt.from(cents ~/ 3 * 10000),
      product: link,
    ),
  ],
);

/// Seed current commands restricted to features supported by the old schema.
/// Generated historical schemas enforce that restriction when data is copied.
Future<UpgradeSeed> seedUpgradeHistory(File source, int version) async {
  final repository = await ReceiptRepository.open(source);
  try {
    var branch = ReceiptBranch(id: id(2), name: 'SYNTHETIC UPGRADE BRANCH');
    final original = command(
      _manual(branch, original: true),
      mutation: 1000,
      at: 1000,
    );
    final first = await repository.saveManual(original);
    branch = (await repository.branches()).single;
    final corrected = command(
      _manual(branch),
      mutation: 1001,
      at: 1001,
      heads: [first.revision],
    );
    await repository.saveManual(corrected);
    for (final data in [
      (10, 11, -50, '31.10.2026'),
      (12, 13, 0, '29.2.2024'),
    ]) {
      await repository.saveManual(
        command(
          snapshot(
            number: data.$1,
            branch: branch,
            date: data.$4,
            items: [row(number: data.$2, cents: BigInt.from(data.$3))],
            total: BigInt.from(data.$3),
          ),
          mutation: 1000 + data.$1,
          at: 1010 + data.$1,
        ),
      );
    }
    if (version >= 2) {
      final fixture = OcrFixture()..branchName = branch.name;
      final ids = ReviewRowIds()..retain(fixture.rows.single.id, id(21));
      ReviewedReceipt ocr(int mutation, List<RevisionId> heads) {
        final audit = fixture.audit();
        return ReviewedReceipt.ocr(
          current: audit,
          branch: branch,
          rowDetails: const {},
          expectedHeads: heads,
          confirmation:
              OcrReviewChecks(
                audit: audit,
                branch: branch,
                receiptId: id(20),
                rowIds: ids,
                rowDetails: const {},
                expectedHeads: heads,
                mutationId: id(mutation),
                dateReviewed: true,
                totalReviewed: true,
              ).confirm(
                reviewedAtMs: BigInt.from(mutation),
                appVersion: 'upgrade-rehearsal',
              ),
        );
      }

      final first = await repository.saveOcr(ocr(1030, []));
      await repository.saveOcr(ocr(1031, [first.revision]));
    }
    if (version >= 3) {
      final deleted = snapshot(
        number: 30,
        branch: branch,
        items: [row(number: 31)],
      );
      await repository.saveManual(command(deleted, mutation: 1040, at: 1040));
      final saved = (await repository.read(deleted.id))!;
      await repository.deleteReceipt(
        ReceiptDeletionChecks(
          document: saved.document,
          expectedHead: saved.revision,
          mutationId: id(1041),
          receiptReviewed: true,
        ).confirm(
          deletedAtMs: BigInt.from(1041),
          appVersion: 'upgrade-rehearsal',
        ),
      );
    }
    if (version >= 4) {
      final created = await repository.saveProduct(
        productDocument(branch, number: 60, at: 1050),
        mutationId: id(1050),
      );
      await repository.saveProduct(
        productDocument(
          branch,
          number: 60,
          name: 'SYNTHETIC MILK CURRENT',
          head: created.revision,
          at: 1051,
        ),
        mutationId: id(1051),
      );
      final product = (await repository.readProduct(id(60)))!;
      final alias = await repository.saveAlias(
        aliasDocument(
          branch,
          product.revision,
          number: 62,
          product: 60,
          name: 'synthetic milk',
          at: 1052,
        ),
        mutationId: id(1052),
      );
      await repository.saveAlias(
        aliasDocument(
          branch,
          product.revision,
          number: 62,
          product: 60,
          name: 'synthetic milk',
          active: false,
          head: alias.revision,
          at: 1053,
        ),
        mutationId: id(1053),
      );
    }
    await repository.verifyIntegrity();
    return UpgradeSeed(
      original,
      corrected,
      await repository.exportBackup(),
      await repository.identity(),
    );
  } finally {
    await repository.close();
  }
}

Map<String, Object?> _capture(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    return {
      'version': raw.userVersion,
      'tables': captureReleasedTables(raw),
      'schema': raw
          .select('SELECT sql FROM sqlite_schema ORDER BY name')
          .map((r) => r['sql'])
          .toList(),
    };
  } finally {
    raw.close();
  }
}

Future<void> _checkSummaries(
  ReceiptRepository repository,
  int version, {
  bool changed = false,
}) async {
  final total = BigInt.from((version >= 2 ? 675 : 475) + (changed ? 300 : 0));
  final spending = await repository.spendingSummary();
  expect(spending.totals.totalCents, total);
  expect(spending.totals.receiptCount, version >= 2 ? 5 : 4);
  expect(spending.totals.negativeReceipts, 1);
  expect(spending.totals.adjustedReceipts, 1);
  expect(spending.totals.unlinkedReceipts, version >= 2 ? 3 : 2);
  expect(spending.branches.single.totals.totalCents, total);
  expect(spending.months.map((m) => (m.year, m.month)), [
    (2026, 11),
    (2026, 10),
    (2024, 2),
  ]);
  expect(spending.months[1].totals.totalCents, BigInt.from(-50));
  expect(spending.months[2].totals.totalCents, BigInt.zero);
  final day = StoredReceiptDate.parse('17.11.2026');
  expect(
    (await repository.spendingSummary(
      filter: HistoryFilter(branchId: id(2), fromDate: day, throughDate: day),
    )).totals.totalCents,
    BigInt.from(225),
  );
  final prices = await repository.purchaseHistory(id(2), id(60));
  expect(prices.summary.totalRows, 2);
  expect(prices.summary.comparableRows, 2);
  expect(prices.summary.rawCents, BigInt.from(changed ? 900 : 600));
  expect(prices.summary.effectiveCents, BigInt.from(changed ? 800 : 500));
  expect(prices.summary.receiptDiscountRows, 1);
  expect(prices.summary.adjustmentRows, 1);
  expect(prices.summary.groups, hasLength(2));
  expect(
    prices.summary.groups.every(
      (g) => g.unit == QuantityUnit.piece && g.count == 1,
    ),
    isTrue,
  );
  expect(
    prices.summary.groups.map((g) => g.minimum.euros).toList()..sort(),
    changed ? ['1,0000', '2,0000'] : ['1,0000', '1,0000'],
  );
  expect(
    prices.summary.groups.map((g) => g.productRevision).toSet(),
    hasLength(2),
  );
  final selected = await repository.purchaseHistory(
    id(2),
    id(60),
    range: PurchaseDateRange(fromDate: day, throughDate: day),
  );
  expect(selected.summary.totalRows, 1);
  expect(selected.purchases.single.purchase.depositCents, BigInt.from(40));
  expect(
    selected.purchases.single.purchase.effectiveUnitPrice!.euros,
    '1,0000',
  );
  expect(selected.summary.effectiveCents, BigInt.from(200));
  expect(await repository.read(id(30)), isNull);
  expect(
    await repository.readDeleted(id(30)),
    version >= 3 ? isNotNull : isNull,
  );
  if (version >= 2) {
    final ocr = (await repository.read(id(20)))!.document;
    expect(ocr.review.source, 'ocr');
    expect(ocr.review.expectedHeads, hasLength(1));
    expect(ocr.snapshot.items.single.id, id(21));
  }
  expect((await repository.readAlias(id(62)))!.document.alias.isActive, isTrue);
  final match = await repository.matchAlias(id(2), 'SYNTHETIC MILK');
  expect(match!.product.document.product.id, id(60));
  final historical = selected.purchases.single.purchase.row.product!.revision;
  expect(historical, isNot(match.product.revision));
  await repository.verifyIntegrity();
}

/// Same assertions run in package tests and native Android/Windows tests.
/// The optional callback checks restored screens before this workspace closes.
Future<void> rehearseUpgrade(
  Directory directory,
  int version, {
  Future<void> Function(
    ReceiptWorkspace workspace,
    StoredProduct product,
    BigInt total,
  )?
  inspectRestored,
}) async {
  final source = File('${directory.path}/seed.sqlite');
  final file = File('${directory.path}/receipts.sqlite');
  final seed = await seedUpgradeHistory(source, version);
  await copyToReleasedSchema(source, file, version);
  final before = _capture(file);
  expect(before['version'], version);
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
  expect(
    _capture(file),
    before,
    reason: 'Failed upgrades must roll back DDL, values and version.',
  );
  ReceiptWorkspace? workspace;
  try {
    workspace = await ReceiptWorkspace.open(directory);
    var repository = workspace.repository;
    final migrated = _capture(file);
    expect(migrated['version'], 7);
    final beforeTables =
        before['tables']! as Map<String, List<Map<String, Object?>>>;
    final afterTables =
        migrated['tables']! as Map<String, List<Map<String, Object?>>>;
    expect({
      for (final key in beforeTables.keys) key: afterTables[key],
    }, beforeTables);
    expect(await repository.exportBackup(), seed.backup);
    expect((await repository.identity()).deviceId, seed.identity.deviceId);
    expect(
      (await repository.spendingSummary()).totals.totalCents,
      BigInt.from(version >= 2 ? 475 : 275),
    );
    final branch = (await repository.branches()).single;
    if (version < 4) {
      expect(await repository.products(branch.id), isEmpty);
      await repository.saveProduct(
        productDocument(branch, number: 60, at: 2000),
        mutationId: id(2000),
      );
    } else {
      expect(
        (await repository.readAlias(id(62)))!.document.alias.isActive,
        isFalse,
      );
      expect(await repository.matchAlias(branch.id, 'synthetic milk'), isNull);
    }
    final olderProduct = (await repository.readProduct(id(60)))!;
    final current = (await repository.read(id(1)))!;
    await repository.saveManual(
      command(
        _manual(branch, link: olderProduct.link),
        mutation: 2001,
        at: 2001,
        heads: [current.revision],
      ),
    );
    await repository.saveProduct(
      productDocument(
        branch,
        number: 60,
        name: 'SYNTHETIC MILK LATER',
        head: olderProduct.revision,
        at: 2002,
      ),
      mutationId: id(2002),
    );
    final product = (await repository.readProduct(id(60)))!;
    final alias = await repository.readAlias(id(62));
    await repository.saveAlias(
      aliasDocument(
        branch,
        product.revision,
        number: 62,
        product: 60,
        name: 'synthetic milk',
        head: alias?.revision,
        at: 2003,
      ),
      mutationId: id(2003),
    );
    final purchase = _purchase(branch, product.link);
    final purchaseSave = await repository.saveManual(
      command(purchase, mutation: 2004, at: 2004),
    );
    await _checkSummaries(repository, version);
    final originalEvents = beforeTables['change_log']!;
    final postUpgrade =
        _capture(file)['tables']! as Map<String, List<Map<String, Object?>>>;
    expect(
      postUpgrade['change_log']!.take(originalEvents.length).toList(),
      originalEvents,
    );
    final owners = postUpgrade['row_identities']!;
    expect(
      owners.where((r) => r['row_id'] == id(7).value).single['receipt_id'],
      id(1).value,
    );
    expect(
      (await repository.read(id(1)))!.document.snapshot.items
          .any((r) => r.id == id(7)),
      isFalse,
    );
    final plain = await repository.exportBackup();
    final encrypted = await workspace.exportProtected(_password);
    await expectLater(
      workspace.prepare(encrypted, 'wrong-rehearsal-password'),
      throwsA(
        isA<StorageFailure>().having(
          (e) => e.code,
          'code',
          'backupAuthentication',
        ),
      ),
    );
    final tampered = Uint8List.fromList(encrypted)..[encrypted.length - 1] ^= 1;
    await expectLater(
      workspace.prepare(tampered, _password),
      throwsA(isA<StorageFailure>()),
    );
    expect(await repository.exportBackup(), plain);
    // Leave a different dataset to prove replacement and previous-slot recovery.
    final correction = command(
      _purchase(branch, product.link, cents: 600),
      mutation: 2005,
      at: 2005,
      heads: [purchaseSave.revision],
    );
    await repository.saveManual(correction);
    await _checkSummaries(repository, version, changed: true);
    final changedBackup = await repository.exportBackup();
    final preview = await workspace.prepare(encrypted, _password);
    await workspace.activate(preview);
    repository = workspace.repository;
    final restoredTables =
        _capture(preview.restored.databaseFile)['tables']!
            as Map<String, List<Map<String, Object?>>>;
    for (final entry in postUpgrade.entries) {
      if (entry.key == 'dataset_state' || entry.key == 'received_cursors')
        continue;
      expect(
        restoredTables[entry.key],
        unorderedEquals(entry.value),
        reason: 'Encrypted restore must preserve ' + entry.key,
      );
    }
    expect(
      restoredTables['received_cursors'],
      containsAll(postUpgrade['received_cursors']!),
    );
    final restoredIdentity = await repository.identity();
    expect(restoredIdentity.datasetId, seed.identity.datasetId);
    expect(restoredIdentity.deviceId, isNot(seed.identity.deviceId));
    expect(restoredIdentity.nextLocalSequence, BigInt.one);
    expect(await repository.exportBackup(), plain);
    await _checkSummaries(repository, version);
    // Exact retries of old commands must not append events after restore.
    expect((await repository.saveManual(seed.original)).replayed, isTrue);
    expect((await repository.saveManual(seed.corrected)).replayed, isTrue);
    expect(await repository.exportBackup(), plain);
    final freshSave = await repository.saveManual(correction);
    expect(freshSave.replayed, isFalse);
    expect(freshSave.revision.origin, restoredIdentity.deviceId);
    expect(freshSave.revision.sequence, BigInt.one);
    await _checkSummaries(repository, version, changed: true);
    await workspace.close();
    workspace = null;
    workspace = await ReceiptWorkspace.open(directory);
    expect(
      (await workspace.repository.identity()).deviceId,
      restoredIdentity.deviceId,
    );
    await _checkSummaries(workspace.repository, version, changed: true);
    // Return to the retained pre-activation slot; its exact bytes are preserved.
    await workspace.returnToPrevious();
    expect(await workspace.repository.exportBackup(), changedBackup);
    await _checkSummaries(workspace.repository, version, changed: true);
    // A second encrypted recovery proves repeated fresh-origin restoration.
    final again = await workspace.prepare(encrypted, _password);
    await workspace.activate(again);
    expect(
      (await workspace.repository.identity()).deviceId,
      isNot(restoredIdentity.deviceId),
    );
    expect(await workspace.repository.exportBackup(), plain);
    await _checkSummaries(workspace.repository, version);
    if (inspectRestored != null) {
      await inspectRestored(
        workspace,
        (await workspace.repository.readProduct(id(60)))!,
        BigInt.from(version >= 2 ? 675 : 475),
      );
    }
  } finally {
    await workspace?.close();
  }
}

/// Synthetic future-version/corrupt projections must be refused without reset.
Future<void> rehearseRefusal(Directory directory) async {
  final source = File('${directory.path}/seed.sqlite');
  await seedUpgradeHistory(source, 4);
  for (final name in ['future', 'corrupt']) {
    final target = File('${directory.path}/$name.sqlite');
    expect(await target.exists(), isFalse);
    await source.copy(target.path);
    final raw = sqlite.sqlite3.open(target.path);
    try {
      if (name == 'future') {
        raw.userVersion = 8;
      } else {
        raw.execute(
          'UPDATE receipts SET total_amount_cents = 999 WHERE id = ?',
          [id(1).value],
        );
      }
    } finally {
      raw.close();
    }
    final before = _capture(target);
    await expectLater(
      ReceiptRepository.open(target),
      throwsA(isA<StorageFailure>()),
    );
    expect(
      _capture(target),
      before,
      reason: 'An unsupported or invalid database must not be silently reset.',
    );
  }
}
