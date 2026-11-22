import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/spending_dashboard_page.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'purchase_history_test.dart' show approve;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native calendar dashboard, drill-down, correction and protected recovery',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('dashboard-smoke-');
      WorkspaceStore? store;
      try {
        final workspace = await ReceiptWorkspace.open(directory);
        final active = store = WorkspaceStore(workspace);
        var branch = ReceiptBranch(
          id: DurableId.generate(),
          name: 'SYNTHETIC MARKET',
        );
        ReceiptSnapshot receipt(
          int cents,
          String date, {
          ReceiptBranch? selected,
        }) => ReceiptSnapshot(
          id: DurableId.generate(),
          branch: selected ?? branch,
          date: StoredReceiptDate.parse(date),
          totalCents: BigInt.from(cents),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC PRODUCT',
              kind: LineKind.product,
              cents: BigInt.from(cents),
            ),
          ],
        );
        late ReceiptSnapshot first;
        for (var i = 0; i < 35; i++) {
          final value = receipt(300, '18.11.2026 23:59:59');
          await active.saveManual(approve(value));
          if (i == 0) {
            first = value;
            branch = (await active.branches()).single;
          }
        }
        await active.saveManual(approve(receipt(1000, '18.10.2026')));
        await active.saveManual(approve(receipt(900, '19.10.2026')));
        await active.saveManual(approve(receipt(-500, '18.9.2026')));
        await active.saveManual(approve(receipt(999, '19.11.2026')));
        await active.saveManual(
          approve(
            receipt(
              -100,
              '17.11.2026',
              selected: ReceiptBranch(
                id: DurableId.generate(),
                name: 'SYNTHETIC SECOND MARKET',
              ),
            ),
          ),
        );
        final before = await workspace.repository.exportBackup();
        final captureKey = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: ReceiptReaderApp(storageOpener: () async => active),
          ),
        );
        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(finder, findsOneWidget);
          await t.pumpAndSettle();
        }

        Finder total(String value) => find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.key == const Key('dashboard-total') &&
              w.data == value,
        );

        Future<void> tap(String key) async {
          final finder = find.byKey(ValueKey(key));
          await t.ensureVisible(finder);
          await t.pumpAndSettle();
          await t.tap(finder);
          await t.pumpAndSettle();
        }

        Future<void> shot(String name) async {
          if (!Platform.isWindows) return;
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('build/dashboard-windows-$name.png').writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
          }
        }

        await waitFor(find.byKey(const Key('open-dashboard')));
        await tap(
          'open-dashboard',
        ); // Actual home navigation, with the real clock.
        await waitFor(find.byKey(const Key('dashboard-total')));
        Navigator.of(t.element(find.byKey(const Key('dashboard-total')))).pop();
        await t.pumpAndSettle();
        Navigator.of(t.element(find.byKey(const Key('open-dashboard')))).push(
          MaterialPageRoute<void>(
            builder: (_) => SpendingDashboardPage(
              store: active,
              service: active,
              clock: () => DateTime.utc(2026, 11, 18, 12),
            ),
          ),
        );
        await waitFor(find.byKey(const Key('dashboard-total')));
        expect(total('104,00 €'), findsOneWidget);
        expect(find.text('2,89 €'), findsOneWidget);
        expect(await workspace.repository.exportBackup(), before);
        await shot('overview');
        await tap('dashboard-branch');
        await tap('dashboard-branch-${branch.id.value}');
        await waitFor(total('105,00 €'));
        final q = SpendingDashboardQuery(
          unit: SpendingPeriodUnit.month,
          anchor: StoredReceiptDate.parse('18.11.2026'),
          today: StoredReceiptDate.parse('18.11.2026'),
        );
        await t.ensureVisible(
          find.byKey(ValueKey('dashboard-bar-${q.selected.firstDay}')),
        );
        await t.pumpAndSettle();
        await shot('trend');
        await tap('dashboard-bar-${q.selected.firstDay}');
        await waitFor(find.byKey(const Key('history-filter-summary')));
        final historyScroll = find
            .descendant(
              of: find.byType(HistoryPage),
              matching: find.byType(Scrollable),
            )
            .first;
        await t.scrollUntilVisible(
          find.byKey(const Key('history-more')),
          400,
          scrollable: historyScroll,
        );
        await tap('history-more');
        final expected = await active.history(
          limit: 100,
          filter: HistoryFilter(
            branchId: branch.id,
            fromDate: purchaseCalendarDate(q.selected.firstDay),
            throughDate: purchaseCalendarDate(q.selected.lastDay),
          ),
        );
        expect(expected, hasLength(35));
        final last = find.byKey(
          ValueKey('history-${expected.last.document.snapshot.id.value}'),
        );
        await t.scrollUntilVisible(last, 400, scrollable: historyScroll);
        expect(last, findsOneWidget);
        Navigator.of(t.element(find.byType(HistoryPage))).pop();
        await t.pumpAndSettle();
        final backup = await active.exportProtected(
          'synthetic-dashboard-test-password',
        );
        final original = (await workspace.repository.read(first.id))!;
        final changed = ReceiptSnapshot(
          id: first.id,
          branch: branch,
          date: first.date,
          totalCents: BigInt.from(900),
          items: [
            ReceiptItemSnapshot(
              id: first.items.single.id,
              name: 'SYNTHETIC PRODUCT',
              kind: LineKind.product,
              cents: BigInt.from(900),
            ),
          ],
        );
        await active.saveManual(approve(changed, heads: [original.revision]));
        await tap('dashboard-refresh');
        await waitFor(total('111,00 €'));
        final candidate = await active.prepareProtected(
          backup,
          'synthetic-dashboard-test-password',
        );
        final activation = active.activateBackup(candidate);
        final queued = active.spendingDashboard(q);
        await activation;
        expect((await queued).selected.totalCents, BigInt.from(10400));
        await tap('dashboard-refresh');
        await waitFor(total('105,00 €'));
        final restored = (await workspace.repository.read(first.id))!;
        await active.deleteReceipt(
          ReceiptDeletionChecks(
            document: restored.document,
            expectedHead: restored.revision,
            mutationId: DurableId.generate(),
            receiptReviewed: true,
          ).confirm(
            deletedAtMs: BigInt.from(3000),
            appVersion: 'dashboard-smoke',
          ),
        );
        await tap('dashboard-refresh');
        await waitFor(total('102,00 €'));
        await tap('dashboard-week');
        await waitFor(find.text('16.11.2026–18.11.2026'));
        await t.pumpWidget(const SizedBox());
        await active.close();
        store = null;
        final reopened = store = WorkspaceStore(
          await ReceiptWorkspace.open(directory),
        );
        expect(
          (await reopened.spendingDashboard(q)).selected.totalCents,
          BigInt.from(10100),
        );
        await reopened.returnToPrevious();
        expect(
          (await reopened.spendingDashboard(q)).selected.totalCents,
          BigInt.from(11000),
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('dashboard-smoke-')) {
          throw StateError('unexpected_test_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
