import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_reader/product_spending_trend_view.dart';
import 'package:receipt_reader/purchase_summary_view.dart';

import 'purchase_history_test.dart' show PurchaseStore, openPurchases, reveal;
import 'manual_save_test.dart' show tapKey;

Future<void> tap(WidgetTester t, Finder finder) async {
  await reveal(t, finder);
  await t.tap(finder.first);
  await t.pumpAndSettle();
}

void main() {
  test('arbitrary-sized percentage formatting keeps its sign and decimal', () {
    expect(purchaseChangePercent(BigInt.from(333)), '+33,3 %');
    expect(purchaseChangePercent(-BigInt.one), '-0,1 %');
    expect(purchaseChangePercent(BigInt.zero), '0,0 %');
    expect(
      purchaseChangePercent(BigInt.parse('90071992547409931')),
      '+9007199254740993,1 %',
    );
  });
  testWidgets(
    'weighted prices and first/latest purchase-day comparison render exactly',
    (t) async {
      final store = PurchaseStore();
      final p = store.seedProduct();
      await store.seed(p, date: '16.11.2026');
      await store.seed(
        p,
        quantity: 3,
        cents: 600,
        discount: 0,
        date: '17.11.2026',
      );
      await openPurchases(t, store, p);
      await reveal(
        t,
        find.text('Ostomäärällä painotettu keskihinta: 1,8000 €/kpl'),
      );
      expect(
        find.text(
          'Ensimmäisen ostopäivän keskihinta: 16.11.2026: 1,5000 €/kpl (n=1)',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Viimeisen ostopäivän keskihinta: 17.11.2026: 2,0000 €/kpl (n=1)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Muutos ensimmäisestä viimeiseen ostopäivään: +33,3 %'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'spending interval drill-down scopes all summaries and resets to all dates',
    (t) async {
      final store = PurchaseStore();
      final p = store.seedProduct();
      await store.seed(p, date: '16.11.2026');
      await store.seed(
        p,
        quantity: 3,
        cents: 600,
        discount: 0,
        date: '17.11.2026',
      );
      await store.seed(
        p,
        quantity: -2,
        cents: -400,
        discount: 0,
        date: '18.11.2026',
      );
      await store.seed(p, quantified: false, date: '19.11.2026');
      await openPurchases(t, store, p);
      final trend = t.widget<ProductSpendingTrendView>(
        find.byType(ProductSpendingTrendView),
      );
      expect(trend.summary.effectiveCents, BigInt.from(800));
      await tap(t, find.byKey(const Key('purchase-spending-details')));
      final day = purchaseCalendarDay(StoredReceiptDate.parse('18.11.2026'));
      await tap(t, find.byKey(ValueKey('purchase-spending-range-$day')));
      expect(store.ranges.last!.fromDate!.day, 18);
      expect(store.ranges.last!.throughDate!.day, 18);
      expect(store.offsets.last, 0);
      expect(
        t.widget<ListView>(find.byType(ListView).last).controller!.offset,
        0,
      );
      expect(find.text('Ostorivejä yhteensä: 1'), findsOneWidget);
      expect(
        t
            .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
            .summary
            .groups,
        isEmpty,
      );
      await tapKey(t, 'purchases-reset-range');
      expect(
        t
            .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
            .summary
            .totalRows,
        4,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'zero spend with purchases stays selectable; empty periods are disabled',
    (t) async {
      final store = PurchaseStore();
      final p = store.seedProduct();
      await store.seed(p, discount: -400, date: '16.11.2026');
      await store.seed(
        p,
        quantity: -2,
        cents: -400,
        discount: 0,
        date: '18.11.2026',
      );
      await openPurchases(t, store, p);
      await tap(t, find.byKey(const Key('purchase-spending-details')));
      final first = purchaseCalendarDay(StoredReceiptDate.parse('16.11.2026'));
      expect(
        t
            .widget<TextButton>(
              find.byKey(ValueKey('purchase-spending-range-$first')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        t
            .widget<TextButton>(
              find.byKey(ValueKey('purchase-spending-range-${first + 1}')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Ei liitettyjä ostorivejä'), findsOneWidget);
      expect(
        find.textContaining('18.11.2026–18.11.2026: -4,00 €'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'single-day and free-baseline comparisons explain missing percentages',
    (t) async {
      final store = PurchaseStore();
      final p = store.seedProduct();
      await store.seed(p, discount: -400, date: '16.11.2026');
      await openPurchases(t, store, p);
      await reveal(
        t,
        find.textContaining('Hinnan muutoksen arviointiin tarvitaan'),
      );
      expect(
        find.textContaining('Muutos ensimmäisestä viimeiseen ostopäivään:'),
        findsNothing,
      );
      await store.seed(p, discount: 0, date: '17.11.2026');
      await tapKey(t, 'purchases-refresh');
      await reveal(
        t,
        find.text(
          'Ensimmäisen päivän keskihinta on nolla; prosenttimuutosta ei lasketa.',
        ),
      );
      expect(
        find.textContaining('Muutos ensimmäisestä viimeiseen ostopäivään:'),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('paging keeps full-history weighted prices and spending totals', (
    t,
  ) async {
    final store = PurchaseStore();
    final p = store.seedProduct();
    for (var i = 0; i < 30; i++) {
      await store.seed(p, date: '16.11.2026');
    }
    await store.seed(
      p,
      quantity: 3,
      cents: 600,
      discount: 0,
      date: '17.11.2026',
    );
    await openPurchases(t, store, p);
    expect(
      t
          .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
          .summary
          .groups
          .single
          .weightedMean
          .euros,
      '1,5238',
    );
    await tap(t, find.byKey(const Key('purchases-next')));
    expect(store.offsets.last, 30);
    await reveal(
      t,
      find.text('Ostomäärällä painotettu keskihinta: 1,5238 €/kpl'),
    );
    expect(
      t
          .widget<PurchaseSummaryView>(find.byType(PurchaseSummaryView))
          .summary
          .effectiveCents,
      BigInt.from(9600),
    );
  });
  testWidgets('new trend charts and details fit 320px with doubled text', (
    t,
  ) async {
    final store = PurchaseStore();
    final p = store.seedProduct();
    await store.seed(p, date: '16.11.2026');
    await store.seed(p, discount: 0, date: '17.11.2026');
    await openPurchases(t, store, p);
    t.view.physicalSize = const Size(320, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpAndSettle();
    await tap(t, find.byKey(const Key('purchase-spending-details')));
    await reveal(
      t,
      find.text('Ostomäärällä painotettu keskihinta: 1,7500 €/kpl'),
    );
    await tap(t, find.text('Jaksojen tarkat hinnat ja havaintomäärät'));
    expect(
      find.text('Ostomäärällä painotettu keskihinta: 1,5000 €/kpl'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
