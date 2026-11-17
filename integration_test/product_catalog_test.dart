import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native catalog writes, encrypted activation and previous-data recovery',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('catalog-storage-smoke-');
      ReceiptWorkspace? workspace;
      try {
        workspace = await ReceiptWorkspace.open(directory);
        final receipt = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: 'SYNTHETIC CATALOG BRANCH',
          ),
          date: StoredReceiptDate.parse('17.11.2026'),
          totalCents: BigInt.from(250),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'TEST MILK 1 L',
              kind: LineKind.product,
              cents: BigInt.from(250),
            ),
          ],
        );
        final command = ReviewedReceipt.manual(
          current: receipt,
          expectedHeads: const [],
          confirmation: ManualReviewChecks(
            snapshot: receipt,
            expectedHeads: const [],
            mutationId: DurableId.generate(),
            branchReviewed: true,
            dateReviewed: true,
            totalReviewed: true,
            reviewedRowIds: receipt.items.map((r) => r.id),
          ).confirm(reviewedAtMs: BigInt.one, appVersion: 'catalog-smoke'),
        );
        await workspace.repository.saveManual(command);
        final branch = (await workspace.repository.branches()).single;
        final product = ProductDocument(
          product: ProductSnapshot(
            id: DurableId.generate(),
            storeId: branch.id,
            canonicalName: 'SYNTHETIC MILK',
            packageValue: BigInt.one,
            packageScale: 0,
            packageUnit: QuantityUnit.litre,
          ),
          storeRevision: branch.revision!,
          expectedHead: null,
          reviewedAtMs: BigInt.two,
          appVersion: 'catalog-smoke',
        );
        final mutation = DurableId.generate();
        final saved = await workspace.repository.saveProduct(
          product,
          mutationId: mutation,
        );
        final aliasId = DurableId.generate(),
            aliasMutation = DurableId.generate();
        ProductAliasDocument alias({RevisionId? head, bool active = true}) =>
            ProductAliasDocument(
              alias: ProductAliasSnapshot(
                id: aliasId,
                storeId: branch.id,
                normalizedName: normalizeReceiptNameV1('TEST MILK 1 L'),
                productId: product.product.id,
                isActive: active,
              ),
              storeRevision: branch.revision!,
              productRevision: saved.revision,
              expectedHead: head,
              reviewedAtMs: BigInt.from(3),
              appVersion: 'catalog-smoke',
            );
        final aliasSaved = await workspace.repository.saveAlias(
          alias(),
          mutationId: aliasMutation,
        );
        final prior = await workspace.repository.identity();
        final before = await workspace.repository.exportBackup();
        const password = 'synthetic catalog password';
        final encrypted = await workspace.exportProtected(password);
        final file = File('${directory.path}/synthetic.rrbackup');
        await file.writeAsBytes(encrypted, flush: true);
        final preview = await workspace.prepare(
          await file.readAsBytes(),
          password,
        );
        expect(preview.receipts, 1);
        expect(preview.events, 4);
        await workspace.activate(preview);
        expect(
          (await workspace.repository.identity()).deviceId,
          isNot(prior.deviceId),
        );
        expect(await workspace.repository.exportBackup(), before);
        expect(
          (await workspace.repository.saveProduct(
            product,
            mutationId: mutation,
          )).replayed,
          isTrue,
        );
        expect(
          (await workspace.repository.saveAlias(
            alias(),
            mutationId: aliasMutation,
          )).replayed,
          isTrue,
        );
        final match = (await workspace.repository.matchAlias(
          branch.id,
          '  TEST\tMILK 1 L ',
        ))!;
        expect(match.product.document.product.packageUnit, QuantityUnit.litre);
        expect(match.product.document.product.id, product.product.id);
        expect(
          await workspace.repository.matchAlias(
            DurableId.generate(),
            'TEST MILK 1 L',
          ),
          isNull,
        );
        final off = await workspace.repository.saveAlias(
          alias(head: aliasSaved.revision, active: false),
          mutationId: DurableId.generate(),
        );
        expect(off.revision.origin, preview.restored.identity.deviceId);
        expect(off.revision.sequence, BigInt.one);
        await expectLater(
          workspace.repository.saveAlias(
            alias(head: aliasSaved.revision),
            mutationId: DurableId.generate(),
          ),
          throwsA(
            isA<StorageFailure>().having((e) => e.code, 'code', 'staleCatalog'),
          ),
        );
        await workspace.close();
        workspace = null;
        workspace = await ReceiptWorkspace.open(directory);
        expect(
          await workspace.repository.matchAlias(branch.id, 'TEST MILK 1 L'),
          isNull,
        );
        expect(
          (await workspace.repository.aliases(
            branch.id,
            activeOnly: false,
          )).single.document.alias.isActive,
          isFalse,
        );
        await workspace.repository.verifyIntegrity();
        await workspace.returnToPrevious();
        expect(
          (await workspace.repository.identity()).deviceId,
          prior.deviceId,
        );
        expect(
          await workspace.repository.matchAlias(branch.id, 'TEST MILK 1 L'),
          isNotNull,
        );
        expect(await workspace.repository.exportBackup(), before);
        expect(
          (await workspace.repository.read(receipt.id))!
              .document
              .snapshot
              .items
              .single
              .product,
          isNull,
        );
        await workspace.repository.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await workspace?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('catalog-storage-smoke-')) {
          throw StateError('unexpected_catalog_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
