import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../../receipt_domain/test/ocr_support.dart';
import 'support.dart';

String digest(String text) => sha256.convert(utf8.encode(text)).toString();
Matcher failure([String? code]) => throwsA(
  isA<StorageFailure>().having((e) => e.code, 'code', code ?? isNotEmpty),
);
Uint8List changed(Uint8List bytes, void Function(Map<String, dynamic>) change) {
  final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  change(map);
  map['content_sha256'] = digest(jsonEncode(map['content']));
  return utf8.encode(jsonEncode(map));
}

void changeEvent(
  Map<String, dynamic> backup,
  int index,
  void Function(Map<String, dynamic>) change,
) {
  final entry = backup['content']['events'][index] as Map<String, dynamic>;
  final event =
      jsonDecode(entry['canonical_event'] as String) as Map<String, dynamic>;
  change(event);
  entry['canonical_event'] = jsonEncode(event);
  entry['event_sha256'] = digest(entry['canonical_event'] as String);
}

ReviewedReceipt ocr(
  ReceiptBranch branch, {
  List<RevisionId> heads = const [],
  int mutation = 22,
}) {
  final f = OcrFixture();
  final audit = f.audit();
  final ids = ReviewRowIds()..retain(f.rows.single.id, id(21));
  final check = OcrReviewChecks(
    audit: audit,
    branch: branch,
    receiptId: id(20),
    rowIds: ids,
    rowDetails: const {},
    expectedHeads: heads,
    mutationId: id(mutation),
    dateReviewed: true,
    totalReviewed: true,
  );
  return ReviewedReceipt.ocr(
    current: audit,
    branch: branch,
    rowDetails: const {},
    expectedHeads: heads,
    confirmation: check.confirm(
      reviewedAtMs: BigInt.from(456),
      appVersion: 'backup-test',
    ),
  );
}

ReviewedReceiptDeletion deletion(StoredReceipt receipt, {int mutation = 23}) =>
    ReceiptDeletionChecks(
      document: receipt.document,
      expectedHead: receipt.revision,
      mutationId: id(mutation),
      receiptReviewed: true,
    ).confirm(deletedAtMs: BigInt.from(789), appVersion: 'backup-test');

Future<List<String>> entries(Directory directory) async =>
    (await directory.list().map((e) => e.path).toList())..sort();
