import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/purchase_history_service.dart';

import 'catalog_page_test.dart' show openCatalog;
import 'manual_save_test.dart' show tapKey, enter;
import 'support/fake_catalog_store.dart';

class PurchaseStore extends FakeCatalogStore implements PurchaseHistoryService {
  final observations = <StoredProductPurchase>[];
  final offsets = <int>[];
  bool fail = false;
  String failureCode = 'database';
  Completer<void>? gate;
  @override
  Future<List<StoredProductPurchase>> purchases(
    DurableId storeId,
    DurableId productId, {
    PurchaseDateRange? range,
    int limit = 30,
    int offset = 0,
  }) async {
    offsets.add(offset);
    await gate?.future;
    if (fail) throw StorageFailure(failureCode);
    return observations
        .where((p) => range?.contains(p.purchase.date) ?? true)
        .skip(offset)
        .take(limit)
        .toList();
  }

  final ranges = <PurchaseDateRange?>[];
  @override
  Future<PurchaseHistoryResult> purchaseHistory(
    DurableId storeId,
    DurableId productId, {
    PurchaseDateRange? range,
    int limit = 30,
    int offset = 0,
  }) async {
    ranges.add(range);
    final page = await purchases(
      storeId,
      productId,
      range: range,
      limit: limit,
      offset: offset,
    );
    final all = observations
        .where((p) => range?.contains(p.purchase.date) ?? true)
        .toList();
    final days = all.map((p) => purchaseCalendarDay(p.purchase.date)).toList()
      ..sort();
    final builder = PurchaseSummaryBuilder(
      storeId: storeId,
      productId: productId,
      firstDay: days.isEmpty
          ? null
          : range?.fromDate == null
          ? days.first
          : purchaseCalendarDay(range!.fromDate!),
      lastDay: days.isEmpty
          ? null
          : range?.throughDate == null
          ? days.last
          : purchaseCalendarDay(range!.throughDate!),
    );
    for (final item in all) {
      builder.add(item.purchase);
    }
    return PurchaseHistoryResult(builder.finish(), page);
  }

  Future<void> seed(
    StoredProduct product, {
    int quantity = 2,
    int cents = 400,
    bool quantified = true,
    QuantityUnit unit = QuantityUnit.piece,
    int discount = -100,
    String date = '17.11.2026',
  }) async {
    final row = ReceiptItemSnapshot(
      id: DurableId.generate(),
      name: 'SYNTHETIC PURCHASE',
      rawName: 'ORIGINAL NAME',
      kind: LineKind.product,
      cents: BigInt.from(cents),
      product: product.link,
      quantityValue: quantified ? BigInt.from(quantity) : null,
      quantityScale: quantified ? 0 : null,
      quantityUnit: quantified ? unit : null,
      rateMicros: quantified ? BigInt.from(2000000) : null,
    );
    final rows = [
      row,
      if (discount < 0)
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'DISCOUNT',
          kind: LineKind.discount,
          cents: BigInt.from(discount),
          discountScope: DiscountScope.item,
          parentItemId: row.id,
        ),
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'DEPOSIT',
        kind: LineKind.deposit,
        cents: BigInt.from(40),
        parentItemId: row.id,
      ),
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'RECEIPT DISCOUNT',
        kind: LineKind.discount,
        cents: BigInt.from(-10),
        discountScope: DiscountScope.receipt,
      ),
    ];
    final snapshot = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: branch,
      date: StoredReceiptDate.parse(date),
      totalCents: rows.fold(BigInt.zero, (s, r) => s + r.cents),
      items: rows,
    );
    await saveManual(
      ReviewedReceipt.manual(
        current: snapshot,
        expectedHeads: const [],
        confirmation: ManualReviewChecks(
          snapshot: snapshot,
          expectedHeads: const [],
          mutationId: DurableId.generate(),
          branchReviewed: true,
          dateReviewed: true,
          totalReviewed: true,
          reviewedRowIds: rows.map((r) => r.id),
        ).confirm(reviewedAtMs: BigInt.one, appVersion: 'test'),
      ),
    );
    observations.add(
      StoredProductPurchase(
        documents.last,
        ProductPurchase.fromReceipt(snapshot, row.id),
      ),
    );
  }
}

Future<void> openPurchases(
  WidgetTester t,
  PurchaseStore store,
  StoredProduct product,
) async {
  await openCatalog(t, store);
  await tapKey(t, 'product-history-${product.document.product.id.value}');
}

