import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/purchase_history_service.dart';

import 'catalog_page_test.dart' show openCatalog;
import 'manual_save_test.dart' show tapKey;
import 'support/fake_catalog_store.dart';

class PurchaseStore extends FakeCatalogStore implements PurchaseHistoryService {
  final observations = <StoredProductPurchase>[];
  final offsets = <int>[];
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<List<StoredProductPurchase>> purchases(
    DurableId storeId,
    DurableId productId, {
    int limit = 30,
    int offset = 0,
  }) async {
    offsets.add(offset);
    await gate?.future;
    if (fail) throw const StorageFailure('database');
    return observations.skip(offset).take(limit).toList();
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
        find.text('Sivun alin ja ylin vertailuhinta: 1,5000–2,0000 €/kpl'),
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
      expect(
        find.text('Tuotteelle ei ole tallennettuja ostorivejä.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('row pagination has page-scoped charts and independent units', (
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
    expect(find.text('Tämän sivun ostorivit: 1–30'), findsOneWidget);
    expect(find.text('Vertailukelpoisia havaintoja: 15'), findsOneWidget);
    await reveal(t, find.text('Laskettu hinta rivialennusten jälkeen (€/kg)'));
    expect(find.text('Vertailukelpoisia havaintoja: 15'), findsWidgets);
    await reveal(t, find.byKey(const Key('purchases-next')));
    await tapKey(t, 'purchases-next');
    // A new FutureBuilder starts its scroll position at the first observation.
    await t.drag(find.byType(ListView).last, const Offset(0, 20000));
    await t.pumpAndSettle();
    expect(store.offsets.last, 30);
    expect(find.text('Tämän sivun ostorivit: 31–31'), findsOneWidget);
    expect(find.text('Vertailukelpoisia havaintoja: 1'), findsOneWidget);
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
}
