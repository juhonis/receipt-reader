import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/product_picker.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'manual_save_test.dart' show tapKey, enter, start, review;
import 'support/fake_catalog_store.dart';

Future<void> openCatalog(WidgetTester t, FakeCatalogStore store) async {
  await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await t.pumpAndSettle();
  await tapKey(t, 'open-catalog');
  await tapKey(t, 'catalog-branch');
  await t.tap(find.text(store.branch.name).last);
  await t.pumpAndSettle();
}

Future<void> selectProduct(WidgetTester t, String key) async {
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> addProduct(WidgetTester t) async {
  await tapKey(t, 'catalog-add');
  await enter(t, 'catalog-name', 'SYNTHETIC MILK');
}

void main() {
  testWidgets(
    'catalog creation and correction explicitly review exact package data',
    (t) async {
      final store = FakeCatalogStore();
      await openCatalog(t, store);
      await addProduct(t);
      await enter(t, 'catalog-package', '0,750');
      await tapKey(t, 'catalog-unit');
      await t.tap(find.text('l').last);
      await t.pumpAndSettle();
      expect(
        t.widget<FilledButton>(find.byKey(const Key('catalog-save'))).onPressed,
        isNull,
      );
      await tapKey(t, 'catalog-reviewed');
      await enter(t, 'catalog-name', 'SYNTHETIC MILK 750 ML');
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('catalog-reviewed')))
            .value,
        isFalse,
      );
      await tapKey(t, 'catalog-reviewed');
      await tapKey(t, 'catalog-save');
      final first = store.productWrites.single.$1;
      expect(first.product.packageValue, BigInt.from(750000));
      expect(first.product.packageScale, 6);
      expect(first.product.packageUnit, QuantityUnit.litre);
      final id = first.product.id;
      await tapKey(t, 'catalog-product-${id.value}');
      await enter(t, 'catalog-name', 'CORRECTED MILK');
      await tapKey(t, 'catalog-reviewed');
      await tapKey(t, 'catalog-save');
      expect(store.productWrites.last.$1.product.id, id);
      expect(
        store.productWrites.last.$1.expectedHead,
        store.results[store.productWrites.first.$2]!.revision,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'alias suggestions require explicit acceptance, and aliases can deactivate and remap',
    (t) async {
      final store = FakeCatalogStore();
      final p = store.seedProduct();
      final second = store.seedProduct(name: 'OTHER MILK');
      await openCatalog(t, store);
      await t.tap(find.text('Kuittinimet'));
      await t.pumpAndSettle();
      await tapKey(t, 'catalog-add');
      await enter(t, 'catalog-name', '  SYNTHETIC  MILK ');
      await t.tap(find.text('Valitse tuote'));
      await t.pumpAndSettle();
      expect(store.aliasWrites, isEmpty);
      await selectProduct(t, 'pick-product-${p.document.product.id.value}');
      await tapKey(t, 'catalog-reviewed');
      await tapKey(t, 'catalog-save');
      final created = store.aliasWrites.single.$1;
      expect(created.alias.normalizedName, 'synthetic milk');
      expect(created.alias.productId, p.document.product.id);
      await tapKey(t, 'catalog-alias-${created.alias.id.value}');
      await tapKey(t, 'catalog-active');
      await t.tap(find.text('Valitse tuote'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('product-suggestion')), findsOneWidget);
      await selectProduct(
        t,
        'pick-product-${second.document.product.id.value}',
      );
      await tapKey(t, 'catalog-reviewed');
      await tapKey(t, 'catalog-save');
      final edited = store.aliasWrites.last.$1;
      expect(edited.alias.id, created.alias.id);
      expect(edited.alias.isActive, isFalse);
      expect(edited.alias.productId, second.document.product.id);
      expect(edited.alias.normalizedName, created.alias.normalizedName);
    },
  );
  testWidgets(
    'uncertain catalog save freezes fields and retries the identical reviewed command',
    (t) async {
      final store = FakeCatalogStore()..uncertain = true;
      await openCatalog(t, store);
      await addProduct(t);
      await tapKey(t, 'catalog-reviewed');
      await tapKey(t, 'catalog-save');
      expect(
        t.widget<TextField>(find.byKey(const Key('catalog-name'))).enabled,
        isFalse,
      );
      final first = store.productWrites.single;
      await tapKey(t, 'catalog-save');
      expect(store.productWrites, hasLength(2));
      expect(identical(first.$1, store.productWrites.last.$1), isTrue);
      expect(store.productWrites.last.$2, first.$2);
      expect(store.productRecords, hasLength(1));
    },
  );
  for (final failure in ['staleCatalog', 'aliasCollision']) {
    testWidgets('catalog $failure requires reload instead of silent rebasing', (
      t,
    ) async {
      final store = FakeCatalogStore()..catalogFailure = failure;
      await openCatalog(t, store);
      await addProduct(t);
      await tapKey(t, 'catalog-reviewed');
      await tapKey(t, 'catalog-save');
      expect(
        t.widget<FilledButton>(find.byKey(const Key('catalog-save'))).onPressed,
        isNull,
      );
      expect(store.productWrites, hasLength(1));
    });
  }
  testWidgets(
    'receipt alias remains a suggestion until selected; renamed rows clear links',
    (t) async {
      final store = FakeCatalogStore();
      final p = store.seedProduct();
      store.seedAlias(p);
      await start(t, store);
      expect(
        t
            .widget<ReceiptProductSelector>(
              find.byKey(const Key('manual-product-0')),
            )
            .link,
        isNull,
      );
      await t.ensureVisible(find.byKey(const Key('manual-product-0')));
      await t.tap(find.text('Valitse tuote'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('product-suggestion')), findsOneWidget);
      await t.tap(find.text('Peruuta'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<ReceiptProductSelector>(
              find.byKey(const Key('manual-product-0')),
            )
            .link,
        isNull,
      );
      await t.tap(find.text('Valitse tuote'));
      await t.pumpAndSettle();
      await selectProduct(t, 'product-suggestion');
      expect(
        t
            .widget<ReceiptProductSelector>(
              find.byKey(const Key('manual-product-0')),
            )
            .link!
            .id,
        p.document.product.id,
      );
      await review(t);
      await tapKey(t, 'manual-save');
      expect(
        find.text(
          'Tarkista myös tuoteliitokset. Ilman liitosta tallennettu rivi säilyy kuitissa.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Peruuta'));
      await t.pumpAndSettle();
      await enter(t, 'manual-row-name-0', 'OTHER MILK');
      expect(
        t
            .widget<ReceiptProductSelector>(
              find.byKey(const Key('manual-product-0')),
            )
            .link,
        isNull,
      );
      await t.ensureVisible(find.byKey(const Key('manual-product-0')));
      await t.tap(find.text('Valitse tuote'));
      await t.pumpAndSettle();
      await selectProduct(t, 'pick-product-${p.document.product.id.value}');
      await review(t);
      await tapKey(t, 'manual-save');
      await tapKey(t, 'confirm-save');
      expect(
        store.saved.single.document.snapshot.items.single.product!.id,
        p.document.product.id,
      );
    },
  );
  testWidgets('changing receipt branch or row kind clears selected products', (
    t,
  ) async {
    final store = FakeCatalogStore();
    final p = store.seedProduct();
    await start(t, store);
    Future<void> pick() async {
      await t.ensureVisible(find.byKey(const Key('manual-product-0')));
      await t.tap(find.text('Valitse tuote'));
      await t.pumpAndSettle();
      await selectProduct(t, 'pick-product-${p.document.product.id.value}');
    }

    await pick();
    await tapKey(t, 'manual-branch');
    await t.tap(find.text('Luo uusi toimipiste').last);
    await t.pumpAndSettle();
    expect(
      t
          .widget<ReceiptProductSelector>(
            find.byKey(const Key('manual-product-0')),
          )
          .link,
      isNull,
    );
    await tapKey(t, 'manual-branch');
    await t.tap(find.text(store.branch.name).last);
    await t.pumpAndSettle();
    await pick();
    await tapKey(t, 'manual-row-kind-0');
    await t.tap(find.text('Pantti tai pantin palautus').last);
    await t.pumpAndSettle();
    await tapKey(t, 'manual-row-kind-0');
    await t.tap(find.text('Tuote').last);
    await t.pumpAndSettle();
    expect(
      t
          .widget<ReceiptProductSelector>(
            find.byKey(const Key('manual-product-0')),
          )
          .link,
      isNull,
    );
  });
  testWidgets(
    'catalog paginates and the editor fits narrow screens with large text',
    (t) async {
      final store = FakeCatalogStore();
      for (var i = 0; i < 31; i++) {
        store.seedProduct(name: 'PRODUCT $i');
      }
      await openCatalog(t, store);
      expect(
        find.byKey(
          ValueKey(
            'catalog-product-${store.productRecords.last.document.product.id.value}',
          ),
        ),
        findsNothing,
      );
      await t.ensureVisible(find.text('Seuraavat'));
      await t.pumpAndSettle();
      await t.tap(find.text('Seuraavat'));
      await t.pumpAndSettle();
      expect(
        find.text(productLabel(store.productRecords.last)),
        findsOneWidget,
      );
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('catalog-add')), 250);
      await tapKey(t, 'catalog-add');
      await enter(t, 'catalog-name', 'NARROW TEST');
      final checkbox = find.descendant(
        of: find.byKey(const Key('catalog-reviewed')),
        matching: find.byType(Checkbox),
      );
      await t.ensureVisible(checkbox);
      await t.tap(checkbox);
      await t.pumpAndSettle();
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('catalog-reviewed')))
            .value,
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );
}
