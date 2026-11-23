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
import 'package:receipt_reader/catalog_page.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/spending_dashboard_page.dart';

import '../packages/receipt_storage/test/support/released_database.dart';
import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native v6 upgrade, reviewed categories, history and protected recovery',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('category-smoke-');
      WorkspaceStore? active;
      try {
        final sourceFile = File('${directory.path}/seed.sqlite');
        final source = await ReceiptRepository.open(sourceFile);
        final branchId = DurableId.generate(), productId = DurableId.generate();
        ReceiptSnapshot receipt(
          ReceiptBranch branch, {
          ReceiptProductLink? link,
        }) => ReceiptSnapshot(
          id: DurableId.generate(),
          branch: branch,
          date: StoredReceiptDate.parse('18.11.2026'),
          totalCents: BigInt.from(200),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC CATEGORY PRODUCT',
              kind: LineKind.product,
              cents: BigInt.from(200),
              product: link,
            ),
          ],
        );
        await source.saveManual(
          approve(
            receipt(
              ReceiptBranch(id: branchId, name: 'SYNTHETIC CATEGORY BRANCH'),
            ),
          ),
        );
        final branch = (await source.branches()).single;
        final created = await source.saveProduct(
          ProductDocument(
            product: ProductSnapshot(
              id: productId,
              storeId: branch.id,
              canonicalName: 'SYNTHETIC PRODUCT',
            ),
            storeRevision: branch.revision!,
            expectedHead: null,
            reviewedAtMs: BigInt.one,
            appVersion: 'category-smoke',
          ),
          mutationId: DurableId.generate(),
        );
        final link = ReceiptProductLink(
          id: productId,
          storeId: branch.id,
          revision: created.revision,
        );
        late StoredReceipt old;
        for (var i = 0; i < 3; i++) {
          final value = receipt(branch, link: link);
          await source.saveManual(approve(value));
          old = (await source.read(value.id))!;
        }
        final oldBytes = ReceiptDocumentCodec.encode(old.document);
        final plain = await source.exportBackup();
        await source.close();
        await copyToReleasedSchema(
          sourceFile,
          File('${directory.path}/receipts.sqlite'),
          6,
        );
        final workspace = await ReceiptWorkspace.open(directory);
        final store = active = WorkspaceStore(workspace);
        expect(await workspace.repository.exportBackup(), plain);
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
          var finder = find.byKey(ValueKey(key));
          if (finder.evaluate().isEmpty) {
            final scroll = find
                .descendant(
                  of: find.byType(SpendingDashboardPage),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  ),
                )
                .first;
            await t.scrollUntilVisible(finder, -400, scrollable: scroll);
          }
          if (key == 'catalog-reviewed') {
            finder = find.descendant(
              of: finder,
              matching: find.byType(Checkbox),
            );
          }
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          await t.tap(finder);
          await t.pumpAndSettle();
        }

        Future<void> shot(String label) async {
          if (!Platform.isWindows) return;
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('build/category-windows-$label.png').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        }

        await wait(find.text('Luokiteltuja tuoterivejä: 0 / 4'));
        await tap('home-tab-receipts');
        await tap('open-catalog');
        await tap('catalog-branch');
        await t.tap(find.text(branch.name).last);
        await t.pumpAndSettle();
        await tap('catalog-product-${productId.value}');
        await t.enterText(
          find.byKey(const Key('catalog-category')),
          'Ruoka ja juoma',
        );
        await t.pumpAndSettle();
        await shot('editor');
        await tap('catalog-reviewed');
        await tap('catalog-save');
        Navigator.of(t.element(find.byType(CatalogPage))).pop();
        await t.pumpAndSettle();
        await tap('home-tab-dashboard');
        await wait(find.text('Luokiteltuja tuoterivejä: 3 / 4'));
        await t.ensureVisible(find.byKey(const Key('dashboard-categories')));
        await t.pumpAndSettle();
        await shot('dashboard');
        expect(
          ReceiptDocumentCodec.encode(
            (await workspace.repository.read(old.document.snapshot.id))!
                .document,
          ),
          oldBytes,
        );
        await tap('category-group-product-Ruoka ja juoma');
        await wait(
          find.byKey(ValueKey('history-${old.document.snapshot.id.value}')),
        );
        Navigator.of(t.element(find.byType(HistoryPage))).pop();
        await t.pumpAndSettle();
        final encrypted = await store.exportProtected(
          'synthetic-category-test-password',
        );
        final current = (await store.readProduct(productId))!;
        await store.saveProduct(
          ProductDocument(
            product: ProductSnapshot(
              id: productId,
              storeId: branch.id,
              canonicalName: 'SYNTHETIC PRODUCT',
              category: 'Hygienia ja terveys',
            ),
            storeRevision: branch.revision!,
            expectedHead: current.revision,
            reviewedAtMs: BigInt.from(2000),
            appVersion: 'category-smoke',
          ),
          mutationId: DurableId.generate(),
        );
        await tap('dashboard-refresh');
        await wait(
          find.byKey(
            const ValueKey('category-group-product-Hygienia ja terveys'),
          ),
        );
        final preview = await store.prepareProtected(
          encrypted,
          'synthetic-category-test-password',
        );
        final activation = store.activateBackup(preview);
        final q = SpendingDashboardQuery(
          unit: SpendingPeriodUnit.month,
          anchor: StoredReceiptDate.parse('18.11.2026'),
          today: StoredReceiptDate.parse('18.11.2026'),
        );
        final queued = store.spendingDashboard(q);
        await activation;
        final summary = (await queued).categories;
        expect(
          summary.groups
              .singleWhere((g) => g.category.name == 'Ruoka ja juoma')
              .totalCents,
          BigInt.from(600),
        );
        expect(summary.totalCents, BigInt.from(800));
        expect(summary.categorizedProductRows, 3);
        await tap('dashboard-refresh');
        await wait(
          find.byKey(const ValueKey('category-group-product-Ruoka ja juoma')),
        );
        await t.pumpWidget(const SizedBox());
        await store.close();
        active = null;
        final reopened = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        expect(
          (await reopened.readProduct(productId))!.document.product.category,
          'Ruoka ja juoma',
        );
        expect(
          ReceiptDocumentCodec.encode(
            (await reopened.workspace.repository.read(
              old.document.snapshot.id,
            ))!.document,
          ),
          oldBytes,
        );
        await reopened.returnToPrevious();
        expect(
          (await reopened.readProduct(productId))!.document.product.category,
          'Hygienia ja terveys',
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await active?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('category-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
