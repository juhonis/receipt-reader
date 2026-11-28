import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/product_picker.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/catalog_page.dart';
import 'package:receipt_reader/text_search_field.dart';

import 'history_page_test.dart' show syntheticReceipt, tapKey, filterText;
import 'support/fake_store.dart';
import 'support/fake_catalog_store.dart';
import 'support/navigation.dart';

void _setSearchViewport(WidgetTester t) {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding.zero;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetViewInsets);
}

Future<void> _openHistory(
  WidgetTester t,
  FakeStore store, {
  bool compact = false,
}) async {
  if (!compact) _setSearchViewport(t);
  await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await t.pumpAndSettle();
  Navigator.of(t.element(find.byType(Scaffold).first))
      .push(MaterialPageRoute<void>(builder: (_) => HistoryPage(store: store)));
  await t.pumpAndSettle();
}

Future<void> _openCatalog(WidgetTester t, FakeCatalogStore store) async {
  _setSearchViewport(t);
  await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await t.pumpAndSettle();
  Navigator.of(t.element(find.byType(Scaffold).first)).push(
    MaterialPageRoute<void>(
      builder: (_) => CatalogPage(store: store, catalog: store),
    ),
  );
  await t.pumpAndSettle();
  await tapKey(t, 'catalog-branch');
  await t.tap(find.text(store.branch.name).last);
  await t.pumpAndSettle();
}

Future<void> searchText(WidgetTester t, String key, String text) async {
  final field = find.byKey(Key(key));
  await t.ensureVisible(field);
  await t.tap(field);
  // Let a native text-input connection attach after refocusing, without waiting
  // for an unrelated pending lookup's progress animation to settle.
  await t.pump(const Duration(milliseconds: 100));
  await t.enterText(field, text);
  await t.pump(const Duration(milliseconds: 300));
  await t.pumpAndSettle();
}

Future<void> _revealHistoryEnd(WidgetTester t, Finder target) async {
  final scroll = find
      .descendant(
        of: find.byType(HistoryPage),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = t.state<ScrollableState>(scroll).position;
  // Reach the lazy list's end without platform drag velocity or IME timing
  // deciding whether the pagination control has been built yet.
  for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
    position.jumpTo(position.maxScrollExtent);
    await t.pumpAndSettle();
  }
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

class _DelayedHistory extends FakeStore {
  final latePage = Completer<List<StoredReceipt>>();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) {
    if (filter?.query == 'late') return latePage.future;
    return super.history(limit: limit, offset: offset, filter: filter);
  }
}

class _DelayedProducts extends FakeCatalogStore {
  final latePage = Completer<List<StoredProduct>>();
  @override
  Future<List<StoredProduct>> products(
    DurableId storeId, {
    int limit = 30,
    int offset = 0,
    String query = '',
  }) {
    if (query == 'late') return latePage.future;
    return super.products(storeId, limit: limit, offset: offset, query: query);
  }
}

