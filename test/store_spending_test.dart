import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'spending_dashboard_test.dart'
    show DashboardStore, openDashboard, tapKey, revealDashboard;

class _LimitedStore extends DashboardStore {
  @override
  Future<SpendingDashboard> spendingDashboard(
    SpendingDashboardQuery query,
  ) async {
    if (query.branchId == null) {
      throw const StorageFailure('spendingGroupLimit');
    }
    return super.spendingDashboard(query);
  }
}

void main() {
  testWidgets(
    'signed store nets, averages and shares use the selected range only',
    (t) async {
      final store = DashboardStore();
      final b = ReceiptBranch(
        id: DurableId.generate(),
        name: store.branch.name,
      );
      final c = ReceiptBranch(id: DurableId.generate(), name: 'NEGATIVE');
      final zero = ReceiptBranch(id: DurableId.generate(), name: 'ZERO');
      await store.seed('18.11.2026', 1000);
      await store.seed('18.11.2026', -200);
      await store.seed('18.11.2026', 200, selected: b);
      await store.seed('18.11.2026', -100, selected: c);
      await store.seed('18.11.2026', 50, selected: zero);
      await store.seed('18.11.2026', -50, selected: zero);
      await store.seed(
        '18.10.2026',
        99999,
        selected: ReceiptBranch(
          id: DurableId.generate(),
          name: 'COMPARISON ONLY',
        ),
      );
      await openDashboard(t, store);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '9,00 €',
      );
      expect(
        find.text('${store.branch.name}: 8,00 € · 80,0 %'),
        findsOneWidget,
      );
      expect(find.text('${b.name}: 2,00 € · 20,0 %'), findsOneWidget);
      expect(find.byKey(ValueKey('store-share-${c.id.value}')), findsNothing);
      expect(
        find.byKey(ValueKey('store-share-${zero.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('store-bar-${zero.id.value}')),
        findsOneWidget,
      );
      expect(find.text('COMPARISON ONLY'), findsNothing);
      expect(
        find.text('Negatiiviset toimipistenetot yhteensä: -1,00 €'),
        findsOneWidget,
      );
      await tapKey(t, 'store-bar-${b.id.value}');
      expect(store.historyFilters.last!.branchId, b.id);
      expect(store.historyFilters.last!.fromDate!.day, 1);
      expect(store.historyFilters.last!.throughDate!.day, 18);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'touching a ring slice opens that branch rather than a combined dataset',
    (t) async {
      final store = DashboardStore();
      final b = ReceiptBranch(id: DurableId.generate(), name: 'SECOND');
      await store.seed('18.11.2026', 800);
      await store.seed('18.11.2026', 200, selected: b);
      await openDashboard(t, store);
      await revealDashboard(t, 'store-share-ring');
      final center = t.getCenter(find.byKey(const Key('store-share-ring')));
      // The final 20% slice occupies the upper-left arc of this known fixture.
      await t.tapAt(center + const Offset(-64, -64));
      await t.pumpAndSettle();
      expect(store.historyFilters.last!.branchId, b.id);
      expect(store.historyFilters.last!.fromDate!.month, 11);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Muut preserves smaller stores and drills down through an explicit choice',
    (t) async {
      final store = DashboardStore();
      final branches = [
        for (var i = 0; i < 10; i++)
          ReceiptBranch(id: DurableId.generate(), name: 'STORE $i'),
      ];
      for (var i = 0; i < branches.length; i++) {
        await store.seed('18.11.2026', (10 - i) * 100, selected: branches[i]);
      }
      await openDashboard(t, store);
      expect(find.text('Muut: 3,00 € · 5,5 %'), findsOneWidget);
      await tapKey(t, 'store-share-others');
      expect(
        find.byKey(ValueKey('store-other-${branches[8].id.value}')),
        findsOneWidget,
      );
      await tapKey(t, 'store-other-${branches[9].id.value}');
      expect(store.historyFilters.last!.branchId, branches[9].id);
      expect(store.historyFilters.last!.throughDate!.day, 18);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('nonpositive and empty selections do not manufacture a ring', (
    t,
  ) async {
    final store = DashboardStore();
    await store.seed('18.11.2026', -100);
    await store.seed(
      '18.11.2026',
      0,
      selected: ReceiptBranch(id: DurableId.generate(), name: 'ZERO'),
    );
    await openDashboard(t, store);
    expect(find.byKey(const Key('store-share-ring')), findsNothing);
    expect(find.byKey(const Key('store-no-positive')), findsOneWidget);
    expect(
      find.byKey(ValueKey('store-bar-${store.branch.id.value}')),
      findsOneWidget,
    );
    await tapKey(t, 'dashboard-previous');
    expect(find.byKey(const Key('store-share-ring')), findsNothing);
    expect(
      find.text('Toimipistevertailuun ei löytynyt kuitteja.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Muut still asks for a store when exactly one store was grouped',
    (t) async {
      final store = DashboardStore();
      final branches = [
        for (var i = 0; i < 9; i++)
          ReceiptBranch(id: DurableId.generate(), name: 'STORE $i'),
      ];
      for (final branch in branches) {
        await store.seed('18.11.2026', 100, selected: branch);
      }
      await openDashboard(t, store);
      await tapKey(t, 'store-share-others');
      expect(store.historyFilters, isEmpty);
      await tapKey(t, 'store-other-${branches.last.id.value}');
      expect(store.historyFilters.last!.branchId, branches.last.id);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'too many stores hides all results and a branch filter recovers',
    (t) async {
      final store = _LimitedStore();
      await store.seed('18.11.2026', 100);
      await openDashboard(t, store);
      expect(find.textContaining('yli 128 toimipistettä'), findsOneWidget);
      expect(find.byKey(const Key('dashboard-total')), findsNothing);
      expect(find.byKey(const Key('store-share-ring')), findsNothing);
      await tapKey(t, 'dashboard-branch');
      await tapKey(t, 'dashboard-branch-${store.branch.id.value}');
      expect(find.byKey(const Key('store-share-ring')), findsOneWidget);
      expect(
        find.text('${store.branch.name}: 1,00 € · 100,0 %'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('store charts and long amounts fit 320px with doubled text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = DashboardStore();
    await store.seed('18.11.2026', 9007199254740993);
    await store.seed(
      '18.11.2026',
      -100,
      selected: ReceiptBranch(
        id: DurableId.generate(),
        name: 'LONG SYNTHETIC BRANCH NAME',
      ),
    );
    await openDashboard(t, store);
    await revealDashboard(t, 'store-share-ring');
    expect(t.takeException(), isNull);
    await tapKey(t, 'store-bar-${store.branch.id.value}');
    expect(store.historyFilters.last!.branchId, store.branch.id);
    expect(t.takeException(), isNull);
  });
}