Future<void> reveal(WidgetTester t, Finder finder) async {
  for (var i = 0; finder.evaluate().isEmpty && i < 200; i++) {
    await t.drag(find.byType(ListView).last, const Offset(0, -400));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(finder.first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'history shows exact prices and separate deposits and opens the saved receipt',
    (t) async {
      final store = PurchaseStore();
      final product = store.seedProduct();
      await store.seed(product);
      await store.seed(product, discount: 0, date: '16.11.2026');
      await openPurchases(t, store, product);
      expect(find.text('Vertailukelpoisia havaintoja: 2'), findsOneWidget);
      expect(
        find.text('Aikavälin alin ja ylin vertailuhinta: 1,5000–2,0000 €/kpl'),
        findsOneWidget,
      );
      await reveal(t, find.text('Kuitin rivisumma: 4,00 €'));
      expect(
        find.text('Riviin liitetyt pantit (ei hinnassa): 0,40 €').first,
        findsOneWidget,
      );
      expect(find.text('Kuitin yksikköhinta: 2 €/kpl').first, findsOneWidget);
      await reveal(t, find.text('Avaa kuitti'));
      await t.tap(find.text('Avaa kuitti').first);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('edit-manual-receipt')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('returns and missing quantity stay visible without charts', (
    t,
  ) async {
    final store = PurchaseStore();
    final product = store.seedProduct();
    await store.seed(product, quantity: -2, cents: -400, discount: 0);
    await store.seed(product, quantified: false);
    await openPurchases(t, store, product);
    expect(find.textContaining('Vertailukelpoisia havaintoja:'), findsNothing);
    await reveal(t, find.text('Palautus — ei hintavertailussa'));
    await reveal(
      t,
      find.text('Ei tarkistettua ostomäärää — ei yksikköhintavertailussa'),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'loading failure retries and refresh discards previous chart while loading',
    (t) async {
      final store = PurchaseStore()..fail = true;
      final product = store.seedProduct();
      await store.seed(product);
      await openPurchases(t, store, product);
      expect(find.byKey(const Key('purchases-retry')), findsOneWidget);
      store.fail = false;
      await tapKey(t, 'purchases-retry');
      expect(find.text('Vertailukelpoisia havaintoja: 1'), findsOneWidget);
      store.gate = Completer<void>();
      await t.tap(find.byKey(const Key('purchases-refresh')));
      await t.pump();
      expect(find.text('Vertailukelpoisia havaintoja: 1'), findsNothing);
      store.observations.clear();
      store.gate!.complete();
      await t.pumpAndSettle();
      await reveal(t, find.text('Tuotteelle ei ole tallennettuja ostorivejä.'));
      expect(
        find.text('Tuotteelle ei ole tallennettuja ostorivejä.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('row pagination retains full-range charts and independent units', (
    t,
  ) async {
    final store = PurchaseStore();
    final product = store.seedProduct();
    for (var i = 0; i < 31; i++) {
      await store.seed(
        product,
        unit: i.isEven ? QuantityUnit.kg : QuantityUnit.litre,
      );
    }
    await openPurchases(t, store, product);
    expect(find.text('Vertailukelpoisia havaintoja: 16'), findsOneWidget);
    await reveal(t, find.text('Laskettu hinta rivialennusten jälkeen (€/kg)'));
    expect(find.text('Vertailukelpoisia havaintoja: 16'), findsOneWidget);
    await reveal(t, find.text('Tämän sivun ostorivit: 1–30'));
    await reveal(t, find.byKey(const Key('purchases-next')));
    await tapKey(t, 'purchases-next');
    // A new FutureBuilder starts its scroll position at the first observation.
    await t.drag(find.byType(ListView).last, const Offset(0, 20000));
    await t.pumpAndSettle();
    expect(store.offsets.last, 30);
    expect(find.text('Vertailukelpoisia havaintoja: 16'), findsOneWidget);
    expect(find.text('Vertailukelpoisia havaintoja: 15'), findsOneWidget);
    expect(find.text('Ostorivejä yhteensä: 31'), findsOneWidget);
    await reveal(t, find.text('Tämän sivun ostorivit: 31–31'));
    await reveal(t, find.byKey(const Key('purchases-previous')));
    await tapKey(t, 'purchases-previous');
    expect(store.offsets.last, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    '320px screen and large text wrap chart labels and financial values',
    (t) async {
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final store = PurchaseStore();
      final product = store.seedProduct();
      await store.seed(product);
      await store.seed(product, discount: 0);
      await openPurchases(t, store, product);
      t.view.physicalSize = const Size(320, 1100);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      await t.pumpAndSettle();
      await reveal(t, find.text('Vertailukelpoisia havaintoja: 2'));
      await reveal(t, find.text('Avaa kuitti'));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'date dialog validates day-only bounds, applies inclusive dates and resets without losing history',
    (t) async {
      final store = PurchaseStore();
      final product = store.seedProduct();
      await store.seed(product, date: '16.11.2026 23:59:59');
      await store.seed(product, date: '17.11.2026 00:00');
      await openPurchases(t, store, product);
      await tapKey(t, 'purchases-range');
      final calls = store.ranges.length;
      await enter(t, 'purchase-from', '29.2.2026');
      await tapKey(t, 'purchase-range-apply');
      expect(find.textContaining('Anna kelvollinen päivä'), findsOneWidget);
      expect(store.ranges.length, calls);
      await enter(t, 'purchase-from', '17.11.2026 12:00');
      await tapKey(t, 'purchase-range-apply');
      expect(store.ranges.length, calls);
      await enter(t, 'purchase-from', '17.11.2026');
      await enter(t, 'purchase-through', '16.11.2026');
      await tapKey(t, 'purchase-range-apply');
      expect(
        find.text('Alkupäivä ei voi olla loppupäivän jälkeen.'),
        findsOneWidget,
      );
      expect(store.ranges.length, calls);
      await enter(t, 'purchase-from', '16.11.2026');
      await tapKey(t, 'purchase-range-apply');
      expect(store.offsets.last, 0);
      expect(store.ranges.last!.fromDate!.day, 16);
      expect(find.text('Ostorivejä yhteensä: 1'), findsOneWidget);
      await tapKey(t, 'purchases-range');
      await enter(t, 'purchase-through', '18.11.2026');
      await t.tap(find.text('Sulje').last);
      await t.pumpAndSettle();
      expect(store.ranges.length, calls + 1);
      await tapKey(t, 'purchases-reset-range');
      expect(find.text('Ostorivejä yhteensä: 2'), findsOneWidget);
      expect(store.ranges.last!.isEmpty, isTrue);
    },
  );
  testWidgets(
    'full-range summary explains every exclusion and exposes exact bucket ranges as text',
    (t) async {
      final store = PurchaseStore();
      final product = store.seedProduct();
      await store.seed(product);
      await store.seed(product, cents: -400, quantity: -2, discount: 0);
      await store.seed(product, quantified: false);
      await store.seed(product, discount: -401);
      await store.seed(product, discount: -400);
      await openPurchases(t, store, product);
      expect(find.text('Ostorivejä yhteensä: 5'), findsOneWidget);
      expect(find.text('Hintavertailuun sisältyvät rivit: 2'), findsOneWidget);
      expect(find.text('Palautukset (ei hintavertailussa): 1'), findsOneWidget);
      expect(
        find.text('Puuttuva ostomäärä (ei hintavertailussa): 1'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Negatiivinen hinta alennusten jälkeen (ei hintavertailussa): 1',
        ),
        findsOneWidget,
      );
      await reveal(t, find.text('Jaksojen tarkat hinnat ja havaintomäärät'));
      await t.tap(find.text('Jaksojen tarkat hinnat ja havaintomäärät'));
      await t.pumpAndSettle();
      expect(
        find.text('17.11.2026–17.11.2026: 0,0000–1,5000 €/kpl (n=2)'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'too many groups asks for a shorter range and shows no partial summary',
    (t) async {
      final store = PurchaseStore()
        ..fail = true
        ..failureCode = 'purchaseGroupLimit';
      final product = store.seedProduct();
      await store.seed(product);
      await openPurchases(t, store, product);
      expect(find.textContaining('Valitse lyhyempi aikaväli.'), findsOneWidget);
      expect(find.text('Koko aikavälin yhteenveto'), findsNothing);
      store.fail = false;
      await tapKey(t, 'purchases-range');
      await enter(t, 'purchase-from', '17.11.2026');
      await tapKey(t, 'purchase-range-apply');
      expect(find.text('Ostorivejä yhteensä: 1'), findsOneWidget);
    },
  );
}
