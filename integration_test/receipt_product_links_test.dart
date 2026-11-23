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

import '../packages/receipt_domain/test/ocr_support.dart';
import '../packages/receipt_storage/test/support/released_database.dart';
import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native v7 upgrade, saved OCR/manual links and protected recovery',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('saved-links-smoke-');
      WorkspaceStore? active;
      try {
        final sourceFile = File('${directory.path}/seed.sqlite');
        final source = await ReceiptRepository.open(sourceFile);
        late StoredReceipt ocr, manual;
        late ReceiptBranch branch;
        final productId = DurableId.generate();
        final rowId = DurableId.generate();
        late String ocrBytes, manualBytes;
        late List<int> plain;
        try {
          final initial = OcrFixture().save();
          await source.saveOcr(initial);
          ocr = (await source.read(initial.document.snapshot.id))!;
          ocrBytes = ReceiptDocumentCodec.encode(ocr.document);
          branch = (await source.branches()).single;
          final value = ReceiptSnapshot(
            id: DurableId.generate(),
            branch: branch,
            date: StoredReceiptDate.parse('18.11.2026'),
            totalCents: BigInt.from(175),
            items: [
              ReceiptItemSnapshot(
                id: rowId,
                name: 'SYNTHETIC MILK',
                rawName: 'RAW MILK',
                kind: LineKind.product,
                cents: BigInt.from(200),
                quantityValue: BigInt.one,
                quantityScale: 0,
                quantityUnit: QuantityUnit.piece,
                rateMicros: BigInt.from(2000000),
              ),
              ReceiptItemSnapshot(
                id: DurableId.generate(),
                name: 'SYNTHETIC DISCOUNT',
                kind: LineKind.discount,
                cents: BigInt.from(-25),
                parentItemId: rowId,
                discountScope: DiscountScope.item,
              ),
            ],
          );
          await source.saveManual(approve(value));
          manual = (await source.read(value.id))!;
          manualBytes = ReceiptDocumentCodec.encode(manual.document);
          await source.saveProduct(
            ProductDocument(
              product: ProductSnapshot(
                id: productId,
                storeId: branch.id,
                canonicalName: 'SYNTHETIC CATALOG MILK',
                category: 'Ruoka ja juoma',
              ),
              storeRevision: branch.revision!,
              expectedHead: null,
              reviewedAtMs: BigInt.one,
              appVersion: 'saved-links-smoke',
            ),
            mutationId: DurableId.generate(),
          );
          plain = await source.exportBackup();
        } finally {
          await source.close();
        }
        await copyToReleasedSchema(
          sourceFile,
          File('${directory.path}/receipts.sqlite'),
          7,
        );
        final store = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        expect(await store.workspace.repository.exportBackup(), plain);
        expect(
          ReceiptDocumentCodec.encode(
            (await store.workspace.repository.read(ocr.document.snapshot.id))!
                .document,
          ),
          ocrBytes,
        );
        expect(
          ReceiptDocumentCodec.encode(
            (await store.workspace.repository.read(
              manual.document.snapshot.id,
            ))!.document,
          ),
          manualBytes,
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

        Future<void> pick() async {
          final row = find.byKey(const Key('saved-product-0'));
          if (row.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              row,
              300,
              scrollable: find.byType(Scrollable).last,
            );
          }
          final button = find.descendant(
            of: row,
            matching: find.byType(TextButton),
          );
          await t.ensureVisible(button);
          await t.tap(button);
          await t.pumpAndSettle();
          await wait(find.byKey(ValueKey('pick-product-${productId.value}')));
        }

        await wait(find.byKey(const Key('home-tab-receipts')));
        await tap('home-tab-receipts');
        await tap('open-history');
        for (final base in [ocr, manual]) {
          await wait(
            find.byKey(ValueKey('history-${base.document.snapshot.id.value}')),
          );
          await tap('history-${base.document.snapshot.id.value}');
          await tap('edit-product-links');
          await pick();
          await tap('pick-product-${productId.value}');
          expect(
            t
                .widget<ReceiptProductSelector>(
                  find.byKey(const Key('saved-product-0')),
                )
                .link!
                .id,
            productId,
          );
          if (Platform.isWindows) {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File(
                'build/saved-links-windows-${base.document.review.source}.png',
              ).writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
            } finally {
              image.dispose();
            }
          }
          await tap('save-product-links');
          await wait(find.byType(HistoryPage));
          final saved = (await store.workspace.repository.read(
            base.document.snapshot.id,
          ))!;
          validateProductLinkRevision(saved.document, base.document);
          expect(saved.document.review.source, base.document.review.source);
          expect(
            saved.document.snapshot.totalCents,
            base.document.snapshot.totalCents,
          );
        }
        final query = SpendingDashboardQuery(
          unit: SpendingPeriodUnit.month,
          anchor: StoredReceiptDate.parse('18.11.2026'),
          today: StoredReceiptDate.parse('18.11.2026'),
        );
        var dashboard = await store.spendingDashboard(query);
        expect(dashboard.categories.totalCents, BigInt.from(375));
        expect(dashboard.categories.categorizedProductRows, 2);
        expect(dashboard.categories.groups.single.totalCents, BigInt.from(375));
        await tap('history-${manual.document.snapshot.id.value}');
        await tap('edit-product-links');
        await pick();
        await tap('unlink-product');
        await tap('save-product-links');
        await wait(find.byType(HistoryPage));
        dashboard = await store.spendingDashboard(query);
        expect(dashboard.categories.totalCents, BigInt.from(375));
        expect(dashboard.categories.categorizedProductRows, 1);
        expect(
          dashboard.categories.groups
              .singleWhere((g) => g.category.name == 'Ruoka ja juoma')
              .totalCents,
          BigInt.from(200),
        );
        final expected = await store.workspace.repository.exportBackup();
        final preview = await store.prepareProtected(
          await store.exportProtected('synthetic saved links password'),
          'synthetic saved links password',
        );
        await store.activateBackup(preview);
        expect(await store.workspace.repository.exportBackup(), expected);
        await t.pumpWidget(const SizedBox());
        await store.close();
        active = null;
        final reopened = active = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        expect(await reopened.workspace.repository.exportBackup(), expected);
        await reopened.workspace.repository.verifyIntegrity();
        final finalManual = (await reopened.workspace.repository.read(
          manual.document.snapshot.id,
        ))!;
        expect(finalManual.document.snapshot.items.first.product, isNull);
        expect(
          finalManual.document.snapshot.items.last.cents,
          BigInt.from(-25),
        );
        expect(
          (await reopened.workspace.repository.read(ocr.document.snapshot.id))!
              .document
              .review
              .source,
          'ocr',
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await active?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('saved-links-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
