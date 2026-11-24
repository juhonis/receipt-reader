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
import 'package:receipt_reader/product_spending_view.dart';
import 'package:receipt_reader/product_rankings_page.dart';
import 'package:receipt_reader/purchase_history_page.dart';

import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native product rankings, inherited ranges, branch identities and encrypted recovery',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('product-rankings-smoke-');
      WorkspaceStore? active;
      try {
        final store = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        Future<ReceiptBranch> branch(String address) async {
          final snapshot = ReceiptSnapshot(
            id: DurableId.generate(),
            branch: ReceiptBranch(
              id: DurableId.generate(),
              name: 'SYNTHETIC BRANCH',
              address: address,
            ),
            date: StoredReceiptDate.parse('1.10.2026'),
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
          await store.saveManual(approve(snapshot));
          return (await store.branches()).firstWhere(
            (b) => b.id == snapshot.branch.id,
          );
        }

        final first = await branch('PRIMARY LOCATION'),
            second = await branch('SECONDARY LOCATION');
        Future<StoredProduct> product(ReceiptBranch at, String name) async {
          final id = DurableId.generate();
          await store.saveProduct(
            ProductDocument(
              product: ProductSnapshot(
                id: id,
                storeId: at.id,
                canonicalName: name,
                category: 'Ruoka ja juoma',
              ),
              storeRevision: at.revision!,
              expectedHead: null,
              reviewedAtMs: BigInt.one,
              appVersion: 'rankings-smoke',
            ),
            mutationId: DurableId.generate(),
          );
          return (await store.readProduct(id))!;
        }

        final products = <StoredProduct>[];
        for (var i = 0; i < 32; i++) {
          products.add(
            await product(
              first,
              i < 2 ? 'COMMON PRODUCT' : 'SYNTHETIC PRODUCT $i',
            ),
          );
        }
        final other = await product(second, 'COMMON PRODUCT');
        ReceiptItemSnapshot item(StoredProduct p, int cents) =>
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'PRINTED ALIAS',
              kind: LineKind.product,
              cents: BigInt.from(cents),
              product: p.link,
              quantityValue: cents < 0 ? -BigInt.one : BigInt.one,
              quantityScale: 0,
              quantityUnit: QuantityUnit.piece,
              rateMicros: BigInt.from(cents.abs() * 10000),
            );
        Future<StoredReceipt> save(
          ReceiptBranch at,
          List<ReceiptItemSnapshot> rows,
          String date,
        ) async {
          final snapshot = ReceiptSnapshot(
            id: DurableId.generate(),
            branch: at,
            date: StoredReceiptDate.parse(date),
            totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
            items: rows,
          );
          await store.saveManual(approve(snapshot));
          return (await store.workspace.repository.read(snapshot.id))!;
        }

        final rows = [
          for (var i = 0; i < products.length; i++)
            item(products[i], (i + 1) * 100),
        ];
        rows.add(item(products.first, 100));
        rows.addAll([
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'DISCOUNT',
            kind: LineKind.discount,
            cents: BigInt.from(-25),
            parentItemId: rows.first.id,
            discountScope: DiscountScope.item,
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'UNLINKED',
            kind: LineKind.product,
            cents: BigInt.from(300),
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'DEPOSIT',
            kind: LineKind.deposit,
            cents: BigInt.from(40),
            parentItemId: rows.first.id,
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'RECEIPT DISCOUNT',
            kind: LineKind.discount,
            cents: BigInt.from(-20),
            discountScope: DiscountScope.receipt,
          ),
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'ADJUSTMENT',
            kind: LineKind.adjustment,
            cents: BigInt.from(5),
            adjustmentReason: 'SYNTHETIC CHECKED',
          ),
        ]);
        final main = await save(first, rows, '17.11.2026 23:59:59');
        await save(first, [item(products.last, -200)], '18.11.2026');
        await save(second, [item(other, 500)], '17.11.2026');
        final before = await store.workspace.repository.exportBackup();
        final backup = await store.exportProtected(
          'synthetic product rankings password',
        );
        final boundaryKey = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: ReceiptReaderApp(
              storageOpener: () async => store,
              dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
            ),
          ),
        );
        Future<void> wait(Finder finder) async {
          for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(finder, findsOneWidget);
          await t.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final finder = find.byKey(ValueKey(key));
          if (finder.evaluate().isEmpty) {
            final scroll = find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last;
            t.state<ScrollableState>(scroll).position.jumpTo(0);
            await t.pumpAndSettle();
            if (finder.evaluate().isEmpty) {
              await t.scrollUntilVisible(finder, 350, scrollable: scroll);
            }
          }
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          await t.tap(finder);
          await t.pumpAndSettle();
        }

        Future<void> back(Type type) async {
          Navigator.pop(t.element(find.byType(type)));
          await t.pumpAndSettle();
        }

        Future<void> shot(String name, Finder target) async {
          if (!Platform.isWindows) return;
          await Scrollable.ensureVisible(t.element(target), alignment: .05);
          await t.pumpAndSettle();
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('build/product-rankings-windows-$name.png').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        }

        await wait(find.byType(ProductSpendingView));
        var summary = t
            .widget<ProductSpendingView>(find.byType(ProductSpendingView))
            .summary;
        expect(summary.groups.length, 33);
        expect(summary.linkedRows, 35);
        expect(summary.productRows, 36);
        expect(summary.linkedCents, BigInt.from(53175));
        expect(summary.receiptTotalCents, BigInt.from(53500));
        await shot('summary', find.byKey(const Key('dashboard-products')));
        final top = summary.groups.first;
        await tap('dashboard-product-${top.productId.value}');
        await wait(find.byType(PurchaseHistoryPage));
        expect(
          t
              .widget<PurchaseHistoryPage>(find.byType(PurchaseHistoryPage))
              .initialRange!
              .fromDate!
              .day,
          1,
        );
        final data = await store.purchaseHistory(
          top.branch.id,
          top.productId,
          range: t
              .widget<PurchaseHistoryPage>(find.byType(PurchaseHistoryPage))
              .initialRange,
        );
        expect(data.summary.effectiveCents, top.totalCents);
        expect(data.summary.totalRows, top.rowCount);
        await back(PurchaseHistoryPage);
        await wait(find.byType(ProductSpendingView));
        await tap('product-ranking-all');
        await wait(find.byType(ProductRankingsPage));
        expect(find.text('Tuotteet: 1–30 / 33'), findsOneWidget);
        await shot('list', find.byKey(const Key('product-rankings-range')));
        await tap('product-rankings-next');
        expect(find.text('Tuotteet: 31–33 / 33'), findsOneWidget);
        await tap('ranked-product-${products.first.link.id.value}');
        await wait(find.byType(PurchaseHistoryPage));
        final scope = t
            .widget<PurchaseHistoryPage>(find.byType(PurchaseHistoryPage))
            .initialRange!;
        expect(scope.fromDate!.day, 1);
        expect(scope.throughDate!.day, 18);
        final selected = await store.purchaseHistory(
          first.id,
          products.first.link.id,
          range: scope,
        );
        expect(selected.summary.effectiveCents, BigInt.from(175));
        expect(selected.summary.groups.single.weightedMean.euros, '0,8750');
        expect(await store.workspace.repository.exportBackup(), before);
        await store.saveManual(
          ReviewedReceipt.productLinks(
            confirmation:
                ProductLinkReviewChecks(
                  base: main.document,
                  expectedHead: main.revision,
                  selections: {
                    for (final row in main.document.snapshot.items)
                      if (row.product?.id == products.first.link.id)
                        row.id: null,
                  },
                  mutationId: DurableId.generate(),
                ).confirm(
                  reviewedAtMs: BigInt.from(3000),
                  appVersion: 'rankings-smoke',
                ),
          ),
        );
        await back(PurchaseHistoryPage);
        await wait(find.text('Tuotteet: 1–30 / 32'));
        await back(ProductRankingsPage);
        await wait(find.byType(ProductSpendingView));
        summary = t
            .widget<ProductSpendingView>(find.byType(ProductSpendingView))
            .summary;
        expect(summary.groups.length, 32);
        expect(summary.unlinkedCents, BigInt.from(475));
        expect(summary.receiptTotalCents, BigInt.from(53500));
        final preview = await store.prepareProtected(
          backup,
          'synthetic product rankings password',
        );
        await store.activateBackup(preview);
        await tap('dashboard-refresh');
        await wait(find.byType(ProductSpendingView));
        expect(
          t
              .widget<ProductSpendingView>(find.byType(ProductSpendingView))
              .summary
              .groups
              .length,
          33,
        );
        expect(await store.workspace.repository.exportBackup(), before);
        await tap('dashboard-branch');
        await tap('dashboard-branch-${second.id.value}');
        await wait(find.byType(ProductSpendingView));
        summary = t
            .widget<ProductSpendingView>(find.byType(ProductSpendingView))
            .summary;
        expect(summary.groups.single.productId, other.link.id);
        expect(summary.linkedCents, BigInt.from(500));
        await tap('dashboard-product-${other.link.id.value}');
        await wait(find.byType(PurchaseHistoryPage));
        expect(
          t
              .widget<PurchaseHistoryPage>(find.byType(PurchaseHistoryPage))
              .product
              .link
              .storeId,
          second.id,
        );
        await back(PurchaseHistoryPage);
        await wait(find.byType(ProductSpendingView));
        await tap('dashboard-branch');
        await tap('dashboard-all-branches');
        await tap('dashboard-custom');
        await t.enterText(
          find.byKey(const Key('dashboard-custom-from')),
          '18.11.2026',
        );
        await t.enterText(
          find.byKey(const Key('dashboard-custom-through')),
          '18.11.2026',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        await tap('dashboard-custom-apply');
        await wait(find.byType(ProductSpendingView));
        summary = t
            .widget<ProductSpendingView>(find.byType(ProductSpendingView))
            .summary;
        expect(summary.groups.single.totalCents, BigInt.from(-200));
        await tap('dashboard-product-${products.last.link.id.value}');
        await wait(find.byType(PurchaseHistoryPage));
        final initial = t
            .widget<PurchaseHistoryPage>(find.byType(PurchaseHistoryPage))
            .initialRange!;
        expect(initial.fromDate!.day, 18);
        expect(initial.throughDate!.day, 18);
        final returns = await store.purchaseHistory(
          first.id,
          products.last.link.id,
          range: initial,
        );
        expect(returns.summary.returnRows, 1);
        expect(returns.summary.effectiveCents, BigInt.from(-200));
        await t.pumpWidget(const SizedBox());
        await store.close();
        active = null;
        final reopened = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        final result = await reopened.spendingDashboard(
          SpendingDashboardQuery(
            unit: SpendingPeriodUnit.month,
            anchor: StoredReceiptDate.parse('18.11.2026'),
            today: StoredReceiptDate.parse('18.11.2026'),
          ),
        );
        expect(result.products.groups.length, 33);
        expect(result.products.linkedCents, BigInt.from(53175));
        expect(
          ReceiptDocumentCodec.encode(
            (await reopened.workspace.repository.read(
              main.document.snapshot.id,
            ))!.document,
          ),
          ReceiptDocumentCodec.encode(main.document),
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await active?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('product-rankings-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
