import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';

import '../test/manual_save_test.dart' show tapKey, enter;

ReviewedReceipt approve(
  ReceiptSnapshot snapshot, {
  List<RevisionId> heads = const [],
}) => ReviewedReceipt.manual(
  current: snapshot,
  expectedHeads: heads,
  confirmation:
      ManualReviewChecks(
        snapshot: snapshot,
        expectedHeads: heads,
        mutationId: DurableId.generate(),
        branchReviewed: true,
        dateReviewed: true,
        totalReviewed: true,
        reviewedRowIds: snapshot.items.map((r) => r.id),
      ).confirm(
        reviewedAtMs: BigInt.from(1000),
        appVersion: 'purchase-history-smoke',
      ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native purchase history, exact prices, correction and encrypted restore',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('purchase-history-smoke-');
      WorkspaceStore? store;
      try {
        final workspace = await ReceiptWorkspace.open(directory);
        store = WorkspaceStore(workspace);
        final seed = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: 'SYNTHETIC HISTORY BRANCH',
          ),
          date: StoredReceiptDate.parse('17.11.2026'),
          totalCents: BigInt.from(200),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SEED',
              kind: LineKind.product,
              cents: BigInt.from(200),
            ),
          ],
        );
        await store.saveManual(approve(seed));
        final branch = (await store.branches()).single;
        final productId = DurableId.generate();
        await store.saveProduct(
          ProductDocument(
            product: ProductSnapshot(
              id: productId,
              storeId: branch.id,
              canonicalName: 'SYNTHETIC PRICE PRODUCT',
            ),
            storeRevision: branch.revision!,
            expectedHead: null,
            reviewedAtMs: BigInt.from(1000),
            appVersion: 'purchase-history-smoke',
          ),
          mutationId: DurableId.generate(),
        );
        final product = (await store.readProduct(productId))!;
        ReceiptSnapshot linked({
          DurableId? id,
          DurableId? rowId,
          int discount = -100,
          String date = '17.11.2026',
        }) {
          final row = ReceiptItemSnapshot(
            id: rowId ?? DurableId.generate(),
            name: 'SYNTHETIC PRICE ROW',
            kind: LineKind.product,
            cents: BigInt.from(400),
            quantityValue: BigInt.from(2),
            quantityScale: 0,
            quantityUnit: QuantityUnit.kg,
            rateMicros: BigInt.from(2000000),
            product: product.link,
          );
          final rows = [
            row,
            if (discount < 0)
              ReceiptItemSnapshot(
                id: DurableId.generate(),
                name: 'SALE',
                kind: LineKind.discount,
                cents: BigInt.from(discount),
                parentItemId: row.id,
                discountScope: DiscountScope.item,
              ),
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'DEPOSIT',
              kind: LineKind.deposit,
              cents: BigInt.from(40),
              parentItemId: row.id,
            ),
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'RECEIPT SALE',
              kind: LineKind.discount,
              cents: BigInt.from(-10),
              discountScope: DiscountScope.receipt,
            ),
          ];
          return ReceiptSnapshot(
            id: id ?? DurableId.generate(),
            branch: branch,
            date: StoredReceiptDate.parse(date),
            items: rows,
            totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
          );
        }

        final first = linked();
        final saved = await store.saveManual(approve(first));
        await store.saveManual(
          approve(linked(discount: 0, date: '16.11.2026')),
        );
        final before = await workspace.repository.exportBackup();
        expect((await store.purchases(branch.id, productId)), hasLength(2));
        await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store!));
        await t.pumpAndSettle();
        await tapKey(t, 'open-catalog');
        await tapKey(t, 'catalog-branch');
        await t.tap(find.text(branch.name).last);
        await t.pumpAndSettle();
        await tapKey(t, 'product-history-${productId.value}');
        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(finder, findsOneWidget);
        }

        final range = find.text(
          'Aikavälin alin ja ylin vertailuhinta: 1,5000–2,0000 €/kg',
        );
        await waitFor(range);
        expect(find.text('Ostorivejä yhteensä: 2'), findsOneWidget);
        await tapKey(t, 'purchases-range');
        await enter(t, 'purchase-from', '16.11.2026');
        await enter(t, 'purchase-through', '16.11.2026');
        await tapKey(t, 'purchase-range-apply');
        await waitFor(find.text('Ostorivejä yhteensä: 1'));
        await waitFor(
          find.text('Aikavälin alin ja ylin vertailuhinta: 2,0000–2,0000 €/kg'),
        );
        await tapKey(t, 'purchases-reset-range');
        await waitFor(range);
        final complete = await store.purchaseHistory(branch.id, productId);
        expect(complete.summary.totalRows, 2);
        expect(
          complete.summary.groups.single.buckets.fold(0, (n, b) => n + b.count),
          2,
        );
        expect(await workspace.repository.exportBackup(), before);
        final backup = await store.exportProtected(
          'synthetic-purchase-test-passphrase',
        );
        // A correction removes the old observation rather than adding a second head.
        await store.saveManual(
          approve(
            linked(id: first.id, rowId: first.items.first.id, discount: -200),
            heads: [saved.revision],
          ),
        );
        await tapKey(t, 'purchases-refresh');
        await waitFor(
          find.text('Aikavälin alin ja ylin vertailuhinta: 1,0000–2,0000 €/kg'),
        );
        final candidate = await store.prepareProtected(
          backup,
          'synthetic-purchase-test-passphrase',
        );
        await store.activateBackup(candidate);
        await tapKey(t, 'purchases-refresh');
        await waitFor(range);
        final restored = (await store.purchases(branch.id, productId)).first;
        expect(restored.purchase.row.id, first.items.first.id);
        expect(restored.purchase.row.cents, BigInt.from(400));
        expect(restored.purchase.effectiveUnitPrice!.euros, '1,5000');
        expect(restored.purchase.depositCents, BigInt.from(40));
        await store.deleteReceipt(
          ReceiptDeletionChecks(
            document: restored.receipt.document,
            expectedHead: restored.receipt.revision,
            mutationId: DurableId.generate(),
            receiptReviewed: true,
          ).confirm(
            deletedAtMs: BigInt.from(2000),
            appVersion: 'purchase-history-smoke',
          ),
        );
        await tapKey(t, 'purchases-refresh');
        await waitFor(find.text('Vertailukelpoisia havaintoja: 1'));
        await t.pumpWidget(const SizedBox());
        await store.close();
        store = null;
        store = WorkspaceStore(await ReceiptWorkspace.open(directory));
        expect((await store.purchases(branch.id, productId)), hasLength(1));
        await store.returnToPrevious();
        expect(
          (await store.purchases(
            branch.id,
            productId,
          )).first.purchase.effectiveUnitPrice!.euros,
          '1,0000',
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('purchase-history-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
