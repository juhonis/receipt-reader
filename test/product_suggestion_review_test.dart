import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/product_picker.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import 'ocr_review_guidance_test.dart' show reveal;
import 'support/fake_catalog_store.dart';

const _rawName = 'TEST COCONVT DRINK 1L';
const _correctName = 'TEST COCONUT DRINK 1L';

class _ObservedCatalog extends FakeCatalogStore {
  Completer<void>? readGate;
  bool failProducts = false;
  @override
  Future<List<StoredProduct>> products(
    DurableId storeId, {
    int limit = 30,
    int offset = 0,
  }) async {
    if (failProducts) throw const StorageFailure('database');
    return super.products(storeId, limit: limit, offset: offset);
  }

  @override
  Future<StoredProduct?> readProduct(DurableId id) async {
    await readGate?.future;
    return super.readProduct(id);
  }
}

Future<ReceiptDraft> _open(WidgetTester tester, FakeCatalogStore store) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final evidence = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 600);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return ReceiptEvidence.decode(bytes!.buffer.asUint8List());
  }))!;
  addTearDown(evidence.dispose);
  final draft = parseReceipt(
    OcrPage(800, 600, [
      OcrWord(store.branch.name, PixelBox(20, 20, 400, 36)),
      OcrWord('19.11.2026', PixelBox(20, 70, 200, 86)),
      OcrWord(_rawName, PixelBox(20, 150, 400, 166)),
      OcrWord('3,00', PixelBox(650, 150, 720, 166)),
      OcrWord('2 kpl 1,50 €/kpl', PixelBox(20, 180, 400, 196)),
      OcrWord('TEST BREAD', PixelBox(20, 220, 200, 236)),
      OcrWord('2,00', PixelBox(650, 220, 720, 236)),
      OcrWord('YHTEENSÄ', PixelBox(20, 270, 200, 286)),
      OcrWord('5,00', PixelBox(650, 270, 720, 286)),
    ]),
    itemTop: 120,
    priceColumnLeft: 600,
  );
  await tester.pumpWidget(const ReceiptReaderApp());
  Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ReviewPage(draft: draft, evidence: evidence, store: store),
    ),
  );
  await tester.pumpAndSettle();
  return draft;
}

Future<void> _suggest(WidgetTester tester) async {
  await reveal(tester, 'ocr-product-suggestions-0');
  await tester.tap(find.byKey(const Key('ocr-product-suggestions-0')));
  await tester.pumpAndSettle();
}

String _name(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('row-name-0')))
    .controller!
    .text;
ReceiptProductLink? _link(WidgetTester tester) => tester
    .widget<ReceiptProductSelector>(find.byKey(const Key('ocr-product-0')))
    .link;

Future<void> _save(WidgetTester tester) async {
  await reveal(tester, 'ocr-save');
  expect(
    tester.widget<FilledButton>(find.byKey(const Key('ocr-save'))).onPressed,
    isNotNull,
  );
  await tester.tap(find.byKey(const Key('ocr-save')));
  await tester.pumpAndSettle();
}

void main() => runProductSuggestionReviewTests();

