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
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/product_picker.dart';

import '../test/manual_save_test.dart' show review;
import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native inline catalog creation, explicit linking and saved category editing',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('inline-catalog-smoke-');
      WorkspaceStore? active;
      try {
        final store = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        final seed = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: 'SYNTHETIC INLINE BRANCH',
          ),
          date: StoredReceiptDate.parse('18.11.2026'),
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
          for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(finder, findsOneWidget);
          await t.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          var finder = find.byKey(ValueKey(key));
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

        Future<void> enter(String key, String value) async {
          final finder = find.byKey(ValueKey(key));
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          await t.enterText(finder, value);
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
        }

        Future<void> shot(String name) async {
          if (!Platform.isWindows) return;
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('build/inline-catalog-windows-$name.png').writeAsBytes(
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
        await tap('home-tab-receipts');
        final manual = find.text('Lisää kuitti käsin');
        await t.ensureVisible(manual);
        await t.tap(manual);
        await t.pumpAndSettle();
        await tap('manual-branch');
        await t.tap(find.text(seed.branch.name).last);
        await t.pumpAndSettle();
        await enter('manual-date', '18.11.2026');
        await enter('manual-total', '2,00');
        await enter('manual-row-name-0', 'SYNTHETIC INLINE MILK');
        await enter('manual-row-amount-0', '2,00');
        final picker = find.descendant(
          of: find.byKey(const Key('manual-product-0')),
          matching: find.byType(TextButton),
        );
        await t.ensureVisible(picker);
        await t.tap(picker);
        await t.pumpAndSettle();
        await wait(find.byKey(const Key('picker-create-product')));
        await tap('picker-create-product');
        expect(
          t
              .widget<TextField>(find.byKey(const Key('catalog-name')))
              .controller!
              .text,
          'SYNTHETIC INLINE MILK',
        );
        await enter('catalog-category', 'Ruoka ja juoma');
        await tap('catalog-reviewed');
        await tap('catalog-save');
        await wait(find.byKey(const Key('product-recent')));
        expect(
          t
              .widget<ReceiptProductSelector>(
                find.byKey(const Key('manual-product-0')),
              )
              .link,
          isNull,
        );
        final branch = (await store.branches()).single;
        final product = (await store.products(branch.id)).single;
        await shot('picker');
        await tap('product-recent');
        await review(t);
        await tap('manual-save');
        await tap('confirm-save');
        await wait(find.byType(HistoryPage));
        final linked = (await store.history()).singleWhere(
          (r) => r.document.snapshot.id != seed.id,
        );
        expect(
          linked.document.snapshot.items.single.product!.id,
          product.document.product.id,
        );
        final bytes = ReceiptDocumentCodec.encode(linked.document);
        await tap('history-${linked.document.snapshot.id.value}');
        await tap('receipt-edit-product-${product.document.product.id.value}');
        await enter('catalog-category', 'Hygienia ja terveys');
        await tap('catalog-reviewed');
        await tap('catalog-save');
        await wait(find.text('Tuoteluokka: Hygienia ja terveys'));
        await shot('detail');
        final query = SpendingDashboardQuery(
          unit: SpendingPeriodUnit.month,
          anchor: StoredReceiptDate.parse('18.11.2026'),
          today: StoredReceiptDate.parse('18.11.2026'),
        );
        final dashboard = await store.spendingDashboard(query);
        expect(dashboard.categories.totalCents, BigInt.from(400));
        expect(
          dashboard.categories.groups
              .singleWhere((g) => g.category.name == 'Hygienia ja terveys')
              .totalCents,
          BigInt.from(200),
        );
        expect(
          ReceiptDocumentCodec.encode(
            (await store.workspace.repository.read(
              linked.document.snapshot.id,
            ))!.document,
          ),
          bytes,
        );
        final preview = await store.prepareProtected(
          await store.exportProtected('synthetic inline catalog password'),
          'synthetic inline catalog password',
        );
        await store.activateBackup(preview);
        await t.pumpWidget(const SizedBox());
        await store.close();
        active = null;
        final reopened = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        expect(
          (await reopened.readProduct(product.document.product.id))!
              .document
              .product
              .category,
          'Hygienia ja terveys',
        );
        expect(
          ReceiptDocumentCodec.encode(
            (await reopened.workspace.repository.read(
              linked.document.snapshot.id,
            ))!.document,
          ),
          bytes,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await active?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('inline-catalog-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