Map<String, Object?> capture(sqlite.Database database) => {
  for (final table in [
    'change_log',
    'revision_parents',
    'event_dependencies',
    'entity_heads',
    'stores',
    'receipts',
    'receipt_items',
    'receipt_reviews',
    'row_identities',
    'local_mutations',
  ])
    table: database
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
};

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test('empty canonical fixture excludes active identity and restores with a fresh origin', () async {
    h.raw.execute('UPDATE dataset_state SET dataset_id = ?, device_id = ?', [
      id(90).value,
      id(91).value,
    ]);
    h.raw.execute('DELETE FROM received_cursors');
    h.raw.execute('INSERT INTO received_cursors VALUES (?, 0)', [id(91).value]);
    final before = await h.repository.identity();
    final bytes = await h.repository.exportBackup();
    expect(bytes, File('test/fixtures/backup_empty_v1.json').readAsBytesSync());
    expect(await h.repository.exportBackup(), bytes);
    expect(utf8.decode(bytes), isNot(contains(id(91).value)));
    final first = await ReceiptRepository.restoreBackup(
      bytes,
      stagingParent: h.directory,
    );
    final second = await ReceiptRepository.restoreBackup(
      bytes,
      stagingParent: h.directory,
    );
    expect(first.identity.datasetId, before.datasetId);
    expect(first.identity.deviceId, isNot(before.deviceId));
    expect(first.identity.deviceId, isNot(second.identity.deviceId));
    expect(first.identity.nextLocalSequence, BigInt.one);
    expect((await h.repository.identity()).deviceId, before.deviceId);
    final restored = await ReceiptRepository.open(first.databaseFile);
    try {
      expect(await restored.history(), isEmpty);
      expect(await restored.exportBackup(), bytes);
      final write = await restored.saveManual(command(snapshot()));
      expect(write.revision.origin, first.identity.deviceId);
      expect(write.revision.sequence, BigInt.two);
      await restored.verifyIntegrity();
    } finally {
      await restored.close();
    }
  });

  test('restore retains every historical byte, tombstone, row owner, metadata and retry result', () async {
    final initial = command(
      snapshot(
        items: [
          row(),
          row(number: 8, name: 'RETIRED', cents: BigInt.from(50)),
        ],
        total: BigInt.from(250),
      ),
    );
    final saved = await h.repository.saveManual(initial);
    final prior = (await h.repository.history()).single;
    final branch = (await h.repository.branches()).single;
    final corrected = command(
      snapshot(
        branch: branch,
        items: [
          ReceiptItemSnapshot(
            id: id(3),
            name: 'CORRECTED',
            rawName: 'PRINTED PRODUCT',
            kind: LineKind.product,
            cents: BigInt.from(250),
            quantityValue: BigInt.from(1000),
            quantityScale: 3,
            quantityUnit: QuantityUnit.kg,
            rateMicros: BigInt.from(2500000),
          ),
          row(
            number: 5,
            name: 'DISCOUNT',
            cents: BigInt.from(-50),
            kind: LineKind.discount,
            parent: id(3),
            scope: DiscountScope.item,
          ),
          row(
            number: 6,
            name: 'DEPOSIT',
            cents: BigInt.from(10),
            kind: LineKind.deposit,
          ),
          ReceiptItemSnapshot(
            id: id(7),
            name: 'ADJUSTMENT',
            kind: LineKind.adjustment,
            cents: BigInt.from(-10),
            adjustmentReason: 'REVIEWED REASON',
          ),
        ],
      ),
      mutation: 10,
      heads: [prior.revision],
    );
    await h.repository.saveManual(corrected);
    final ocrCommand = ocr(branch);
    await h.repository.saveOcr(ocrCommand);
    final manual = (await h.repository.read(id(1)))!;
    final remove = deletion(manual);
    await h.repository.deleteReceipt(remove);
    final sourceIdentity = await h.repository.identity();
    final before = capture(h.raw);
    final bytes = await h.repository.exportBackup();
    expect(utf8.decode(bytes), isNot(contains('PRIVATE NOTE')));
    final staged = await ReceiptRepository.restoreBackup(
      bytes,
      stagingParent: h.directory,
    );
    expect(staged.receiptCount, 2);
    expect(staged.deletedReceiptCount, 1);
    final raw = sqlite.sqlite3.open(staged.databaseFile.path);
    expect(capture(raw), before);
    raw.close();
    var restored = await ReceiptRepository.open(staged.databaseFile);
    try {
      expect(await restored.exportBackup(), bytes);
      expect(
        (await restored.identity()).deviceId,
        isNot(sourceIdentity.deviceId),
      );
      expect(
        (await restored.history()).single.document.review,
        isA<OcrReviewRecord>(),
      );
      expect((await restored.saveManual(initial)).revision, saved.revision);
      expect((await restored.saveOcr(ocrCommand)).replayed, isTrue);
      expect((await restored.deleteReceipt(remove)).replayed, isTrue);
      expect(await restored.read(id(1)), isNull);
      await expectLater(
        restored.saveManual(command(snapshot(branch: branch), mutation: 80)),
        failure('receiptDeleted'),
      );
      await expectLater(
        restored.saveManual(
          command(snapshot(number: 30, branch: branch), mutation: 81),
        ),
        failure('rowIdentityReused'),
      );
      await restored.close();
      restored = await ReceiptRepository.open(staged.databaseFile);
      final current = (await restored.history()).single;
      final correction = ocr(branch, heads: [current.revision], mutation: 31);
      final newResult = await restored.saveOcr(correction);
      expect(newResult.revision.origin, staged.identity.deviceId);
      expect(newResult.revision.sequence, BigInt.one);
      final nextBytes = await restored.exportBackup();
      final second = await ReceiptRepository.restoreBackup(
        nextBytes,
        stagingParent: h.directory,
      );
      final recoveredAgain = await ReceiptRepository.open(second.databaseFile);
      try {
        expect(second.identity.deviceId, isNot(staged.identity.deviceId));
        expect(await recoveredAgain.exportBackup(), nextBytes);
        expect(
          (await recoveredAgain.saveOcr(correction)).revision,
          newResult.revision,
        );
        final removedOcr = deletion(
          (await recoveredAgain.history()).single,
          mutation: 32,
        );
        final result = await recoveredAgain.deleteReceipt(removedOcr);
        expect(result.revision.origin, second.identity.deviceId);
        expect(result.revision.sequence, BigInt.one);
        final thirdBytes = await recoveredAgain.exportBackup();
        final third = await ReceiptRepository.restoreBackup(
          thirdBytes,
          stagingParent: h.directory,
        );
        final thirdRepository = await ReceiptRepository.open(
          third.databaseFile,
        );
        try {
          expect(await thirdRepository.history(), isEmpty);
          await thirdRepository.verifyIntegrity();
        } finally {
          await thirdRepository.close();
        }
      } finally {
        await recoveredAgain.close();
      }
      expect(capture(h.raw), before);
    } finally {
      await restored.close();
    }
  });

  final malformed = <String, Uint8List Function(Uint8List)>{
    'future format': (b) => changed(b, (m) => m['format_version'] = '4'),
    'future event': (b) =>
        changed(b, (m) => changeEvent(m, 0, (e) => e['event_version'] = '2')),
    'unknown field': (b) =>
        changed(b, (m) => m['private_key'] = 'PRIVATE SECRET'),
    'missing field': (b) => changed(b, (m) => m['content'].remove('heads')),
    'bad checksum': (b) =>
        changed(b, (m) => m['content']['events'][0]['event_sha256'] = '0' * 64),
    'wrong manifest counts': (b) =>
        changed(b, (m) => m['content']['counts']['stores'] = '0'),
    'wrong heads': (b) =>
        changed(b, (m) => m['content']['heads'][0]['sequence'] = '999'),
    'missing group member': (b) => changed(b, (m) {
      m['content']['events'].removeLast();
      m['content']['counts']['events'] = '1';
    }),
    'sequence gap': (b) =>
        changed(b, (m) => changeEvent(m, 1, (e) => e['sequence'] = '3')),
    'future review policy': (b) => changed(
      b,
      (m) => changeEvent(
        m,
        1,
        (e) => e['payload']['review']['policy_version'] = '99',
      ),
    ),
    'invalid receipt values': (b) => changed(
      b,
      (m) => changeEvent(
        m,
        1,
        (e) => e['payload']['receipt']['total_cents'] = '201',
      ),
    ),
    'negative sequence': (b) =>
        changed(b, (m) => changeEvent(m, 1, (e) => e['sequence'] = '-1')),
    'overflow audit': (b) => changed(
      b,
      (m) => changeEvent(m, 1, (e) => e['audit_at_ms'] = '9223372036854775808'),
    ),
    'wrong dataset': (b) =>
        changed(b, (m) => m['content']['dataset_id'] = id(80).value),
    'duplicate event': (b) => changed(b, (m) {
      m['content']['events'].add(m['content']['events'][1]);
      m['content']['counts']['events'] = '3';
    }),
    'cross-origin mutation': (b) => changed(
      b,
      (m) => changeEvent(m, 1, (e) {
        e['origin'] = id(80).value;
        e['sequence'] = '1';
      }),
    ),
    'reordered history': (b) => changed(
      b,
      (m) => m['content']['events'] = (m['content']['events'] as List).reversed
          .toList(),
    ),
    'truncated bytes': (b) => Uint8List.sublistView(b, 0, b.length - 1),
    'extra whitespace': (b) => Uint8List.fromList([...b, 10]),
    'duplicate JSON key': (b) => utf8.encode(
      utf8.decode(b).replaceFirst('{', '{"format":"receipt_reader_backup",'),
    ),
    'invalid UTF-8': (b) => Uint8List.fromList([255, ...b]),
    'UTF-8 BOM': (b) => Uint8List.fromList([239, 187, 191, ...b]),
    'too many events': (b) =>
        changed(b, (m) => m['content']['counts']['events'] = '20001'),
    'oversized event': (b) => changed(
      b,
      (m) => m['content']['events'][0]['canonical_event'] =
          'x' * (ReceiptBackupLimits.maxEventBytes + 1),
    ),
  };
  for (final entry in malformed.entries) {
    test(
      'rejects ${entry.key}, removes staging and preserves the active dataset',
      () async {
        await h.repository.saveManual(command(snapshot()));
        final bytes = await h.repository.exportBackup();
        final before = capture(h.raw);
        final directories = await entries(h.directory);
        await expectLater(
          ReceiptRepository.restoreBackup(
            entry.value(bytes),
            stagingParent: h.directory,
          ),
          failure(),
        );
        expect(await entries(h.directory), directories);
        expect(capture(h.raw), before);
        await h.repository.verifyIntegrity();
      },
    );
  }

  test('bounds input before parsing and sanitizes missing/unwritable staging errors', () async {
    await expectLater(
      ReceiptRepository.restoreBackup(
        Uint8List(ReceiptBackupLimits.maxBytes + 1),
        stagingParent: h.directory,
      ),
      failure('backupTooLarge'),
    );
    final bytes = await h.repository.exportBackup();
    await expectLater(
      ReceiptRepository.restoreBackup(
        bytes,
        stagingParent: Directory('${h.directory.path}/absent'),
      ),
      failure('backupStorage'),
    );
    await expectLater(
      ReceiptRepository.restoreBackup(
        bytes,
        stagingParent: Directory(h.file.path),
      ),
      failure('backupStorage'),
    );
    await h.repository.verifyIntegrity();
  });

  test('exports one complete snapshot while a concurrent connection commits a two-event mutation', () async {
    await h.repository.saveManual(command(snapshot()));
    final other = await ReceiptRepository.open(h.file);
    try {
      final export = h.repository.exportBackup();
      final write = other.saveManual(
        command(
          snapshot(
            number: 40,
            branch: ReceiptBranch(id: id(41), name: 'SECOND BRANCH'),
            items: [row(number: 42)],
          ),
          mutation: 43,
        ),
      );
      await write;
      final staged = await ReceiptRepository.restoreBackup(
        await export,
        stagingParent: h.directory,
      );
      final restored = await ReceiptRepository.open(staged.databaseFile);
      try {
        expect((await restored.history()).length, anyOf(1, 2));
        expect(staged.eventCount, anyOf(2, 4));
        await restored.verifyIntegrity();
      } finally {
        await restored.close();
      }
      expect(await h.repository.history(), hasLength(2));
    } finally {
      await other.close();
    }
  });

  test(
    'signed integer limits and exact printed timestamps survive restore',
    () async {
      await h.repository.saveManual(
        command(
          snapshot(
            total: sqliteInt64Min,
            items: [row(cents: sqliteInt64Min)],
            date: '16.11.2026 23:59:56',
          ),
        ),
      );
      final branch = (await h.repository.branches()).single;
      await h.repository.saveManual(
        command(
          snapshot(
            number: 10,
            branch: branch,
            total: sqliteInt64Max,
            items: [row(number: 11, cents: sqliteInt64Max)],
            date: '16.11.2026 23:59',
          ),
          mutation: 12,
        ),
      );
      final bytes = await h.repository.exportBackup();
      final staged = await ReceiptRepository.restoreBackup(
        bytes,
        stagingParent: h.directory,
      );
      final restored = await ReceiptRepository.open(staged.databaseFile);
      try {
        expect(await restored.exportBackup(), bytes);
        expect(
          (await restored.history()).map((r) => r.document.snapshot.totalCents),
          unorderedEquals([sqliteInt64Min, sqliteInt64Max]),
        );
        await restored.verifyIntegrity();
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'recomputed checksums still require deletion to match the prior document',
    () async {
      await h.repository.saveManual(command(snapshot()));
      await h.repository.deleteReceipt(
        deletion((await h.repository.history()).single),
      );
      final bytes = await h.repository.exportBackup();
      final invalid = changed(
        bytes,
        (m) => changeEvent(
          m,
          2,
          (e) => e['payload']['reviewed_document_sha256'] = '0' * 64,
        ),
      );
      final before = await entries(h.directory);
      await expectLater(
        ReceiptRepository.restoreBackup(invalid, stagingParent: h.directory),
        failure('tombstonePayload'),
      );
      expect(await entries(h.directory), before);
      expect(await h.repository.readDeleted(id(1)), isNotNull);
    },
  );

  test(
    'a forged snapshot after a tombstone cannot resurrect a receipt on restore',
    () async {
      await h.repository.saveManual(command(snapshot()));
      final prior = (await h.repository.history()).single;
      final branch = (await h.repository.branches()).single;
      final removed = await h.repository.deleteReceipt(deletion(prior));
      final bytes = await h.repository.exportBackup();
      final forged = command(
        snapshot(branch: branch),
        heads: [removed.revision],
        mutation: 30,
      );
      final invalid = changed(bytes, (m) {
        final content = m['content'];
        final event = jsonDecode(
          content['events'][1]['canonical_event'] as String,
        ) as Map<String, dynamic>;
        event['sequence'] = '4';
        event['audit_at_ms'] = forged.document.review.reviewedAtMs.toString();
        event['mutation_id'] = forged.mutationId.value;
        event['mutation_index'] = '0';
        event['mutation_count'] = '1';
        event['parents'] = [
          {
            'origin': removed.revision.origin.value,
            'sequence': removed.revision.sequence.toString(),
          },
        ];
        event['payload'] = jsonDecode(
          ReceiptDocumentCodec.encode(forged.document),
        );
        final canonical = jsonEncode(event);
        content['events'].add({
          'canonical_event': canonical,
          'event_sha256': digest(canonical),
        });
        content['counts']['events'] = '4';
        content['counts']['deleted_receipts'] = '0';
        for (final head in content['heads'] as List) {
          if (head['entity_kind'] == 'receipt') {
            head['sequence'] = '4';
          }
        }
      });
      final before = await entries(h.directory);
      await expectLater(
        ReceiptRepository.restoreBackup(invalid, stagingParent: h.directory),
        failure('historicalResurrection'),
      );
      expect(await entries(h.directory), before);
      expect(await h.repository.history(), isEmpty);
    },
  );

  test(
    'export refuses corrupted projections instead of blessing them in a backup',
    () async {
      await h.repository.saveManual(command(snapshot()));
      h.raw.execute('UPDATE receipts SET total_amount_cents = 201');
      await expectLater(
        h.repository.exportBackup(),
        failure('receiptProjection'),
      );
    },
  );
}
