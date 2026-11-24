import 'package:flutter_test/flutter_test.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/l10n/generated/app_localizations.dart';
import 'package:receipt_reader/product_comparison_page.dart';
import 'package:receipt_reader/product_comparison_service.dart';
import 'package:receipt_reader/purchase_history_page.dart';

import 'product_rankings_test.dart' show tap;
import 'support/ranking_store.dart';

class ComparisonStore extends RankingStore implements ProductComparisonService {
  bool fail = false;
  final ranges = <PurchaseDateRange?>[];
  final contributions = <DurableId, List<ProductPurchase>>{};
  StoredProduct create(
    ReceiptBranch branch,
    int size, {
    String? key = 'DEMO Coffee',
  }) {
    final p = StoredProduct(
      ProductDocument(
        product: ProductSnapshot(
          id: DurableId.generate(),
          storeId: branch.id,
          canonicalName: 'Coffee',
          comparisonKey: key,
          category: 'Food',
          packageValue: BigInt.from(size),
          packageScale: 3,
          packageUnit: QuantityUnit.kg,
        ),
        storeRevision: branch.revision!,
        expectedHead: null,
        reviewedAtMs: BigInt.one,
        appVersion: 'widget-test',
      ),
      RevisionId(branch.revision!.origin, BigInt.from(sequence++)),
    );
    productRecords.add(p);
    final row = ReceiptItemSnapshot(
      id: DurableId.generate(),
      name: 'Coffee',
      kind: LineKind.product,
      cents: BigInt.from(300),
      quantityValue: BigInt.one,
      quantityScale: 0,
      quantityUnit: QuantityUnit.piece,
      rateMicros: BigInt.from(3000000),
      product: p.link,
    );
    final receipt = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: branch,
      date: StoredReceiptDate.parse('17.11.2026'),
      totalCents: BigInt.from(300),
      items: [row],
    );
    contributions[p.link.id] = [ProductPurchase.fromReceipt(receipt, row.id)];
    return p;
  }

  @override
  Future<ProductComparisonResult> productComparison(
    DurableId productId, {
    PurchaseDateRange? range,
  }) async {
    ranges.add(range);
    if (fail) throw const StorageFailure('database');
    final anchor = productRecords.singleWhere((p) => p.link.id == productId);
    final members = [
      if (anchor.document.product.comparisonKey != null)
        for (final p in productRecords)
          if (p.document.product.comparisonKey ==
              anchor.document.product.comparisonKey)
            ComparisonMember(
              p,
              (await branches()).singleWhere((b) => b.id == p.link.storeId),
            ),
    ];
    final b = ProductComparisonBuilder(
      purchaseCalendarDay(
        range?.fromDate ?? StoredReceiptDate.parse('1.11.2026'),
      ),
      purchaseCalendarDay(
        range?.throughDate ?? StoredReceiptDate.parse('30.11.2026'),
      ),
    );
    for (final m in members) {
      for (final p in contributions[m.product.link.id]!) {
        if (range?.contains(p.date) ?? true) {
          b.add(p, m.product.document.product, m.branch);
        }
      }
    }
    return ProductComparisonResult(anchor, members, b.finish());
  }
}

Future<(ComparisonStore, StoredProduct)> openComparison(
  WidgetTester t, {
  bool grouped = true,
}) async {
  final store = ComparisonStore();
  final other = ReceiptBranch(
    id: DurableId.generate(),
    name: 'SECOND STORE',
    revision: store.branch.revision,
  );
  store.otherBranches.add(other);
  final p = store.create(
    store.branch,
    500,
    key: grouped ? 'DEMO Coffee' : null,
  );
  store.create(other, 1000);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('fi'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProductComparisonPage(
        store: store,
        service: store,
        catalog: store,
        productId: p.link.id,
      ),
    ),
  );
  await t.pumpAndSettle();
  return (store, p);
}

void main() {
  testWidgets(
    'weighted prices and trend selection retain exact range into product history',
    (t) async {
      final (store, _) = await openComparison(t);
      expect(find.text('3,0000 €/kg'), findsWidgets);
      expect(find.text('6,0000 €/kg'), findsWidgets);
      final beforeInterval = t
          .widget<Text>(find.byKey(const Key('comparison-trend-selection-kg')))
          .data;
      await tap(t, 'comparison-trend-prev-kg');
      expect(
        t
            .widget<Text>(
              find.byKey(const Key('comparison-trend-selection-kg')),
            )
            .data,
        isNot(beforeInterval),
      );
      await tap(t, 'comparison-range');
      await t.enterText(find.byKey(const Key('purchase-from')), '17.11.2026');
      await t.enterText(
        find.byKey(const Key('purchase-through')),
        '17.11.2026',
      );
      await tap(t, 'purchase-range-apply');
      expect(store.ranges.last!.fromDate!.day, 17);
      await tap(t, 'comparison-store-${store.branch.id.value}-kg');
      final p = store.productRecords.first;
      await tap(t, 'comparison-member-${p.link.id.value}');
      expect(find.byType(PurchaseHistoryPage), findsOneWidget);
      expect(store.scopes.last.range!.throughDate!.day, 17);
      expect(store.scopes.last.product, p.link.id);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'comparison group edits preserve category and package, and clearing removes membership',
    (t) async {
      final (store, _) = await openComparison(t);
      await tap(t, 'comparison-edit');
      await t.enterText(find.byKey(const Key('catalog-comparison')), '');
      await tap(t, 'catalog-reviewed');
      await tap(t, 'catalog-save');
      expect(store.productWrites.single.$1.product.comparisonKey, isNull);
      expect(store.productWrites.single.$1.product.category, 'Food');
      expect(
        store.productWrites.single.$1.product.packageValue,
        BigInt.from(500),
      );
      expect(find.byKey(const Key('comparison-unit-kg')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('failure hides stale prices and retries', (t) async {
    final (store, _) = await openComparison(t);
    store.fail = true;
    await tap(t, 'comparison-refresh');
    expect(find.byKey(const Key('comparison-unit-kg')), findsNothing);
    store.fail = false;
    await tap(t, 'comparison-retry');
    expect(find.byKey(const Key('comparison-unit-kg')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'no automatic same-name grouping; empty group has setup instructions',
    (t) async {
      await openComparison(t, grouped: false);
      expect(find.byKey(const Key('comparison-unit-kg')), findsNothing);
      expect(find.textContaining('täsmälleen sama ryhmänimi'), findsOneWidget);
      await tap(t, 'comparison-help');
      expect(
        find.textContaining('kuitille tallennetun tuoteversion'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'comparison and catalog group editor fit 320px with doubled text',
    (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await openComparison(t);
      await tap(t, 'comparison-trend-kg');
      await tap(t, 'comparison-edit');
      await tap(t, 'catalog-comparison');
      expect(t.takeException(), isNull);
    },
  );
}
