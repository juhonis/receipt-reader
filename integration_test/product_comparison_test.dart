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
import 'package:receipt_reader/product_comparison_page.dart';
import 'package:receipt_reader/purchase_history_page.dart';

import '../test/support/navigation.dart';
import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'explicit cross-store prices, historical packages and encrypted recovery',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('product-comparison-smoke-');
      WorkspaceStore? active;
      try {
        final store = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        Future<void> seedBranch(String name) async {
          await store.saveManual(
            approve(
              ReceiptSnapshot(
                id: DurableId.generate(),
                branch: ReceiptBranch(id: DurableId.generate(), name: name),
                date: StoredReceiptDate.parse('1.11.2026'),
                totalCents: BigInt.zero,
                items: [
                  ReceiptItemSnapshot(
                    id: DurableId.generate(),
                    name: 'SYNTHETIC SEED',
                    kind: LineKind.product,
                    cents: BigInt.zero,
                  ),
                ],
              ),
            ),
          );
        }

        await seedBranch('DEMO A');
        await seedBranch('DEMO B');
        final branches = await store.branches();
        Future<StoredProduct> product(
          ReceiptBranch branch,
          int size, {
          StoredProduct? previous,
        }) async {
          final doc = ProductDocument(
            product: ProductSnapshot(
              id: previous?.link.id ?? DurableId.generate(),
              storeId: branch.id,
              canonicalName: 'DEMO COFFEE',
              comparisonKey: 'DEMO Kahvi',
              category: 'Ruoka ja juoma',
              packageValue: BigInt.from(size),
              packageScale: 3,
              packageUnit: QuantityUnit.kg,
            ),
            storeRevision: branch.revision!,
            expectedHead: previous?.revision,
            reviewedAtMs: BigInt.one,
            appVersion: 'comparison-smoke',
          );
          await store.saveProduct(doc, mutationId: DurableId.generate());
          return (await store.readProduct(doc.product.id))!;
        }

        final a = await product(branches[0], 500),
            b = await product(branches[1], 1000);
        for (final values in [
          (a, 2, 600, 2),
          (a, 1, 350, 17),
          (b, 1, 650, 3),
          (b, 2, 1200, 18),
          (a, -1, -300, 19),
        ]) {
          final p = values.$1, q = values.$2, cents = values.$3;
          final row = ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'DEMO COFFEE',
            kind: LineKind.product,
            cents: BigInt.from(cents),
            quantityValue: BigInt.from(q),
            quantityScale: 0,
            quantityUnit: QuantityUnit.piece,
            rateMicros: BigInt.from(cents.abs() * 10000 ~/ q.abs()),
            product: p.link,
          );
          await store.saveManual(
            approve(
              ReceiptSnapshot(
                id: DurableId.generate(),
                branch: branches.firstWhere((v) => v.id == p.link.storeId),
                date: StoredReceiptDate.parse('${values.$4}.11.2026'),
                totalCents: row.cents,
                items: [row],
              ),
            ),
          );
        }
        // Editing today's pack must never rewrite the old saved 500 g purchases.
        await product(branches[0], 1000, previous: a);
        final before = await store.workspace.repository.exportBackup();
        final capture = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: ReceiptReaderApp(
              storageOpener: () async => store,
              dashboardClock: () => DateTime.utc(2026, 11, 24, 12),
            ),
          ),
        );
        Future<void> wait(Finder f) async {
          for (var i = 0; i < 400 && f.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(f, findsOneWidget);
          await t.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final f = find.byKey(ValueKey(key));
          if (f.evaluate().isEmpty) {
            final scroll = find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last;
            t.state<ScrollableState>(scroll).position.jumpTo(0);
            await t.pumpAndSettle();
            if (f.evaluate().isEmpty) {
              await t.scrollUntilVisible(f, 250, scrollable: scroll);
            }
          }
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
        }

        Future<void> shot() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final img = await boundary.toImage();
          try {
            final bytes = (await img.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final target = Platform.isWindows
                ? File('build/product-comparison-windows.png')
                : File('${support.path}/product-comparison-android.png');
            await target.writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            img.dispose();
          }
        }

        await wait(find.byKey(const Key('home-tab-receipts')));
        await openReceiptManagement(t);
        await tap('open-catalog');
        await tap('catalog-branch');
        await t.tap(find.text(branches[0].name).last);
        await t.pumpAndSettle();
        await tap('product-history-${a.link.id.value}');
        await tap('purchases-compare');
        await wait(find.byKey(const Key('comparison-unit-kg')));
        final series = t
            .widget<ComparisonUnitView>(find.byType(ComparisonUnitView))
            .series;
        expect(series.map((g) => g.weightedMean.euros), ['6,1667', '6,3333']);
        expect(
          (await store.productComparison(a.link.id)).summary.returnRows,
          1,
        );
        await shot();
        expect(await store.workspace.repository.exportBackup(), before);
        await tap('comparison-range');
        await t.enterText(find.byKey(const Key('purchase-from')), '17.11.2026');
        await t.enterText(
          find.byKey(const Key('purchase-through')),
          '18.11.2026',
        );
        await tap('purchase-range-apply');
        await wait(find.byKey(const Key('comparison-unit-kg')));
        expect(
          t
              .widget<ComparisonUnitView>(find.byType(ComparisonUnitView))
              .series
              .map((g) => g.weightedMean.euros),
          ['6,0000', '7,0000'],
        );
        await tap('comparison-store-${branches[0].id.value}-kg');
        await tap('comparison-member-${a.link.id.value}');
        final history = t.widget<PurchaseHistoryPage>(
          find.byType(PurchaseHistoryPage).last,
        );
        expect(history.initialRange!.fromDate!.day, 17);
        expect(history.initialRange!.throughDate!.day, 18);
        Navigator.pop(t.element(find.byType(PurchaseHistoryPage).last));
        await t.pumpAndSettle();
        await tap('comparison-reset-range');
        const password = 'synthetic comparison backup password';
        final protected = await store.exportProtected(password);
        await tap('comparison-edit');
        await t.enterText(find.byKey(const Key('catalog-comparison')), '');
        await tap('catalog-reviewed');
        await tap('catalog-save');
        await wait(find.byKey(const Key('comparison-edit')));
        expect(find.byType(ComparisonUnitView), findsNothing);
        final candidate = await store.prepareProtected(protected, password);
        await store.activateBackup(candidate);
        await tap('comparison-refresh');
        await wait(find.byKey(const Key('comparison-unit-kg')));
        expect(
          t
              .widget<ComparisonUnitView>(find.byType(ComparisonUnitView))
              .series
              .first
              .weightedMean
              .euros,
          '6,1667',
        );
        expect(await store.workspace.repository.exportBackup(), before);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await active.close();
        active = null;
        final reopened = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        expect(
          (await reopened.productComparison(a.link.id)).summary.comparableRows,
          4,
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await active?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('product-comparison-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
