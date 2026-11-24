import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/spending_breakdown_view.dart';

import 'product_rankings_test.dart' show open, tap;
import 'support/ranking_store.dart';

void main() {
  testWidgets('phone controls group refresh with branch navigation', (t) async {
    t.view.physicalSize = const Size(412, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final store = RankingStore();
    await open(t, store);
    expect(
      t.getTopLeft(find.byKey(const Key('dashboard-branch'))).dy,
      t.getTopLeft(find.byKey(const Key('dashboard-refresh'))).dy,
    );
    expect(
      t.getBottomLeft(find.byKey(const Key('dashboard-branch'))).dy,
      lessThanOrEqualTo(
        t.getTopLeft(find.byKey(const Key('dashboard-date'))).dy,
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('summary precedes product pie and mode survives period changes', (
    t,
  ) async {
    final store = RankingStore();
    final a = store.product(name: 'A'), b = store.product(name: 'B');
    await store.seed([(a, 800), (b, 200)]);
    await open(t, store);
    expect(
      t.getTopLeft(find.byKey(const Key('dashboard-summary'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('dashboard-breakdown'))).dy),
    );
    expect(find.byKey(const Key('product-share-ring')), findsOneWidget);
    expect(find.byKey(const Key('store-share-ring')), findsNothing);
    expect(find.text('A: 8,00 € · 80,0 %'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-products')), findsNothing);
    await tap(t, 'breakdown-branch');
    await tap(t, 'dashboard-week');
    expect(
      t.widget<SpendingBreakdownView>(find.byType(SpendingBreakdownView)).mode,
      SpendingBreakdownMode.branch,
    );
    expect(find.byKey(const Key('store-share-ring')), findsOneWidget);
    await tap(t, 'dashboard-summary-info');
    expect(find.textContaining('16.11.2026'), findsWidgets);
    await tap(t, 'dashboard-previous-comparison-receipts');
    expect(store.historyFilters.last!.fromDate!.day, 9);
    expect(store.historyFilters.last!.throughDate!.day, 11);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'product shares exclude negative and unlinked nets and help explains scope',
    (t) async {
      final store = RankingStore();
      final a = store.product(name: 'A'), b = store.product(name: 'RETURN');
      await store.seed([(a, 1000), (a, -200), (b, -100), (null, 300)]);
      await open(t, store);
      expect(find.text('A: 8,00 € · 100,0 %'), findsOneWidget);
      expect(find.text('Positiiviset tuotenetot: 8,00 €'), findsOneWidget);
      expect(find.text('Negatiiviset netot: -1,00 €'), findsOneWidget);
      expect(find.text('Ei tuotelinkkiä: 3,00 €'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '10,00 €',
      );
      await tap(t, 'dashboard-breakdown-info');
      expect(
        find.textContaining('pantit, kuittialennukset ja oikaisut'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'grouped products retain exact shares and explicit scoped choices',
    (t) async {
      final store = RankingStore();
      final products = [for (var i = 0; i < 7; i++) store.product(name: 'P$i')];
      await store.seed([
        for (var i = 0; i < 7; i++) (products[i], (7 - i) * 100),
      ]);
      await open(t, store);
      expect(find.text('Muut: 3,00 € · 10,7 %'), findsOneWidget);
      await tap(t, 'breakdown-product-others');
      expect(store.scopes, isEmpty);
      await tap(t, 'breakdown-other-product-${products.last.link.id.value}');
      expect(store.scopes.last.product, products.last.link.id);
      expect(store.scopes.last.range!.fromDate!.day, 1);
      expect(store.scopes.last.range!.throughDate!.day, 18);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('product ring taps use product identity and selected dates', (
    t,
  ) async {
    final store = RankingStore();
    final a = store.product(name: 'SAME'), b = store.product(name: 'SAME');
    await store.seed([(a, 800), (b, 200)]);
    await open(t, store);
    await t.ensureVisible(find.byKey(const Key('product-share-ring')));
    await t.pumpAndSettle();
    final center = t.getCenter(find.byKey(const Key('product-share-ring')));
    await t.tapAt(center + const Offset(-64, -64));
    await t.pumpAndSettle();
    expect(store.scopes.last.product, b.link.id);
    expect(store.scopes.last.range!.throughDate!.day, 18);
    expect(t.takeException(), isNull);
  });
}
