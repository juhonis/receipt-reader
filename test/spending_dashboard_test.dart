import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/spending_service.dart';
import 'package:receipt_reader/spending_dashboard_page.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'support/fake_store.dart';

class DashboardStore extends FakeStore implements SpendingDashboardService {
  final queries = <SpendingDashboardQuery>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<SpendingDashboard> spendingDashboard(
    SpendingDashboardQuery query,
  ) async {
    queries.add(query);
    await gate?.future;
    if (fail) throw const StorageFailure('database');
    final builder = SpendingDashboardBuilder(query);
    for (final stored in documents) {
      builder.add(stored.document.snapshot);
    }
    return builder.build();
  }

  Future<void> seed(String date, int cents, {ReceiptBranch? selected}) async {
    final row = ReceiptItemSnapshot(
      id: DurableId.generate(),
      name: 'TEST',
      kind: LineKind.product,
      cents: BigInt.from(cents),
    );
    final snapshot = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: selected ?? branch,
      date: StoredReceiptDate.parse(date),
      totalCents: BigInt.from(cents),
      items: [row],
    );
    await saveManual(
      ReviewedReceipt.manual(
        current: snapshot,
        expectedHeads: [],
        confirmation: ManualReviewChecks(
          snapshot: snapshot,
          expectedHeads: [],
          mutationId: DurableId.generate(),
          branchReviewed: true,
          dateReviewed: true,
          totalReviewed: true,
          reviewedRowIds: [row.id],
        ).confirm(reviewedAtMs: BigInt.one, appVersion: 'dashboard-test'),
      ),
    );
  }
}

