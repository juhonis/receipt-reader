import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'catalog_support.dart';
import 'catalog_test.dart' show tamper, changeCatalogEvent;
import 'support.dart';
import '../../receipt_domain/test/ocr_support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  late ReceiptBranch branch;
  late StoredProduct product;
  late StoredReceipt initial;
  setUp(() async {
    h = await Harness.create();
    await h.repository.saveManual(command(snapshot()));
    branch = (await h.repository.branches()).single;
    initial = (await h.repository.read(id(1)))!;
    await h.repository.saveProduct(productDocument(branch), mutationId: id(12));
    product = (await h.repository.readProduct(id(10)))!;
  });
  tearDown(() => h.dispose());
  ReceiptSnapshot linked({ReceiptProductLink? link, bool unlinked = false}) =>
      snapshot(
        branch: branch,
        items: [
          ReceiptItemSnapshot(
            id: id(3),
            rawName: 'ORIGINAL MILK',
            name: 'Reviewed milk',
            kind: LineKind.product,
            cents: BigInt.from(200),
            product: unlinked ? null : link ?? product.link,
          ),
        ],
      );
  Future<SaveResult> saveLink() => h.repository.saveManual(
    command(linked(), mutation: 20, heads: [initial.revision]),
  );
  Matcher fails(String code) =>
      throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));

  test('reviewed links preserve row identity, raw names, amounts and causal history across later catalog edits', () async {
    final pending = command(linked(), mutation: 20, heads: [initial.revision]);
    final saved = await h.repository.saveManual(pending);
    final receipt = (await h.repository.read(id(1)))!;
    expect(
      receipt.document.snapshot.items.single.product!.revision,
      product.revision,
    );
    expect(receipt.document.snapshot.items.single.rawName, 'ORIGINAL MILK');
    expect(receipt.document.snapshot.items.single.id, id(3));
    expect(receipt.document.snapshot.totalCents, BigInt.from(200));
    expect(receipt.document.review.expectedHeads, [initial.revision]);
    expect(
      h.raw.select('SELECT product_id FROM receipt_items').single['product_id'],
      id(10).value,
    );
    final deps = h.raw.select(
      'SELECT dependency_seq FROM event_dependencies WHERE child_seq = ?',
      [saved.revision.sequence.toInt()],
    );
    expect(deps.map((r) => r['dependency_seq']).toSet(), {
      branch.revision!.sequence.toInt(),
      product.revision.sequence.toInt(),
    });
    await h.repository.saveProduct(
      productDocument(
        branch,
        name: 'Updated catalog label',
        head: product.revision,
      ),
      mutationId: id(21),
    );
    expect((await h.repository.saveManual(pending)).replayed, isTrue);
    await h.reopen();
    expect(
      (await h.repository.read(id(1)))!.document.sha256Hex,
      receipt.document.sha256Hex,
    );
    await h.repository.verifyIntegrity();
    await expectLater(
      h.repository.saveManual(
        command(linked(), mutation: 22, heads: [saved.revision]),
      ),
      fails('staleProduct'),
    );
    final currentProduct = (await h.repository.readProduct(id(10)))!;
    await h.repository.saveManual(
      command(
        linked(link: currentProduct.link),
        mutation: 23,
        heads: [saved.revision],
      ),
    );
    final head = (await h.repository.read(id(1)))!.revision;
    await h.repository.saveManual(
      command(linked(unlinked: true), mutation: 24, heads: [head]),
    );
    expect(
      (await h.repository.read(id(1)))!.document.snapshot.items.single.product,
      isNull,
    );
    expect(h.count('row_identities'), 1);
    await h.repository.verifyIntegrity();
  });

  test('repeated products deduplicate dependencies and independent products stay separate', () async {
    await h.repository.saveProduct(
      productDocument(branch, number: 30),
      mutationId: id(31),
    );
    final second = (await h.repository.readProduct(id(30)))!;
    final rows = [
      for (var i = 0; i < 3; i++)
        ReceiptItemSnapshot(
          id: id(i == 0 ? 3 : 40 + i),
          name: 'MILK',
          kind: LineKind.product,
          cents: BigInt.from(200),
          product: i == 2 ? second.link : product.link,
        ),
    ];
    final saved = await h.repository.saveManual(
      command(
        snapshot(branch: branch, items: rows, total: BigInt.from(600)),
        mutation: 50,
        heads: [initial.revision],
      ),
    );
    expect(
      h.raw.select('SELECT * FROM event_dependencies WHERE child_seq = ?', [
        saved.revision.sequence.toInt(),
      ]),
      hasLength(3),
    );
    await h.repository.verifyIntegrity();
  });

  test(
    'foreign-store product cannot be disguised by forging the link store',
    () async {
      final otherBranch = ReceiptBranch(id: id(60), name: 'OTHER BRANCH');
      await h.repository.saveManual(
        command(
          snapshot(number: 61, branch: otherBranch, items: [row(number: 62)]),
          mutation: 63,
        ),
      );
      final other = (await h.repository.branches()).firstWhere(
        (b) => b.id == otherBranch.id,
      );
      await h.repository.saveProduct(
        productDocument(other, number: 64),
        mutationId: id(65),
      );
      final foreign = (await h.repository.readProduct(id(64)))!;
      final before = await h.repository.exportBackup();
      await expectLater(
        h.repository.saveManual(
          command(
            linked(
              link: ReceiptProductLink(
                id: foreign.link.id,
                storeId: branch.id,
                revision: foreign.revision,
              ),
            ),
            mutation: 66,
            heads: [initial.revision],
          ),
        ),
        fails('crossStoreProduct'),
      );
      expect(await h.repository.exportBackup(), before);
      expect(
        () => h.raw.execute('UPDATE receipt_items SET product_id = ?', [
          foreign.link.id.value,
        ]),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await saveLink();
      expect(
        () => h.raw.execute("UPDATE receipt_items SET kind = 'deposit'"),
        throwsA(isA<sqlite.SqliteException>()),
      );
    },
  );

  test('linked historical snapshots use inner backup v3 through encrypted restore, unlink and deletion', () async {
    final saved = await saveLink();
    await h.repository.saveManual(
      command(linked(unlinked: true), mutation: 21, heads: [saved.revision]),
    );
    final receipt = (await h.repository.read(id(1)))!;
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: receipt.document,
        expectedHead: receipt.revision,
        mutationId: id(22),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(456), appVersion: 'links-test'),
    );
    final bytes = await h.repository.exportBackup();
    expect(jsonDecode(utf8.decode(bytes))['format_version'], '3');
    final protected = await ProtectedBackup.encrypt(
      bytes,
      'synthetic link backup password',
    );
    final restored = await ReceiptRepository.restoreBackup(
      await ProtectedBackup.decrypt(
        protected,
        'synthetic link backup password',
      ),
      stagingParent: h.directory,
    );
    final recovered = await ReceiptRepository.open(restored.databaseFile);
    try {
      expect(await recovered.exportBackup(), bytes);
      expect(await recovered.read(id(1)), isNull);
      expect(await recovered.readDeleted(id(1)), isNotNull);
      await recovered.verifyIntegrity();
    } finally {
      await recovered.close();
    }
  });

  test(
    'OCR links persist reviewed provenance and stable row identity',
    () async {
      final f = OcrFixture();
      final ids = ReviewRowIds()..retain(f.rows.single.id, id(32));
      final details = {f.rows.single.id: OcrRowDetails(product: product.link)};
      final current = f.audit();
      final pending = ReviewedReceipt.ocr(
        current: current,
        branch: branch,
        rowDetails: details,
        expectedHeads: const [],
        confirmation: OcrReviewChecks(
          audit: current,
          branch: branch,
          receiptId: id(33),
          rowIds: ids,
          rowDetails: details,
          expectedHeads: const [],
          mutationId: id(34),
          dateReviewed: true,
          totalReviewed: true,
        ).confirm(reviewedAtMs: BigInt.from(1000), appVersion: 'links-test'),
      );
      await h.repository.saveOcr(pending);
      await h.reopen();
      final receipt = (await h.repository.read(id(33)))!;
      expect(receipt.document.review, isA<OcrReviewRecord>());
      expect(receipt.document.snapshot.items.single.id, id(32));
      expect(receipt.document.snapshot.items.single.rawName, 'MILK');
      expect(
        receipt.document.snapshot.items.single.product!.revision,
        product.revision,
      );
      expect((await h.repository.saveOcr(pending)).replayed, isTrue);
      await h.repository.verifyIntegrity();
    },
  );

  for (final invalid in [
    'missing dependency',
    'wrong product revision',
    'wrong product identity',
    'wrong product store',
    'downgraded version',
  ]) {
    test(
      'checksummed linked backup rejects $invalid without touching source',
      () async {
        await saveLink();
        final before = await h.repository.exportBackup();
        final bytes = tamper(before, (b) {
          if (invalid == 'downgraded version') {
            b['format_version'] = '2';
            return;
          }
          changeCatalogEvent(b, 3, (e) {
            final link = e['payload']['receipt']['items'][0]['product'];
            switch (invalid) {
              case 'missing dependency':
                e['dependencies'].removeWhere(
                  (dynamic d) =>
                      d['sequence'] == product.revision.sequence.toString(),
                );
              case 'wrong product revision':
                link['revision']['sequence'] = branch.revision!.sequence
                    .toString();
              case 'wrong product identity':
                link['id'] = id(99).value;
              case 'wrong product store':
                link['store_id'] = id(99).value;
            }
          });
        });
        await expectLater(
          ReceiptRepository.restoreBackup(bytes, stagingParent: h.directory),
          throwsA(isA<StorageFailure>()),
        );
        expect(await h.repository.exportBackup(), before);
        await h.repository.verifyIntegrity();
      },
    );
  }
}
