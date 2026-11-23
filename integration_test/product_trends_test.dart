import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/purchase_summary_view.dart';

import '../test/support/navigation.dart';
import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native exact product trends, interval drill-down and encrypted recovery',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('product-trends-smoke-');
      WorkspaceStore? active;
      try {
        final store = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        final branchId = DurableId.generate(), productId = DurableId.generate();
        final seed = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(id: branchId, name: 'SYNTHETIC TREND BRANCH'),
          date: StoredReceiptDate.parse('15.11.2026'),
          totalCents: BigInt.from(100),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SEED',
              kind: LineKind.product,
              cents: BigInt.from(100),
            ),
          ],
        );
        await store.saveManual(approve(seed));
        final branch = (await store.branches()).single;
        await store.saveProduct(
          ProductDocument(
            product: ProductSnapshot(
              id: productId,
              storeId: branch.id,
              canonicalName: 'SYNTHETIC TREND MILK',
              category: 'Ruoka ja juoma',
            ),
            storeRevision: branch.revision!,
            expectedHead: null,
            reviewedAtMs: BigInt.one,
            appVersion: 'product-trends-smoke',
          ),
          mutationId: DurableId.generate(),
        );
        final product = (await store.readProduct(productId))!;
        final originals = <StoredReceipt>[];
        for (final data in [
          (16, 2, 400, -100, true),
          (17, 3, 900, 0, true),
          (18, -1, -300, 0, true),
          (19, 1, 500, 0, false),
        ]) {
          final row = ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'SYNTHETIC PURCHASE',
            kind: LineKind.product,
            cents: BigInt.from(data.$3),
            product: product.link,
            quantityValue: data.$5 ? BigInt.from(data.$2) : null,
            quantityScale: data.$5 ? 0 : null,
            quantityUnit: data.$5 ? QuantityUnit.kg : null,
            rateMicros: data.$5
                ? BigInt.from(data.$3 ~/ data.$2 * 10000)
                : null,
          );
          final rows = [
            row,
            if (data.$4 < 0)
              ReceiptItemSnapshot(
                id: DurableId.generate(),
                name: 'ITEM DISCOUNT',
                kind: LineKind.discount,
                cents: BigInt.from(data.$4),
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
              name: 'RECEIPT DISCOUNT',
              kind: LineKind.discount,
              cents: BigInt.from(-10),
              discountScope: DiscountScope.receipt,
            ),
          ];
          final snapshot = ReceiptSnapshot(
            id: DurableId.generate(),
            branch: branch,
            date: StoredReceiptDate.parse('${data.$1}.11.2026'),
            totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
            items: rows,
          );
          final result = await store.saveManual(approve(snapshot));
          originals.add(
            StoredReceipt(
              (await store.workspace.repository.read(snapshot.id))!.document,
              result.revision,
            ),
          );
        }
        final before = await store.workspace.repository.exportBackup();
        final boundaryKey = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: ReceiptReaderApp(
              storageOpener: () async => store,
              dashboardClock: () => DateTime.utc(2026, 11, 19, 12),
            ),
          ),
        );
        Future<void> wait(Finder finder) async {
          for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(finder, findsOneWidget);
          await t.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final finder = find.byKey(ValueKey(key));
          if (finder.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              finder,
              300,
              scrollable: find.byType(Scrollable).last,
            );
          }
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          await t.tap(finder);
          await t.pumpAndSettle();
        }

        Future<void> shot(String name, Finder finder) async {
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          if (!Platform.isWindows) return;
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('build/product-trends-windows-$name.png').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        }

        await wait(find.byKey(const Key('home-tab-receipts')));
        await openReceiptManagement(t);
        await tap('open-catalog');
        await tap('catalog-branch');
        await t.tap(find.text(branch.name).last);
        await t.pumpAndSettle();
        await tap('product-history-${productId.value}');
        await wait(
          find.text('Ostomäärällä painotettu keskihinta: 2,4000 €/kg'),
        );
        expect(
          find.text('Muutos ensimmäisestä viimeiseen ostopäivään: +100,0 %'),
          findsOneWidget,
        );
        final summary = t
            .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
            .summary;
        expect(summary.effectiveCents, BigInt.from(1400));
        expect(summary.spendingBuckets.map((b) => b.effectiveCents), [
          BigInt.from(300),
          BigInt.from(900),
          BigInt.from(-300),
          BigInt.from(500),
        ]);
        await shot(
          'spending',
          find.byKey(const Key('purchase-spending-chart')),
        );
        await shot(
          'prices',
          find.text('Ostomäärällä painotettu keskihinta: 2,4000 €/kg'),
        );
        await tap('purchase-spending-details');
        final day = purchaseCalendarDay(StoredReceiptDate.parse('18.11.2026'));
        await tap('purchase-spending-range-$day');
        await wait(find.text('Ostorivejä yhteensä: 1'));
        expect(
          t
              .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
              .summary
              .groups,
          isEmpty,
        );
        await tap('purchases-reset-range');
        await wait(
          find.text('Ostomäärällä painotettu keskihinta: 2,4000 €/kg'),
        );
        expect(await store.workspace.repository.exportBackup(), before);
        for (final original in originals) {
          expect(
            ReceiptDocumentCodec.encode(
              (await store.workspace.repository.read(
                original.document.snapshot.id,
              ))!.document,
            ),
            ReceiptDocumentCodec.encode(original.document),
          );
        }
        final backup = await store.exportProtected(
          'synthetic product trends password',
        );
        final changed = originals[1];
        await store.saveManual(
          ReviewedReceipt.productLinks(
            confirmation:
                ProductLinkReviewChecks(
                  base: changed.document,
                  expectedHead: changed.revision,
                  selections: {changed.document.snapshot.items.first.id: null},
                  mutationId: DurableId.generate(),
                ).confirm(
                  reviewedAtMs: BigInt.from(3000),
                  appVersion: 'product-trends-smoke',
                ),
          ),
        );
        await tap('purchases-refresh');
        await wait(
          find.text('Ostomäärällä painotettu keskihinta: 1,5000 €/kg'),
        );
        final preview = await store.prepareProtected(
          backup,
          'synthetic product trends password',
        );
        await store.activateBackup(preview);
        await tap('purchases-refresh');
        await wait(
          find.text('Ostomäärällä painotettu keskihinta: 2,4000 €/kg'),
        );
        expect(await store.workspace.repository.exportBackup(), before);
        await t.pumpWidget(const SizedBox());
        await store.close();
        active = null;
        final reopened = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        final recovered = await reopened.purchaseHistory(branch.id, productId);
        expect(recovered.summary.groups.single.weightedMean.euros, '2,4000');
        expect(
          recovered.summary.groups.single.changeTenthsPercent,
          BigInt.from(1000),
        );
        expect(recovered.summary.effectiveCents, BigInt.from(1400));
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await active?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('product-trends-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
