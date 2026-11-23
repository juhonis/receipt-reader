import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/product_picker.dart';

import 'category_workflow_test.dart' show CategoryStore, tap;
import 'manual_save_test.dart' show start, enter;
import 'support/fake_catalog_store.dart';

Future<void> openPicker(WidgetTester t) async {
  final selector = find.byKey(const Key('manual-product-0'));
  final button = find.descendant(
    of: selector,
    matching: find.byType(TextButton),
  );
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

ReceiptProductLink? selected(WidgetTester t) => t
    .widget<ReceiptProductSelector>(find.byKey(const Key('manual-product-0')))
    .link;

Future<void> saveCategory(
  WidgetTester t, [
  String label = 'Ruoka ja juoma',
]) async {
  await enter(t, 'catalog-category', label);
  await tap(t, 'catalog-reviewed');
  await tap(t, 'catalog-save');
}

void main() {
  testWidgets(
    'inline creation prefills receipt name and requires explicit selection',
    (t) async {
      final store = FakeCatalogStore();
      await start(t, store);
      await openPicker(t);
      await tap(t, 'picker-create-product');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('catalog-name')))
            .controller!
            .text,
        'SYNTHETIC MILK',
      );
      await saveCategory(t);
      final created = store.productRecords.single;
      expect(created.document.product.category, 'Ruoka ja juoma');
      expect(
        find.byKey(
          ValueKey('pick-product-${created.document.product.id.value}'),
        ),
        findsNothing,
      );
      expect(selected(t), isNull);
      expect(store.saved, isEmpty);
      expect(store.aliasWrites, isEmpty);
      await tap(t, 'product-recent');
      expect(selected(t)!.id, created.document.product.id);
      expect(selected(t)!.revision, created.revision);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling picker keeps its catalog save but leaves receipt unlinked',
    (t) async {
      final store = FakeCatalogStore();
      await start(t, store);
      await openPicker(t);
      await tap(t, 'picker-create-product');
      await saveCategory(t);
      await t.tap(find.text('Peruuta').last);
      await t.pumpAndSettle();
      expect(selected(t), isNull);
      expect(store.productRecords, hasLength(1));
      expect(store.saved, isEmpty);
      await openPicker(t);
      await tap(
        t,
        'pick-product-${store.productRecords.single.document.product.id.value}',
      );
      expect(selected(t)!.id, store.productRecords.single.document.product.id);
    },
  );

  testWidgets(
    'editing a picker product preserves identity and explicitly selects new revision',
    (t) async {
      final store = FakeCatalogStore();
      final original = store.seedProduct();
      await start(t, store);
      await openPicker(t);
      await tap(
        t,
        'edit-product-pick-product-${original.document.product.id.value}',
      );
      await saveCategory(t, 'Oma luokka');
      expect(selected(t), isNull);
      final revised = store.productRecords.single;
      expect(revised.document.product.id, original.document.product.id);
      expect(revised.document.expectedHead, original.revision);
      expect(revised.revision, isNot(original.revision));
      await tap(t, 'product-recent');
      expect(selected(t)!.id, revised.document.product.id);
      expect(selected(t)!.revision, revised.revision);
      expect(find.text('Tuoteluokka: Oma luokka'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain inline save retries original command without duplicating product',
    (t) async {
      final store = FakeCatalogStore()..uncertain = true;
      await start(t, store);
      await openPicker(t);
      await tap(t, 'picker-create-product');
      await saveCategory(t);
      expect(
        t.widget<TextField>(find.byKey(const Key('catalog-category'))).enabled,
        isFalse,
      );
      expect(store.productWrites, hasLength(1));
      await tap(t, 'catalog-save');
      expect(
        identical(store.productWrites.first.$1, store.productWrites.last.$1),
        isTrue,
      );
      expect(store.productWrites.first.$2, store.productWrites.last.$2);
      expect(store.productRecords, hasLength(1));
      await tap(t, 'product-recent');
      expect(selected(t)!.id, store.productRecords.single.document.product.id);
    },
  );

  testWidgets(
    'saved receipt category edit leaves receipt bytes untouched and refreshes filtered history',
    (t) async {
      final store = CategoryStore();
      final p = store.seedProduct();
      final receipt = await store.seed([
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SYNTHETIC MILK',
          kind: LineKind.product,
          cents: BigInt.from(200),
          product: p.link,
        ),
      ]);
      final bytes = ReceiptDocumentCodec.encode(receipt.document);
      await t.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async => store,
          dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'category-group-uncategorized-');
      await tap(t, 'history-${receipt.document.snapshot.id.value}');
      await tap(t, 'receipt-edit-product-${p.document.product.id.value}');
      await saveCategory(t);
      expect(find.text('Tuoteluokka: Ruoka ja juoma'), findsOneWidget);
      expect(
        ReceiptDocumentCodec.encode(store.documents.single.document),
        bytes,
      );
      Navigator.of(t.element(find.byType(ReceiptDetailPage))).pop();
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('history-${receipt.document.snapshot.id.value}')),
        findsNothing,
      );
      expect(store.historyCalls, 2);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'picker load failure can retry without creating or selecting data',
    (t) async {
      final store = FakeCatalogStore();
      await start(t, store);
      store.failBranches = true;
      await openPicker(t);
      expect(find.text('Tuotetietojen lataus epäonnistui.'), findsOneWidget);
      expect(find.byKey(const Key('picker-create-product')), findsNothing);
      store.failBranches = false;
      await t.tap(find.text('Lataa uudelleen'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('picker-create-product')), findsOneWidget);
      expect(store.productWrites, isEmpty);
      expect(selected(t), isNull);
    },
  );

  testWidgets('inline picker and editor work at 320px with doubled text', (
    t,
  ) async {
    final store = FakeCatalogStore();
    await start(t, store);
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpAndSettle();
    await openPicker(t);
    await tap(t, 'picker-create-product');
    await saveCategory(t);
    await tap(t, 'product-recent');
    expect(selected(t)!.id, store.productRecords.single.document.product.id);
    expect(t.takeException(), isNull);
  });
}
