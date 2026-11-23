import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/catalog_page.dart';
import 'package:receipt_reader/spending_service.dart';

import 'support/fake_catalog_store.dart';
import 'catalog_page_test.dart' show openCatalog;
import 'manual_save_test.dart' show enter;

class CategoryStore extends FakeCatalogStore
    implements SpendingDashboardService {
  @override
  Future<SpendingDashboard> spendingDashboard(
    SpendingDashboardQuery query,
  ) async {
    final builder = SpendingDashboardBuilder(query);
    for (final receipt in documents) {
      builder.add(receipt.document.snapshot, productCategories: categoryLabels);
    }
    return builder.build();
  }

  Future<StoredReceipt> seed(List<ReceiptItemSnapshot> rows) async {
    final snapshot = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: branch,
      date: StoredReceiptDate.parse('18.11.2026'),
      totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
      items: rows,
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
          reviewedRowIds: rows.map((r) => r.id),
        ).confirm(reviewedAtMs: BigInt.one, appVersion: 'category-widget'),
      ),
    );
    return documents.last;
  }
}

Future<void> tap(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey(key));
  final target = key == 'catalog-reviewed'
      ? find.descendant(of: finder, matching: find.byType(Checkbox))
      : finder;
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'category changes invalidate catalog approval and retries freeze exact labels',
    (t) async {
      final store = FakeCatalogStore()..uncertain = true;
      await openCatalog(t, store);
      await tap(t, 'catalog-add');
      await enter(t, 'catalog-name', 'TEST');
      await t.tap(find.text('Ruoka ja juoma'));
      await t.pumpAndSettle();
      await tap(t, 'catalog-reviewed');
      await enter(t, 'catalog-category', 'Oma luokka');
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('catalog-reviewed')))
            .value,
        isFalse,
      );
      await tap(t, 'catalog-reviewed');
      await tap(t, 'catalog-save');
      expect(store.productWrites.single.$1.product.category, 'Oma luokka');
      expect(
        t.widget<TextField>(find.byKey(const Key('catalog-category'))).enabled,
        isFalse,
      );
      await tap(t, 'catalog-save');
      expect(
        identical(store.productWrites.first.$1, store.productWrites.last.$1),
        isTrue,
      );
      expect(store.productWrites.first.$2, store.productWrites.last.$2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'reviewed category edit regroups old purchases and drills down without rewriting receipts',
    (t) async {
      final store = CategoryStore();
      final p = store.seedProduct();
      final saved = await store.seed([
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'OLD PURCHASE',
          kind: LineKind.product,
          cents: BigInt.from(200),
          product: p.link,
        ),
      ]);
      final before = ReceiptDocumentCodec.encode(saved.document);
      await t.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async => store,
          dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Luokiteltuja tuoterivejä: 0 / 1'), findsOneWidget);
      await tap(t, 'home-tab-receipts');
      await tap(t, 'open-catalog');
      await tap(t, 'catalog-branch');
      await t.tap(find.text(store.branch.name).last);
      await t.pumpAndSettle();
      await tap(t, 'catalog-product-${p.document.product.id.value}');
      await enter(t, 'catalog-category', 'Ruoka ja juoma');
      await tap(t, 'catalog-reviewed');
      await tap(t, 'catalog-save');
      Navigator.of(t.element(find.byType(CatalogPage))).pop();
      await t.pumpAndSettle();
      await tap(t, 'home-tab-dashboard');
      expect(find.text('Luokiteltuja tuoterivejä: 1 / 1'), findsOneWidget);
      expect(
        ReceiptDocumentCodec.encode(store.documents.single.document),
        before,
      );
      await tap(t, 'category-group-product-Ruoka ja juoma');
      expect(
        store.historyFilters.last!.category,
        ReceiptCategory.product('Ruoka ja juoma'),
      );
      expect(
        find.textContaining('Kuittien loppusummat sisältävät myös muut ryhmät'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unclassified products, deposits and negative unallocated amounts stay visible',
    (t) async {
      final store = CategoryStore();
      final p = store.seedProduct(category: 'Ruoka ja juoma');
      final productId = DurableId.generate();
      await store.seed([
        ReceiptItemSnapshot(
          id: productId,
          name: 'TEST',
          kind: LineKind.product,
          cents: BigInt.from(1000),
          product: p.link,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SALE',
          kind: LineKind.discount,
          cents: BigInt.from(-100),
          parentItemId: productId,
          discountScope: DiscountScope.item,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'UNKNOWN',
          kind: LineKind.product,
          cents: BigInt.from(200),
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(50),
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'RECEIPT SALE',
          kind: LineKind.discount,
          cents: BigInt.from(-20),
          discountScope: DiscountScope.receipt,
        ),
      ]);
      await t.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async => store,
          dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Luokiteltuja tuoterivejä: 1 / 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('category-group-uncategorized-')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('category-group-receiptDiscount-')),
        findsOneWidget,
      );
      await tap(t, 'category-group-deposit-');
      expect(
        store.historyFilters.last!.category,
        const ReceiptCategory.deposit(),
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('category editor fits a narrow view with doubled text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = FakeCatalogStore();
    await openCatalog(t, store);
    await tap(t, 'catalog-add');
    await enter(t, 'catalog-name', 'TEST');
    await enter(t, 'catalog-category', 'Oma luokka');
    await tap(t, 'catalog-reviewed');
    await tap(t, 'catalog-save');
    expect(store.productWrites.single.$1.product.category, 'Oma luokka');
    expect(t.takeException(), isNull);
  });
}
