import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/manual_receipt_page.dart';

import '../test/manual_save_test.dart' show tapKey, enter, review;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native reviewed catalog, explicit alias selection, receipt correction and encrypted recovery',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('catalog-review-smoke-');
      WorkspaceStore? store;
      ReceiptWorkspace? workspace;
      try {
        workspace = await ReceiptWorkspace.open(directory);
        store = WorkspaceStore(workspace);
        final seed = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: 'SYNTHETIC REVIEW BRANCH',
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
        await store.saveManual(
          ReviewedReceipt.manual(
            current: seed,
            expectedHeads: const [],
            confirmation:
                ManualReviewChecks(
                  snapshot: seed,
                  expectedHeads: const [],
                  mutationId: DurableId.generate(),
                  branchReviewed: true,
                  dateReviewed: true,
                  totalReviewed: true,
                  reviewedRowIds: seed.items.map((r) => r.id),
                ).confirm(
                  reviewedAtMs: BigInt.one,
                  appVersion: 'catalog-review-smoke',
                ),
          ),
        );
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => store!),
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'open-catalog');
        await tapKey(tester, 'catalog-branch');
        await tester.tap(find.text(seed.branch.name).last);
        await tester.pumpAndSettle();
        await tapKey(tester, 'catalog-add');
        await enter(tester, 'catalog-name', 'SYNTHETIC NATIVE MILK');
        await tapKey(tester, 'catalog-reviewed');
        await tapKey(tester, 'catalog-save');
        final branch = (await store.branches()).single;
        final product = (await store.products(branch.id)).single;
        await tester.tap(find.text('Kuittinimet'));
        await tester.pumpAndSettle();
        await tapKey(tester, 'catalog-add');
        await enter(tester, 'catalog-name', 'TEST MILK 1 L');
        await tester.tap(find.text('Valitse tuote'));
        await tester.pumpAndSettle();
        await tapKey(
          tester,
          'pick-product-${product.document.product.id.value}',
        );
        await tapKey(tester, 'catalog-reviewed');
        await tapKey(tester, 'catalog-save');
        expect(
          (await store.aliases(branch.id)).single.document.alias.normalizedName,
          'test milk 1 l',
        );
        Navigator.of(tester.element(find.text('Tuotteet ja kuittinimet')))
            .pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lisää kuitti käsin'));
        await tester.pumpAndSettle();
        await tapKey(tester, 'manual-branch');
        await tester.tap(find.text(branch.name).last);
        await tester.pumpAndSettle();
        await enter(tester, 'manual-date', '17.11.2026');
        await enter(tester, 'manual-total', '2,00');
        await enter(tester, 'manual-row-name-0', 'TEST MILK 1 L');
        await enter(tester, 'manual-row-amount-0', '2,00');
        await tester.ensureVisible(find.byKey(const Key('manual-product-0')));
        await tester.tap(find.text('Valitse tuote'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('product-suggestion')), findsOneWidget);
        await tapKey(tester, 'product-suggestion');
        await review(tester);
        await tapKey(tester, 'manual-save');
        await tapKey(tester, 'confirm-save');
        for (
          var attempt = 0;
          attempt < 100 && find.text('Kuittihistoria').evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        final linked = (await store.history()).firstWhere(
          (r) => r.document.snapshot.id != seed.id,
        );
        final row = linked.document.snapshot.items.single;
        expect(row.product!.id, product.document.product.id);
        expect(row.cents, BigInt.from(200));
        Navigator.of(tester.element(find.text('Kuittihistoria'))).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                ManualReceiptPage.correction(store: store!, receipt: linked),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('manual-product-0')));
        await tester.tap(find.text('Valitse tuote'));
        await tester.pumpAndSettle();
        await tapKey(tester, 'unlink-product');
        await review(tester);
        await tapKey(tester, 'manual-save');
        await tapKey(tester, 'confirm-save');
        final corrected = (await store.history()).firstWhere(
          (r) => r.document.snapshot.id == linked.document.snapshot.id,
        );
        expect(corrected.document.snapshot.items.single.id, row.id);
        expect(corrected.document.snapshot.items.single.name, row.name);
        expect(corrected.document.snapshot.items.single.product, isNull);
        expect(corrected.document.review.expectedHeads, [linked.revision]);
        const password = 'synthetic native catalog review password';
        final bytes = await workspace.repository.exportBackup();
        final preview = await store.prepareProtected(
          await store.exportProtected(password),
          password,
        );
        await store.activateBackup(preview);
        expect(await workspace.repository.exportBackup(), bytes);
        await workspace.repository.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await store?.close();
        if (store == null) await workspace?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('catalog-review-smoke-')) {
          throw StateError('unexpected_catalog_review_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
