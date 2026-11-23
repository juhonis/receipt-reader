import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'catalog_support.dart';
import 'catalog_test.dart' show tamper, changeCatalogEvent;
import '../../receipt_domain/test/ocr_support.dart';

ReviewedReceipt linkCommand(
  StoredReceipt receipt,
  Map<DurableId, ReceiptProductLink?> selections, {
  int mutation = 30,
}) => ReviewedReceipt.productLinks(
  confirmation: ProductLinkReviewChecks(
    base: receipt.document,
    expectedHead: receipt.revision,
    selections: selections,
    mutationId: id(mutation),
  ).confirm(reviewedAtMs: BigInt.from(2000), appVersion: 'saved-links-test'),
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  for (final ocr in [false, true]) {
    test(
      '${ocr ? 'OCR' : 'manual'} reviewed links preserve evidence, retries, recovery and unlink history',
      () async {
        final initial = ocr ? OcrFixture().save() : command(snapshot());
        Future<SaveResult> save(ReviewedReceipt c) =>
            ocr ? h.repository.saveOcr(c) : h.repository.saveManual(c);
        await save(initial);
        final base = (await h.repository.read(id(1)))!;
        final bytes = ReceiptDocumentCodec.encode(base.document);
        final branch = (await h.repository.branches()).single;
        await h.repository.saveProduct(
          productDocument(branch),
          mutationId: id(12),
        );
        final product = (await h.repository.readProduct(id(10)))!;
        final c = linkCommand(base, {id(3): product.link});
        await save(c);
        final linked = (await h.repository.read(id(1)))!;
        validateProductLinkRevision(linked.document, base.document);
        expect(linked.document.review.source, ocr ? 'ocr' : 'manual');
        expect(
          originalReceiptRowIds(linked.document),
          originalReceiptRowIds(base.document),
        );
        expect(
          h.raw.select('SELECT payload FROM change_log WHERE origin_seq = ?', [
            base.revision.sequence.toInt(),
          ]).single['payload'],
          bytes,
        );
        await h.repository.saveProduct(
          productDocument(branch, head: product.revision, name: 'CURRENT'),
          mutationId: id(13),
        );
        expect((await save(c)).replayed, isTrue);
        await save(linkCommand(linked, {id(3): null}, mutation: 31));
        expect(h.count('row_identities'), 1);
        final backup = await h.repository.exportBackup();
        expect(jsonDecode(utf8.decode(backup))['format_version'], '5');
        final encrypted = await ProtectedBackup.encrypt(
          backup,
          'synthetic saved link password',
        );
        final restored = await ReceiptRepository.restoreBackup(
          await ProtectedBackup.decrypt(
            encrypted,
            'synthetic saved link password',
          ),
          stagingParent: h.directory,
        );
        final recovered = await ReceiptRepository.open(restored.databaseFile);
        try {
          expect(await recovered.exportBackup(), backup);
          expect(
            (await recovered.read(id(1)))!
                .document
                .snapshot
                .items
                .single
                .product,
            isNull,
          );
          await recovered.verifyIntegrity();
        } finally {
          await recovered.close();
        }
        await h.reopen();
        final cleared = (await h.repository.read(id(1)))!;
        await h.repository.deleteReceipt(
          ReceiptDeletionChecks(
            document: cleared.document,
            expectedHead: cleared.revision,
            mutationId: id(32),
            receiptReviewed: true,
          ).confirm(
            deletedAtMs: BigInt.from(3000),
            appVersion: 'saved-links-test',
          ),
        );
        expect(
          jsonDecode(
            utf8.decode(await h.repository.exportBackup()),
          )['format_version'],
          '5',
        );
        await h.repository.verifyIntegrity();
      },
    );
  }

  test(
    'unchanged links keep their reviewed revisions after a catalog edit',
    () async {
      await h.repository.saveManual(command(snapshot()));
      final branch = (await h.repository.branches()).single;
      await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final old = (await h.repository.readProduct(id(10)))!;
      await h.repository.saveManual(
        command(
          snapshot(
            number: 40,
            branch: branch,
            total: BigInt.from(400),
            items: [
              ReceiptItemSnapshot(
                id: id(41),
                name: 'LINKED',
                kind: LineKind.product,
                cents: BigInt.from(200),
                product: old.link,
              ),
              row(number: 42),
            ],
          ),
          mutation: 43,
        ),
      );
      final receipt = (await h.repository.read(id(40)))!;
      await h.repository.saveProduct(
        productDocument(branch, head: old.revision, name: 'NEW NAME'),
        mutationId: id(13),
      );
      final fresh = (await h.repository.readProduct(id(10)))!;
      await h.repository.saveManual(linkCommand(receipt, {id(42): fresh.link}));
      final rows = (await h.repository.read(id(40)))!.document.snapshot.items;
      expect(rows.first.product!.revision, old.revision);
      expect(rows.last.product!.revision, fresh.revision);
      await h.repository.verifyIntegrity();
    },
  );

  test(
    'stale receipt and selected product reject without additional writes',
    () async {
      await h.repository.saveManual(command(snapshot()));
      final base = (await h.repository.read(id(1)))!;
      final branch = (await h.repository.branches()).single;
      await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final old = (await h.repository.readProduct(id(10)))!;
      final c = linkCommand(base, {id(3): old.link});
      await h.repository.saveProduct(
        productDocument(branch, head: old.revision),
        mutationId: id(13),
      );
      final before = await h.repository.exportBackup();
      await expectLater(
        h.repository.saveManual(c),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'staleProduct'),
        ),
      );
      expect(await h.repository.exportBackup(), before);
      final fresh = (await h.repository.readProduct(id(10)))!;
      await h.repository.saveManual(
        linkCommand(base, {id(3): fresh.link}, mutation: 31),
      );
      await expectLater(
        h.repository.saveManual(c),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'staleReceipt'),
        ),
      );
    },
  );

  test('foreign products and deleted receipts cannot be linked', () async {
    await h.repository.saveManual(command(snapshot()));
    final base = (await h.repository.read(id(1)))!;
    final branch = (await h.repository.branches()).single;
    await h.repository.saveManual(
      command(
        snapshot(
          number: 60,
          branch: ReceiptBranch(id: id(61), name: 'OTHER BRANCH'),
          items: [row(number: 62)],
        ),
        mutation: 63,
      ),
    );
    final other = (await h.repository.branches()).firstWhere(
      (b) => b.id == id(61),
    );
    await h.repository.saveProduct(
      productDocument(other, number: 64),
      mutationId: id(65),
    );
    final product = (await h.repository.readProduct(id(64)))!;
    final c = linkCommand(base, {
      id(3): ReceiptProductLink(
        id: product.link.id,
        storeId: branch.id,
        revision: product.revision,
      ),
    });
    final before = await h.repository.exportBackup();
    await expectLater(
      h.repository.saveManual(c),
      throwsA(
        isA<StorageFailure>().having(
          (e) => e.code,
          'code',
          'crossStoreProduct',
        ),
      ),
    );
    expect(await h.repository.exportBackup(), before);
    await h.repository.deleteReceipt(
      ReceiptDeletionChecks(
        document: base.document,
        expectedHead: base.revision,
        mutationId: id(66),
        receiptReviewed: true,
      ).confirm(deletedAtMs: BigInt.from(3000), appVersion: 'saved-links-test'),
    );
    await expectLater(
      h.repository.saveManual(c),
      throwsA(
        isA<StorageFailure>().having((e) => e.code, 'code', 'receiptDeleted'),
      ),
    );
    await h.repository.verifyIntegrity();
  });

  for (final invalid in [
    'date',
    'amount',
    'base',
    'evidence',
    'reviewed',
    'downgrade',
  ]) {
    test('checksummed backup rejects a forged link-only $invalid', () async {
      await h.repository.saveManual(command(snapshot()));
      final base = (await h.repository.read(id(1)))!;
      final branch = (await h.repository.branches()).single;
      await h.repository.saveProduct(
        productDocument(branch),
        mutationId: id(12),
      );
      final product = (await h.repository.readProduct(id(10)))!;
      await h.repository.saveManual(linkCommand(base, {id(3): product.link}));
      final before = await h.repository.exportBackup();
      final forged = tamper(before, (b) {
        if (invalid == 'downgrade') {
          b['format_version'] = '3';
          return;
        }
        changeCatalogEvent(b, 3, (e) {
          final r = e['payload']['review'], s = e['payload']['receipt'];
          switch (invalid) {
            case 'date':
              s['date']['day'] = '17';
            case 'amount':
              s['total_cents'] = '300';
              s['items'][0]['cents'] = '300';
            case 'base':
              r['base_document_sha256'] = '0' * 64;
            case 'evidence':
              r['original_row_ids'] = [id(99).value];
            case 'reviewed':
              r['reviewed_product_row_ids'] = <String>[];
          }
        });
      });
      await expectLater(
        ReceiptRepository.restoreBackup(forged, stagingParent: h.directory),
        throwsA(isA<StorageFailure>()),
      );
      expect(await h.repository.exportBackup(), before);
    });
  }
}
