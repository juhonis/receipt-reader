import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_reader/category_comparison_view.dart';
import 'package:receipt_reader/history_page.dart';

import 'product_rankings_test.dart' show open, tap;
import 'support/ranking_store.dart';

void main() {
  testWidgets(
    'category pie separates signed and unclassified nets and opens scoped receipts',
    (t) async {
      final store = RankingStore();
      final p = store.product(name: 'Food'),
          returned = store.product(name: 'Return');
      store.categoryLabels[p.link.id] = 'Muut';
      store.categoryLabels[returned.link.id] = 'Return';
      await store.seed([(p, 800), (null, 200), (returned, -50)]);
      await open(t, store);
      await tap(t, 'breakdown-category');
      expect(find.byKey(const Key('category-share-ring')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('category-positive-total'))).data,
        contains('10,00 €'),
      );
      expect(
        t.widget<Text>(find.byKey(const Key('category-negative-total'))).data,
        contains('-0,50 €'),
      );
      expect(
        find.byKey(const Key('category-share-product-Return')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('category-share-uncategorized-')),
        findsOneWidget,
      );
      await tap(t, 'category-share-product-Muut');
      expect(find.byType(HistoryPage), findsOneWidget);
      final filter = store.historyFilters.last!;
      expect(filter.category, ReceiptCategory.product('Muut'));
      expect(filter.fromDate!.day, 1);
      expect(filter.throughDate!.day, 18);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'paired chart opens matched comparison receipts and preserves mode on reload',
    (t) async {
      final store = RankingStore();
      final p = store.product();
      store.categoryLabels[p.link.id] = 'Food';
      await store.seed([(p, 300)], date: '18.11.2026');
      await store.seed([(p, 200)], date: '18.10.2026');
      await store.seed([(p, 9000)], date: '19.10.2026');
      await open(t, store);
      await tap(t, 'dashboard-chart-categories');
      expect(
        t
            .widget<Text>(find.byKey(const Key('category-delta-product-Food')))
            .data,
        '+1,00 € · +50,0 %',
      );
      await tap(t, 'category-change-product-Food');
      final day = store.queries.last.comparisonPrevious!.firstDay;
      await tap(t, 'category-comparison-open-$day');
      final filter = store.historyFilters.last!;
      expect(filter.category, ReceiptCategory.product('Food'));
      expect(filter.fromDate!.month, 10);
      expect(filter.fromDate!.day, 1);
      expect(filter.throughDate!.day, 18);
      Navigator.pop(t.element(find.byType(HistoryPage)));
      await t.pumpAndSettle();
      await tap(t, 'dashboard-week');
      await tap(t, 'dashboard-chart-categories');
      expect(find.byType(CategoryComparisonView), findsOneWidget);
      expect(
        find.byKey(const Key('category-comparison-missing')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('paired bars share a scale despite different label widths', (
    t,
  ) async {
    final store = RankingStore();
    final p = store.product();
    store.categoryLabels[p.link.id] = 'Food';
    await store.seed([(p, 3000)]);
    await store.seed([(p, 200)], date: '17.10.2026');
    await open(t, store);
    await tap(t, 'dashboard-chart-categories');
    final bars = find.descendant(
      of: find.byType(CategoryComparisonView),
      matching: find.byType(FractionallySizedBox),
    );
    expect(bars, findsNWidgets(2));
    final first = find.descendant(
      of: bars.at(0),
      matching: find.byType(ColoredBox),
    );
    final second = find.descendant(
      of: bars.at(1),
      matching: find.byType(ColoredBox),
    );
    expect(
      t.getSize(second).width / t.getSize(first).width,
      closeTo(200 / 3000, .000001),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('missing receipts never invent biggest changes', (t) async {
    final store = RankingStore();
    await store.seed([(null, 200)]);
    await open(t, store);
    await tap(t, 'dashboard-chart-categories');
    expect(
      find.byKey(const Key('category-comparison-missing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('category-change-uncategorized-')),
      findsNothing,
    );
    await tap(t, 'category-comparison-info');
    expect(find.textContaining('1.10.2026'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('paired signed bars fit 320px at doubled text', (t) async {
    t.view.physicalSize = const Size(320, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = RankingStore();
    final p = store.product();
    store.categoryLabels[p.link.id] = 'A long category label';
    await store.seed([(p, -300)]);
    await store.seed([(p, 100)], date: '17.10.2026');
    await open(t, store);
    await tap(t, 'breakdown-category');
    await tap(t, 'dashboard-chart-categories');
    expect(find.byType(CategoryComparisonView), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('grouped remainder preserves real Muut category identity', (
    t,
  ) async {
    final store = RankingStore();
    for (var i = 0; i < 10; i++) {
      final p = store.product(name: 'P$i');
      store.categoryLabels[p.link.id] = i == 9 ? 'Muut' : 'Category$i';
      await store.seed([(p, 1000 - i)]);
    }
    await open(t, store);
    await tap(t, 'breakdown-category');
    await tap(t, 'category-share-others');
    await tap(t, 'category-other-product-Muut');
    expect(
      store.historyFilters.last!.category,
      ReceiptCategory.product('Muut'),
    );
    expect(t.takeException(), isNull);
  });
}