void main() {
  runTextSearchTests();
  testWidgets(
    'a delayed parent echo preserves newer typed text and its pending query',
    (t) async {
      final applied = ValueNotifier('old');
      addTearDown(applied.dispose);
      final submitted = <String>[];
      await t.pumpWidget(const ReceiptReaderApp());
      await t.pumpAndSettle();
      Navigator.of(t.element(find.byType(Scaffold).first)).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: applied,
              builder: (_, value, _) => TextSearchField(
                fieldKey: 'echo-search',
                value: value,
                label: 'Search',
                hint: '',
                onChanged: submitted.add,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final field = find.byKey(const Key('echo-search'));
      await t.enterText(field, 'new');
      await t.pump(const Duration(milliseconds: 300));
      expect(submitted, ['new']);
      await t.enterText(field, 'newer');
      applied.value = 'new';
      await t.pump();
      expect(t.widget<TextField>(field).controller!.text, 'newer');
      await t.pump(const Duration(milliseconds: 300));
      expect(submitted, ['new', 'newer']);
      applied.value = '';
      await t.pump();
      expect(t.widget<TextField>(field).controller!.text, '');
    },
  );
}

void runTextSearchTests() {
  testWidgets(
    'receipt search finds unloaded entries, combines words across fields and clears',
    (t) async {
      final store = FakeStore();
      store.documents.addAll(
        List.generate(
          35,
          (_) => syntheticReceipt(store, amount: BigInt.from(200)),
        ),
      );
      final target = syntheticReceipt(
        store,
        branch: ReceiptBranch(id: DurableId.generate(), name: 'ÄITI MARKET'),
        amount: BigInt.from(200),
      );
      store.documents.add(target);
      await _openHistory(t, store);
      expect(
        find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
        findsNothing,
      );
      await searchText(t, 'history-search', ' äiti RETURN ');
      expect(
        find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
        findsOneWidget,
      );
      expect(store.historyOffsets.last, 0);
      await searchText(t, 'history-search', 'missing');
      expect(
        find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
        findsNothing,
      );
      await tapKey(t, 'history-search-clear');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(store.historyFilters.last, isNull);
      expect(store.historyOffsets.last, 0);
      await _revealHistoryEnd(t, find.byKey(const Key('history-more')));
      await tapKey(t, 'history-more');
      expect(store.historyOffsets.last, 30);
      await _revealHistoryEnd(
        t,
        find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
      );
      expect(
        find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'receipt query survives filter editing and clearing text preserves other filters',
    (t) async {
      final store = FakeStore();
      final target = syntheticReceipt(store, amount: BigInt.from(200));
      store.documents.add(target);
      await _openHistory(t, store);
      await searchText(t, 'history-search', 'return');
      await tapKey(t, 'history-filters');
      await filterText(t, 'from', '16.11.2026');
      await filterText(t, 'max', '2,00');
      await tapKey(t, 'history-filter-apply');
      expect(store.historyFilters.last!.query, 'return');
      expect(store.historyFilters.last!.fromDate!.day, 16);
      await tapKey(t, 'history-search-clear');
      expect(store.historyFilters.last!.query, '');
      expect(store.historyFilters.last!.maxTotalCents, BigInt.from(200));
      await tapKey(t, 'history-reset');
      expect(store.historyFilters.last, isNull);
    },
  );

  testWidgets('a late receipt page cannot replace newer search results', (
    t,
  ) async {
    final store = _DelayedHistory();
    final target = syntheticReceipt(store, amount: BigInt.from(200));
    store.documents.add(target);
    await _openHistory(t, store);
    // A pending progress indicator never settles; pump only the debounce here.
    await t.enterText(find.byKey(const Key('history-search')), 'late');
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    await searchText(t, 'history-search', 'missing');
    store.latePage.complete([target]);
    await t.pumpAndSettle();
    expect(
      find.byKey(ValueKey('history-${target.document.snapshot.id.value}')),
      findsNothing,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'catalog searches all products and active aliases, and resets paging',
    (t) async {
      final store = FakeCatalogStore();
      for (var i = 0; i < 35; i++) {
        store.seedProduct(name: 'OTHER $i');
      }
      final target = store.seedProduct(name: 'Ruisleipä');
      store.seedAlias(target);
      await _openCatalog(t, store);
      expect(
        find.byKey(ValueKey('catalog-product-${target.link.id.value}')),
        findsNothing,
      );
      await searchText(t, 'catalog-search', 'LEIPÄ');
      expect(
        find.byKey(ValueKey('catalog-product-${target.link.id.value}')),
        findsOneWidget,
      );
      await searchText(t, 'catalog-search', 'synthetic');
      expect(
        find.byKey(ValueKey('catalog-product-${target.link.id.value}')),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('Kuittinimet'));
      await t.tap(find.text('Kuittinimet'));
      await t.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            'catalog-alias-${store.aliasRecords.single.document.alias.id.value}',
          ),
        ),
        findsOneWidget,
      );
      await searchText(t, 'catalog-search', 'no match');
      await t.scrollUntilVisible(
        find.text('Ei hakutuloksia.'),
        200,
        scrollable: verticalScrollable(),
      );
      expect(find.text('Ei hakutuloksia.'), findsOneWidget);
      await tapKey(t, 'catalog-search-clear');
      expect(
        find.byKey(
          ValueKey(
            'catalog-alias-${store.aliasRecords.single.document.alias.id.value}',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'product picker search finds unloaded products and returns the chosen identity',
    (t) async {
      _setSearchViewport(t);
      final store = FakeCatalogStore();
      for (var i = 0; i < 35; i++) {
        store.seedProduct(name: 'OTHER $i');
      }
      final target = store.seedProduct(name: 'Ruisleipä');
      store.seedAlias(target);
      await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
      await t.pumpAndSettle();
      final choice = chooseProduct(
        t.element(find.byType(Scaffold).first),
        store,
        store.branch.id,
      );
      await t.pumpAndSettle();
      await searchText(t, 'picker-search', 'synthetic');
      await tapKey(t, 'pick-product-${target.link.id.value}');
      expect((await choice)!.product!.link.id, target.link.id);
    },
  );

  testWidgets(
    'late product results cannot reappear after changing the picker query',
    (t) async {
      _setSearchViewport(t);
      final store = _DelayedProducts();
      final old = store.seedProduct(name: 'OLD');
      final target = store.seedProduct(name: 'NEW');
      await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
      await t.pumpAndSettle();
      final choice = chooseProduct(
        t.element(find.byType(Scaffold).first),
        store,
        store.branch.id,
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('picker-search')), 'late');
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      await searchText(t, 'picker-search', 'new');
      store.latePage.complete([old]);
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('pick-product-${old.link.id.value}')),
        findsNothing,
      );
      await tapKey(t, 'pick-product-${target.link.id.value}');
      expect((await choice)!.product!.link.id, target.link.id);
    },
  );

  testWidgets('search and clear fit a compact display with enlarged text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 960);
    t.view.devicePixelRatio = 1;
    t.view.viewInsets = FakeViewPadding.zero;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = FakeStore();
    store.documents.add(syntheticReceipt(store, amount: BigInt.from(200)));
    await _openHistory(t, store, compact: true);
    await searchText(t, 'history-search', 'return');
    await tapKey(t, 'history-search-clear');
    final catalog = FakeCatalogStore();
    final target = catalog.seedProduct(name: 'Ruisleipä');
    final choice = chooseProduct(
      t.element(find.byType(Scaffold).last),
      catalog,
      catalog.branch.id,
    );
    await t.pumpAndSettle();
    await searchText(t, 'picker-search', 'LEIPÄ');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tapKey(t, 'pick-product-${target.link.id.value}');
    expect((await choice)!.product!.link.id, target.link.id);
    expect(t.takeException(), isNull);
  });
}