Future<void> openDashboard(
  WidgetTester t,
  DashboardStore store, {
  DateTime Function()? clock,
}) async {
  await t.pumpWidget(
    ReceiptReaderApp(
      storageOpener: () async => store,
      dashboardClock: clock ?? () => DateTime.utc(2026, 11, 18, 12),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> revealDashboard(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    final scroll = find
        .descendant(
          of: find.byType(SpendingDashboardPage),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await t.scrollUntilVisible(finder, -300, scrollable: scroll);
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await revealDashboard(t, key);
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'monthly totals, exact average, fair comparison and receipt drill-down',
    (t) async {
      final store = DashboardStore();
      await store.seed('17.11.2026', 500);
      await store.seed('18.11.2026 23:59:59', 100);
      await store.seed('19.11.2026', 999);
      await store.seed('17.10.2026', 1200);
      await store.seed('19.10.2026', 900);
      await openDashboard(t, store);
      expect(find.text('600,00 €'), findsNothing);
      expect(find.byKey(const Key('dashboard-total')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '6,00 €',
      );
      expect(find.text('3,00 €'), findsOneWidget);
      expect(find.text('1.11.2026–18.11.2026'), findsOneWidget);
      expect(find.text('Muutos euroina: -6,00 €'), findsOneWidget);
      expect(find.text('Muutos prosentteina: -50,0 %'), findsOneWidget);
      await tapKey(t, 'dashboard-receipts');
      expect(store.historyFilters.last!.fromDate!.day, 1);
      expect(store.historyFilters.last!.throughDate!.day, 18);
      expect(store.historyFilters.last!.throughDate!.month, 11);
      expect(
        find.byKey(
          ValueKey('history-${store.documents[2].document.snapshot.id.value}'),
        ),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'weekly mode, previous/current navigation, branch and chart drill-down',
    (t) async {
      final store = DashboardStore();
      await store.seed('17.11.2026', 300);
      await store.seed('10.11.2026', 200);
      await openDashboard(t, store);
      await tapKey(t, 'dashboard-week');
      expect(find.text('16.11.2026–18.11.2026'), findsOneWidget);
      await tapKey(t, 'dashboard-previous');
      expect(find.text('9.11.2026–15.11.2026'), findsOneWidget);
      await tapKey(t, 'dashboard-today');
      await tapKey(t, 'dashboard-branch');
      await tapKey(t, 'dashboard-branch-${store.branch.id.value}');
      expect(store.queries.last.branchId, store.branch.id);
      final day = store.queries.last.periods[1];
      await tapKey(t, 'dashboard-bar-${day.firstDay}');
      expect(store.historyFilters.last!.branchId, store.branch.id);
      expect(store.historyFilters.last!.fromDate!.day, 17);
      expect(store.historyFilters.last!.throughDate!.day, 17);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'empty periods and zero/negative baselines do not invent percentages',
    (t) async {
      final store = DashboardStore();
      await store.seed('18.11.2026', -100);
      await store.seed('18.10.2026', 0);
      await openDashboard(t, store);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '-1,00 €',
      );
      expect(
        find.textContaining('Prosenttimuutosta ei lasketa'),
        findsOneWidget,
      );
      expect(find.text('Muutos prosentteina: -100,0 %'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'refresh/failure clear stale totals, retry and older requests cannot replace newer selection',
    (t) async {
      final store = DashboardStore();
      await store.seed('18.11.2026', 300);
      await openDashboard(t, store);
      final gate = store.gate = Completer<void>();
      await t.tap(find.byKey(const Key('dashboard-refresh')));
      await t.pump();
      expect(find.byKey(const Key('dashboard-total')), findsNothing);
      store.gate = null;
      await t.tap(find.byKey(const Key('dashboard-week')));
      await t.pumpAndSettle();
      expect(store.queries.last.unit, SpendingPeriodUnit.week);
      gate.complete();
      await t.pumpAndSettle();
      expect(find.text('16.11.2026–18.11.2026'), findsOneWidget);
      store.fail = true;
      await tapKey(t, 'dashboard-refresh');
      expect(find.byKey(const Key('dashboard-total')), findsNothing);
      store.fail = false;
      await tapKey(t, 'dashboard-retry');
      expect(find.byKey(const Key('dashboard-total')), findsOneWidget);
    },
  );
  testWidgets('Helsinki day rollover refreshes current periods', (t) async {
    final store = DashboardStore();
    var now = DateTime.utc(2026, 11, 30, 21, 59);
    await openDashboard(t, store, clock: () => now);
    expect(store.queries.last.today.month, 11);
    now = DateTime.utc(2026, 11, 30, 22, 1);
    await tapKey(t, 'dashboard-refresh');
    expect(store.queries.last.today.month, 12);
    expect(store.queries.last.anchor.month, 12);
  });
  testWidgets('320px doubled text permits filters, details and history', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = DashboardStore();
    await store.seed('18.11.2026', 100);
    await openDashboard(t, store);
    expect(t.takeException(), isNull);
    await tapKey(t, 'dashboard-branch');
    await tapKey(t, 'dashboard-all-branches');
    await revealDashboard(t, 'dashboard-period-details');
    await tapKey(t, 'dashboard-period-details');
    expect(t.takeException(), isNull);
    await tapKey(t, 'dashboard-receipts');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'two home tabs separate analytics and receipts and refresh on return',
    (t) async {
      final store = DashboardStore();
      await store.seed('18.11.2026', 100);
      await openDashboard(t, store);
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('Lisää kuitti käsin'), findsNothing);
      await tapKey(t, 'dashboard-year');
      await tapKey(t, 'home-tab-receipts');
      expect(find.text('Lisää kuitti käsin'), findsOneWidget);
      expect(find.byKey(const Key('open-history')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-total')), findsNothing);
      await store.seed('1.1.2026', 200);
      await tapKey(t, 'home-tab-dashboard');
      expect(store.queries.last.unit, SpendingPeriodUnit.year);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '3,00 €',
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'year navigation and custom range validation, cancel and inclusive drill-down',
    (t) async {
      final store = DashboardStore();
      await store.seed('16.11.2026', 300);
      await store.seed('17.11.2026', 500);
      await store.seed('18.11.2026', 100);
      await store.seed('1.1.2025', 200);
      await openDashboard(t, store);
      await tapKey(t, 'dashboard-year');
      expect(find.text('1.1.2026–18.11.2026'), findsOneWidget);
      await tapKey(t, 'dashboard-previous');
      expect(find.text('1.1.2025–31.12.2025'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '2,00 €',
      );
      await tapKey(t, 'dashboard-custom');
      await tapKey(t, 'dashboard-custom-cancel');
      expect(store.queries.last.unit, SpendingPeriodUnit.year);
      await tapKey(t, 'dashboard-custom');
      Future<void> enter(String key, String text) async {
        await t.enterText(find.byKey(ValueKey(key)), text);
        await t.pumpAndSettle();
      }

      await enter('dashboard-custom-from', '18.11.2026');
      await enter('dashboard-custom-through', '19.11.2026');
      await tapKey(t, 'dashboard-custom-apply');
      expect(find.textContaining('joka ei ole tulevaisuudessa'), findsWidgets);
      await enter('dashboard-custom-through', '17.11.2026');
      await tapKey(t, 'dashboard-custom-apply');
      expect(find.byKey(const Key('dashboard-custom-error')), findsOneWidget);
      await enter('dashboard-custom-from', '17.11.2026');
      await enter('dashboard-custom-through', '18.11.2026');
      await tapKey(t, 'dashboard-custom-apply');
      expect(store.queries.last.unit, SpendingPeriodUnit.custom);
      expect(
        t.widget<Text>(find.byKey(const Key('dashboard-total'))).data,
        '6,00 €',
      );
      expect(find.byKey(const Key('dashboard-previous')), findsNothing);
      await tapKey(t, 'dashboard-receipts');
      expect(store.historyFilters.last!.fromDate!.day, 17);
      expect(store.historyFilters.last!.throughDate!.day, 18);
      expect(t.takeException(), isNull);
    },
  );
}
