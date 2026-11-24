import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/purchase_history_page.dart';
import 'package:receipt_storage/receipt_storage.dart';

import '../tools/demo_receipts/demo_data.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'compact dashboard charts on synthetic receipts preserve storage',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('compact-dashboard-smoke-');
      WorkspaceStore? store;
      try {
        final workspace = await ReceiptWorkspace.open(directory);
        store = WorkspaceStore(workspace);
        await loadDemoReceipts(
          workspace.repository,
          StoredReceiptDate.parse('24.11.2026'),
        );
        final before = await workspace.repository.exportBackup();
        final capture = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: ReceiptReaderApp(
              storageOpener: () async => store!,
              dashboardClock: () => DateTime.utc(2026, 11, 24, 12),
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
              await t.scrollUntilVisible(finder, 300, scrollable: scroll);
            }
          }
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          await t.tap(finder);
          await t.pumpAndSettle();
        }

        Future<void> shot(String name) async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final target = Platform.isWindows
                ? File('build/compact-dashboard-windows-$name.png')
                : File('${support.path}/compact-dashboard-android-$name.png');
            await target.writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        }

        await wait(find.byKey(const Key('dashboard-total')));
        expect(
          t.getTopLeft(find.byKey(const Key('dashboard-week'))).dy,
          t.getTopLeft(find.byKey(const Key('dashboard-custom'))).dy,
        );
        expect(
          t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
          '126,88 €',
        );
        expect(find.byKey(const Key('product-share-ring')), findsOneWidget);
        await shot('overview');
        await tap('breakdown-branch');
        expect(find.byKey(const Key('store-share-ring')), findsOneWidget);
        await shot('branches');
        await tap('dashboard-week');
        await wait(find.byKey(const Key('dashboard-total')));
        expect(
          t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
          '41,59 €',
        );
        expect(find.byKey(const Key('store-share-ring')), findsOneWidget);
        await tap('breakdown-product');
        final product = await store.spendingDashboard(
          SpendingDashboardQuery(
            unit: SpendingPeriodUnit.week,
            anchor: StoredReceiptDate.parse('24.11.2026'),
            today: StoredReceiptDate.parse('24.11.2026'),
          ),
        );
        await tap(
          'breakdown-product-${product.products.groups.first.productId.value}',
        );
        await wait(find.byType(PurchaseHistoryPage));
        final range = t
            .widget<PurchaseHistoryPage>(find.byType(PurchaseHistoryPage))
            .initialRange!;
        expect(range.fromDate!.day, 23);
        expect(range.throughDate!.day, 24);
        Navigator.pop(t.element(find.byType(PurchaseHistoryPage)));
        await t.pumpAndSettle();
        await wait(find.byKey(const Key('dashboard-total')));
        await tap('dashboard-summary-info');
        expect(find.textContaining('17.11.2026'), findsWidgets);
        expect(await workspace.repository.exportBackup(), before);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('compact-dashboard-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
