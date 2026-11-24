import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/product_rankings_page.dart';
import 'package:receipt_reader/spending_breakdown_view.dart';
import 'package:receipt_reader/purchase_history_page.dart';
import 'package:receipt_reader/purchase_summary_view.dart';
import 'package:receipt_reader/software_info_page.dart';

import 'support/ranking_store.dart';

Future<void> open(WidgetTester t, RankingStore store) async {
  await t.pumpWidget(
    ReceiptReaderApp(
      storageOpener: () async => store,
      dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey(key));
  final scroll = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (finder.evaluate().isEmpty && scroll.evaluate().isNotEmpty) {
    t.state<ScrollableState>(scroll.last).position.jumpTo(0);
    await t.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(finder, 350, scrollable: scroll.last);
    }
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> back(WidgetTester t, Type page) async {
  Navigator.pop(t.element(find.byType(page)));
  await t.pumpAndSettle();
}

void main() {
  for (final unit in SpendingPeriodUnit.values) {
    testWidgets(
      '${unit.name} dashboard product shortcut inherits exact inclusive dates and identity',
      (t) async {
        final store = RankingStore();
        final p = store.product(name: 'SAME NAME'),
            other = store.product(name: 'SAME NAME');
        await store.seed([(p, 200), (other, 700)], date: '17.11.2026 23:59:59');
        await store.seed([(p, 300)], date: '18.11.2026');
        await store.seed([(p, 9000)], date: '18.10.2026');
        await open(t, store);
        if (unit == SpendingPeriodUnit.custom) {
          await tap(t, 'dashboard-custom');
          await t.enterText(
            find.byKey(const Key('dashboard-custom-from')),
            '17.11.2026',
          );
          await t.enterText(
            find.byKey(const Key('dashboard-custom-through')),
            '17.11.2026',
          );
          await tap(t, 'dashboard-custom-apply');
        } else {
          await tap(t, 'dashboard-${unit.name}');
        }
        final query = store.queries.last;
        final ranking = t
            .widget<SpendingBreakdownView>(find.byType(SpendingBreakdownView))
            .data
            .products;
        final amount = ranking.groups
            .singleWhere((g) => g.productId == p.link.id)
            .totalCents;
        await tap(t, 'breakdown-product-${p.link.id.value}');
        expect(find.byType(PurchaseHistoryPage), findsOneWidget);
        final scope = store.scopes.last;
        expect(scope.branch, store.branch.id);
        expect(scope.product, p.link.id);
        expect(scope.offset, 0);
        expect(
          purchaseCalendarDay(scope.range!.fromDate!),
          query.selected.firstDay,
        );
        expect(
          purchaseCalendarDay(scope.range!.throughDate!),
          query.selected.lastDay,
        );
        expect(
          t
              .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
              .summary
              .effectiveCents,
          amount,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'top ten retains exact remainder and full list pages open any product',
    (t) async {
      final store = RankingStore();
      final products = [
        for (var i = 0; i < 35; i++) store.product(name: 'PRODUCT $i'),
      ];
      await store.seed([
        for (var i = 0; i < 35; i++) (products[i], (i + 1) * 100),
      ]);
      await open(t, store);
      await tap(t, 'dashboard-product-details');
      expect(
        find.text('Muut liitetyt tuotteet (25): 325,00 €'),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey('breakdown-product-${products.first.link.id.value}'),
        ),
        findsNothing,
      );
      await tap(t, 'product-ranking-all');
      expect(find.byType(ProductRankingsPage), findsOneWidget);
      expect(find.text('Tuotteet: 1–30 / 35'), findsOneWidget);
      await tap(t, 'product-rankings-next');
      expect(find.text('Tuotteet: 31–35 / 35'), findsOneWidget);
      await tap(t, 'ranked-product-${products.first.link.id.value}');
      expect(store.scopes.last.product, products.first.link.id);
      expect(store.scopes.last.range!.fromDate!.day, 1);
      expect(store.scopes.last.range!.throughDate!.day, 18);
      await back(t, PurchaseHistoryPage);
      expect(find.text('Tuotteet: 1–30 / 35'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'metadata failure stays on dashboard and a retry opens the product',
    (t) async {
      final store = RankingStore();
      final p = store.product();
      await store.seed([(p, 200)]);
      await open(t, store);
      store.failProduct = true;
      await tap(t, 'breakdown-product-${p.link.id.value}');
      expect(find.byType(PurchaseHistoryPage), findsNothing);
      expect(
        find.text(
          'Tuotteen ostohistorian avaaminen epäonnistui. Päivitä ja yritä uudelleen.',
        ),
        findsOneWidget,
      );
      store.failProduct = false;
      await tap(t, 'breakdown-product-${p.link.id.value}');
      expect(find.byType(PurchaseHistoryPage), findsOneWidget);
    },
  );
  testWidgets(
    'a mismatched metadata identity cannot open a different product',
    (t) async {
      final store = RankingStore();
      final p = store.product(), other = store.product();
      await store.seed([(p, 200)]);
      await open(t, store);
      store.productOverride = other;
      await tap(t, 'breakdown-product-${p.link.id.value}');
      expect(find.byType(PurchaseHistoryPage), findsNothing);
      expect(store.scopes, isEmpty);
      expect(
        store.documents.single.document.snapshot.items.single.product!.id,
        p.link.id,
      );
    },
  );
  testWidgets(
    'changing filters during a delayed product read discards obsolete navigation',
    (t) async {
      final store = RankingStore();
      final p = store.product();
      await store.seed([(p, 200)]);
      await open(t, store);
      store.productGate = Completer<void>();
      await tap(t, 'breakdown-product-${p.link.id.value}');
      await tap(t, 'dashboard-week');
      store.productGate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(PurchaseHistoryPage), findsNothing);
      expect(store.queries.last.unit, SpendingPeriodUnit.week);
      await tap(t, 'breakdown-product-${p.link.id.value}');
      expect(store.scopes.last.range!.fromDate!.day, 16);
    },
  );
  testWidgets('switching tabs discards a delayed dashboard product read', (
    t,
  ) async {
    final store = RankingStore();
    final p = store.product();
    await store.seed([(p, 200)]);
    await open(t, store);
    store.productGate = Completer<void>();
    await tap(t, 'breakdown-product-${p.link.id.value}');
    await tap(t, 'home-tab-receipts');
    store.productGate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(PurchaseHistoryPage), findsNothing);
    expect(store.scopes, isEmpty);
    await tap(t, 'home-tab-dashboard');
    await tap(t, 'breakdown-product-${p.link.id.value}');
    expect(find.byType(PurchaseHistoryPage), findsOneWidget);
  });
  testWidgets(
    'opening another route discards a delayed dashboard product read',
    (t) async {
      final store = RankingStore();
      final p = store.product();
      await store.seed([(p, 200)]);
      await open(t, store);
      store.productGate = Completer<void>();
      await tap(t, 'breakdown-product-${p.link.id.value}');
      await tap(t, 'open-software-info');
      store.productGate!.complete();
      await t.pumpAndSettle();
      expect(find.byType(SoftwareInfoPage), findsOneWidget);
      expect(find.byType(PurchaseHistoryPage), findsNothing);
      expect(store.scopes, isEmpty);
    },
  );
  testWidgets('returning after unlink reloads ranking, coverage and totals', (
    t,
  ) async {
    final store = RankingStore();
    final p = store.product();
    final saved = await store.seed([(p, 200)]);
    await open(t, store);
    await tap(t, 'breakdown-product-${p.link.id.value}');
    await store.saveManual(
      ReviewedReceipt.productLinks(
        confirmation:
            ProductLinkReviewChecks(
              base: saved.document,
              expectedHead: saved.revision,
              selections: {saved.document.snapshot.items.single.id: null},
              mutationId: DurableId.generate(),
            ).confirm(
              reviewedAtMs: BigInt.from(3000),
              appVersion: 'ranking-widget',
            ),
      ),
    );
    await back(t, PurchaseHistoryPage);
    final summary = t
        .widget<SpendingBreakdownView>(find.byType(SpendingBreakdownView))
        .data
        .products;
    expect(summary.groups, isEmpty);
    expect(summary.unlinkedCents, BigInt.from(200));
    expect(summary.receiptTotalCents, BigInt.from(200));
    expect(summary.linkedRows, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'full list refresh failure clears stale entries and retries the same range',
    (t) async {
      final store = RankingStore();
      final p = store.product();
      await store.seed([(p, 200)]);
      await open(t, store);
      await tap(t, 'product-ranking-all');
      store.failDashboard = true;
      await tap(t, 'product-rankings-refresh');
      expect(
        find.byKey(ValueKey('ranked-product-${p.link.id.value}')),
        findsNothing,
      );
      expect(find.byKey(const Key('product-rankings-retry')), findsOneWidget);
      store.failDashboard = false;
      await tap(t, 'product-rankings-retry');
      expect(
        find.byKey(ValueKey('ranked-product-${p.link.id.value}')),
        findsOneWidget,
      );
      expect(
        store.queries.last.selected.firstDay,
        store.queries.first.selected.firstDay,
      );
    },
  );
  testWidgets(
    'branch filter keeps equal names independent and scopes shortcut to chosen branch',
    (t) async {
      final store = RankingStore();
      final other = ReceiptBranch(
        id: DurableId.generate(),
        name: store.branch.name,
        revision: RevisionId(store.branch.revision!.origin, BigInt.from(900)),
      );
      store.otherBranches.add(other);
      final a = store.product(name: 'SAME'),
          b = store.product(name: 'SAME', at: other);
      await store.seed([(a, 200)]);
      await store.seed([(b, 300)], at: other);
      await open(t, store);
      expect(
        t
            .widget<SpendingBreakdownView>(find.byType(SpendingBreakdownView))
            .data
            .products
            .groups
            .length,
        2,
      );
      await tap(t, 'dashboard-branch');
      await tap(t, 'dashboard-branch-${other.id.value}');
      final summary = t
          .widget<SpendingBreakdownView>(find.byType(SpendingBreakdownView))
          .data
          .products;
      expect(summary.groups.single.productId, b.link.id);
      await tap(t, 'breakdown-product-${b.link.id.value}');
      expect(store.scopes.last.branch, other.id);
      expect(store.scopes.last.product, b.link.id);
    },
  );
  testWidgets(
    'ranking limit keeps complete dashboard totals and withholds partial product list',
    (t) async {
      final store = RankingStore();
      final products = [
        for (var i = 0; i <= ProductSpendingBuilder.maxGroups; i++)
          store.product(),
      ];
      await store.seed([for (final p in products) (p, 1)]);
      await open(t, store);
      final summary = t
          .widget<SpendingBreakdownView>(find.byType(SpendingBreakdownView))
          .data
          .products;
      expect(summary.limitExceeded, isTrue);
      expect(summary.groups, isEmpty);
      expect(summary.linkedRows, 2049);
      expect(summary.linkedCents, BigInt.from(2049));
      expect(find.byKey(const Key('product-ranking-limit')), findsOneWidget);
      expect(find.byKey(const Key('product-ranking-all')), findsNothing);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '20,49 €',
      );
      expect(find.byKey(const Key('dashboard-retry')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('ranking and full list wrap at 320px with doubled text', (
    t,
  ) async {
    final store = RankingStore();
    final p = store.product(name: 'LONG SYNTHETIC PRODUCT LABEL');
    await store.seed([(p, -200)]);
    await open(t, store);
    t.view.physicalSize = const Size(320, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpAndSettle();
    await tap(t, 'product-ranking-all');
    await tap(t, 'ranked-product-${p.link.id.value}');
    if (find.byType(PurchaseSummaryView).evaluate().isEmpty) {
      await t.scrollUntilVisible(
        find.byType(PurchaseSummaryView),
        350,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await t.pumpAndSettle();
    }
    expect(
      t
          .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
          .summary
          .returnRows,
      1,
    );
    expect(t.takeException(), isNull);
  });
}