/// Portable synthetic pixels and fake storage; no normal app database is opened.
void runProductSuggestionReviewTests() {
  testWidgets(
    'name-only correction preserves OCR source, finances and final approval',
    (tester) async {
      final store = _ObservedCatalog();
      final product = store.seedProduct(name: _correctName);
      final draft = await _open(tester, store);
      await _suggest(tester);
      expect(store.saved, isEmpty);
      await tester.tap(
        find.byKey(ValueKey('suggest-name-${product.link.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(_name(tester), _correctName);
      expect(_link(tester), isNull);
      expect(draft.rows.first.name, _rawName);
      expect(draft.rowEvidence.first.first.text, _rawName);
      expect(store.saved, isEmpty);
      expect(store.productWrites, isEmpty);
      expect(store.aliasWrites, isEmpty);
      await _save(tester);
      final snapshot = store.saved.single.document.snapshot;
      expect(snapshot.items.first.name, _correctName);
      expect(snapshot.items.first.rawName, _rawName);
      expect(snapshot.items.first.product, isNull);
      expect(snapshot.items.map((r) => r.cents), [
        BigInt.from(300),
        BigInt.from(200),
      ]);
      expect(
        snapshot.items.first.quantityValue,
        draft.rows.first.quantity!.value,
      );
      expect(snapshot.items.first.rateMicros, draft.rows.first.rateMicros);
      expect(snapshot.totalCents, BigInt.from(500));
      expect(snapshot.date.day, 19);
    },
  );

  testWidgets(
    'link-only suggestion keeps the printed name and exact product revision',
    (tester) async {
      final store = _ObservedCatalog();
      final product = store.seedProduct(name: _correctName);
      await _open(tester, store);
      await _suggest(tester);
      await tester.tap(
        find.byKey(ValueKey('suggest-link-${product.link.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(_name(tester), _rawName);
      expect(_link(tester)!.id, product.link.id);
      expect(store.saved, isEmpty);
      await _save(tester);
      final row = store.saved.single.document.snapshot.items.first;
      expect(row.name, _rawName);
      expect(row.rawName, _rawName);
      expect(row.product!.revision, product.revision);
      expect(store.productWrites, isEmpty);
      expect(store.aliasWrites, isEmpty);
    },
  );

  testWidgets('cancelling suggestions leaves the draft and catalog untouched', (
    tester,
  ) async {
    final store = _ObservedCatalog()..seedProduct(name: _correctName);
    await _open(tester, store);
    await _suggest(tester);
    await tester.tap(find.text('Peruuta').last);
    await tester.pumpAndSettle();
    expect(_name(tester), _rawName);
    expect(_link(tester), isNull);
    expect(store.saved, isEmpty);
    expect(store.productWrites, isEmpty);
    expect(store.aliasWrites, isEmpty);
  });

  testWidgets('a changed product must be reviewed again before selecting', (
    tester,
  ) async {
    final store = _ObservedCatalog();
    final original = store.seedProduct(name: _correctName);
    await _open(tester, store);
    await _suggest(tester);
    store.productRecords[0] = StoredProduct(
      original.document,
      RevisionId(store.branch.revision!.origin, BigInt.from(900)),
    );
    await tester.tap(
      find.byKey(ValueKey('suggest-link-${original.link.id.value}')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Tuotetiedot ovat muuttuneet'), findsOneWidget);
    expect(store.saved, isEmpty);
    await tester.tap(
      find.byKey(ValueKey('suggest-link-${original.link.id.value}')),
    );
    await tester.pumpAndSettle();
    expect(_link(tester)!.revision.sequence, BigInt.from(900));
  });

  testWidgets('catalog load failure retries without changing the receipt', (
    tester,
  ) async {
    final store = _ObservedCatalog()..seedProduct(name: _correctName);
    await _open(tester, store);
    store.failProducts = true;
    await _suggest(tester);
    expect(find.text('Tuotetietojen lataus epäonnistui.'), findsOneWidget);
    store.failProducts = false;
    await tester.tap(find.text('Lataa uudelleen'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_correctName), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets(
    'name changes clear an earlier explicit link instead of carrying it silently',
    (tester) async {
      final store = _ObservedCatalog();
      final product = store.seedProduct(name: _correctName);
      await _open(tester, store);
      await _suggest(tester);
      await tester.tap(
        find.byKey(ValueKey('suggest-link-${product.link.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(_link(tester), isNotNull);
      await _suggest(tester);
      await tester.tap(
        find.byKey(ValueKey('suggest-name-${product.link.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(_name(tester), _correctName);
      expect(_link(tester), isNull);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets('suggestions fit a compact screen with doubled text', (
    tester,
  ) async {
    final store = _ObservedCatalog()..seedProduct(name: _correctName);
    await _open(tester, store);
    tester.view.physicalSize = const Size(320, 960);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await _suggest(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Käytä nimeä'));
    await tester.tap(find.text('Käytä nimeä'));
    await tester.pumpAndSettle();
    await reveal(tester, 'row-name-0');
    expect(_name(tester), _correctName);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing a pending choice preserves subsequent user edits', (
    tester,
  ) async {
    final store = _ObservedCatalog();
    final product = store.seedProduct(name: _correctName);
    await _open(tester, store);
    await _suggest(tester);
    store.readGate = Completer<void>();
    await tester.tap(
      find.byKey(ValueKey('suggest-link-${product.link.id.value}')),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('row-name-0')),
      'User edited product',
    );
    store.readGate!.complete();
    await tester.pumpAndSettle();
    expect(_name(tester), 'User edited product');
    expect(_link(tester), isNull);
    expect(store.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an empty catalog leaves name correction manual and saving available',
    (tester) async {
      final store = _ObservedCatalog();
      await _open(tester, store);
      await _suggest(tester);
      expect(
        find.textContaining('Sopivia ehdotuksia ei löytynyt'),
        findsOneWidget,
      );
      await tester.tap(find.text('Peruuta').last);
      await tester.pumpAndSettle();
      await _save(tester);
      expect(store.saved.single.document.snapshot.items.first.name, _rawName);
      expect(store.saved.single.document.snapshot.items.first.product, isNull);
    },
  );
}
