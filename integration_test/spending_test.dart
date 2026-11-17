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
import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native spending, full totals, filters and encrypted dataset replacement',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('spending-smoke-');
      WorkspaceStore? store;
      try {
        final workspace = await ReceiptWorkspace.open(directory);
        final active = WorkspaceStore(workspace);
        store = active;
        ReceiptBranch branch = ReceiptBranch(
          id: DurableId.generate(),
          name: 'SYNTHETIC SPENDING BRANCH',
        );
        ReceiptSnapshot receipt({
          int cents = 200,
          String date = '17.11.2026',
          ReceiptBranch? selected,
        }) => ReceiptSnapshot(
          id: DurableId.generate(),
          branch: selected ?? branch,
          date: StoredReceiptDate.parse(date),
          totalCents: BigInt.from(cents),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'UNLINKED',
              kind: LineKind.product,
              cents: BigInt.from(cents),
            ),
          ],
        );
        for (var i = 0; i < 32; i++) {
          await active.saveManual(approve(receipt()));
          if (i == 0) branch = (await active.branches()).single;
        }
        final other = ReceiptBranch(
          id: DurableId.generate(),
          name: 'SYNTHETIC CREDIT BRANCH',
        );
        await active.saveManual(
          approve(
            receipt(cents: -50, date: '31.10.2026 23:59:59', selected: other),
          ),
        );
        final product = ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'UNLINKED PRODUCT',
          kind: LineKind.product,
          cents: BigInt.from(1000),
        );
        final rows = [
          product,
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'DEPOSIT',
            kind: LineKind.deposit,
            parentItemId: product.id,
            cents: BigInt.from(40),
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'RECEIPT SALE',
            kind: LineKind.discount,
            discountScope: DiscountScope.receipt,
            cents: BigInt.from(-100),
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'RETURN',
            kind: LineKind.product,
            cents: BigInt.from(-200),
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'REVIEWED ADJUSTMENT',
            kind: LineKind.adjustment,
            cents: BigInt.from(10),
            adjustmentReason: 'Synthetic checked difference',
          ),
        ];
        final mixed = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: branch,
          date: StoredReceiptDate.parse('17.11.2026 23:59:59'),
          totalCents: BigInt.from(750),
          items: rows,
        );
        final saved = await active.saveManual(approve(mixed));
        final before = await workspace.repository.exportBackup();
        await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => active));
        await t.pumpAndSettle();
        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(finder, findsOneWidget);
          await t.pumpAndSettle();
        }

        await waitFor(find.byKey(const Key('open-spending')));
        await tapKey(t, 'open-spending');
        await waitFor(find.text('Kuittien loppusummat yhteensä: 71,00 €'));
        expect(find.text('Kuitteja: 34'), findsOneWidget);
        expect(
          find.text('Kuitteja, joilla on tarkistettu oikaisu: 1'),
          findsOneWidget,
        );
        expect(await workspace.repository.exportBackup(), before);
        await tapKey(t, 'spending-filter');
        await waitFor(find.byKey(const Key('history-filter-apply')));
        await enter(t, 'history-filter-from', '17.11.2026');
        await enter(t, 'history-filter-through', '17.11.2026');
        // Select the branch without changing the inclusive date bounds.
        await tapKey(t, 'history-filter-branch');
        await t.tap(find.text(branch.name).last);
        await t.pumpAndSettle();
        await tapKey(t, 'history-filter-apply');
        await waitFor(find.text('Kuittien loppusummat yhteensä: 71,50 €'));
        final backup = await active.exportProtected(
          'synthetic-spending-test-passphrase',
        );
        final changedRows = [
          ReceiptItemSnapshot(
            id: product.id,
            name: product.name,
            kind: LineKind.product,
            cents: BigInt.from(900),
          ),
          ...rows.skip(1),
        ];
        await active.saveManual(
          approve(
            ReceiptSnapshot(
              id: mixed.id,
              branch: branch,
              date: mixed.date,
              totalCents: BigInt.from(650),
              items: changedRows,
            ),
            heads: [saved.revision],
          ),
        );
        await tapKey(t, 'spending-refresh');
        await waitFor(find.text('Kuittien loppusummat yhteensä: 70,50 €'));
        final candidate = await active.prepareProtected(
          backup,
          'synthetic-spending-test-passphrase',
        );
        final activation = active.activateBackup(candidate);
        // The queued read must resolve the repository after replacement completes.
        final queued = active.spendingSummary();
        await activation;
        expect((await queued).totals.totalCents, BigInt.from(7100));
        await tapKey(t, 'spending-refresh');
        await waitFor(find.text('Kuittien loppusummat yhteensä: 71,50 €'));
        final restored = (await workspace.repository.read(mixed.id))!;
        await active.deleteReceipt(
          ReceiptDeletionChecks(
            document: restored.document,
            expectedHead: restored.revision,
            mutationId: DurableId.generate(),
            receiptReviewed: true,
          ).confirm(
            deletedAtMs: BigInt.from(2000),
            appVersion: 'spending-smoke',
          ),
        );
        await tapKey(t, 'spending-refresh');
        await waitFor(find.text('Kuittien loppusummat yhteensä: 64,00 €'));
        await t.pumpWidget(const SizedBox());
        await active.close();
        store = null;
        final reopened = WorkspaceStore(await ReceiptWorkspace.open(directory));
        store = reopened;
        expect(
          (await reopened.spendingSummary()).totals.totalCents,
          BigInt.from(6350),
        );
        await reopened.returnToPrevious();
        expect(
          (await reopened.spendingSummary()).totals.totalCents,
          BigInt.from(7000),
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('spending-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
