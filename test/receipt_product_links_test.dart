import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/manual_receipt_page.dart';
import 'package:receipt_reader/ocr_correction_page.dart';
import 'package:receipt_reader/product_picker.dart';
import 'package:receipt_reader/receipt_product_links_page.dart';

import 'category_workflow_test.dart' show CategoryStore;
import 'inline_catalog_test.dart' show saveCategory;
import '../packages/receipt_domain/test/ocr_support.dart';

Future<void> tap(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }
  final target = key == 'catalog-reviewed'
      ? find.descendant(of: finder, matching: find.byType(Checkbox))
      : finder;
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<StoredReceipt> seed(CategoryStore store, {bool ocr = false}) async {
  if (!ocr) {
    return store.seed([
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'SYNTHETIC SAVED MILK',
        kind: LineKind.product,
        cents: BigInt.from(200),
      ),
    ]);
  }
  final f = OcrFixture()..branchName = store.branch.name;
  final audit = f.audit();
  final checks = OcrReviewChecks(
    audit: audit,
    branch: store.branch,
    receiptId: DurableId.generate(),
    rowIds: f.ids,
    rowDetails: const {},
    expectedHeads: const [],
    mutationId: DurableId.generate(),
    dateReviewed: true,
    totalReviewed: true,
  );
  await store.saveOcr(
    ReviewedReceipt.ocr(
      current: audit,
      branch: store.branch,
      rowDetails: const {},
      expectedHeads: const [],
      confirmation: checks.confirm(
        reviewedAtMs: BigInt.one,
        appVersion: 'saved-links-widget',
      ),
    ),
  );
  return store.documents.single;
}

Future<void> open(
  WidgetTester t,
  CategoryStore store,
  StoredReceipt receipt,
) async {
  await t.pumpWidget(
    ReceiptReaderApp(
      storageOpener: () async => store,
      dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
    ),
  );
  await t.pumpAndSettle();
  await tap(t, 'home-tab-receipts');
  await tap(t, 'open-history');
  await tap(t, 'history-${receipt.document.snapshot.id.value}');
  await tap(t, 'edit-product-links');
}

Future<void> picker(WidgetTester t) async {
  final row = find.byKey(const Key('saved-product-0'));
  if (row.evaluate().isEmpty) {
    await t.scrollUntilVisible(row, 300);
    await t.pumpAndSettle();
  }
  final finder = find.descendant(
    of: find.byKey(const Key('saved-product-0')),
    matching: find.byType(TextButton),
  );
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

bool enabled(WidgetTester t) =>
    t
        .widget<FilledButton>(find.byKey(const Key('save-product-links')))
        .onPressed !=
    null;

void main() {
  for (final ocr in [false, true]) {
    testWidgets(
      '${ocr ? 'OCR' : 'manual'} saved links approve once and preserve full correction route',
      (t) async {
        final store = CategoryStore();
        final product = store.seedProduct();
        final base = await seed(store, ocr: ocr);
        final bytes = ReceiptDocumentCodec.encode(base.document);
        await open(t, store, base);
        expect(enabled(t), isFalse);
        expect(find.byType(TextField), findsNothing);
        await picker(t);
        await tap(t, 'pick-product-${product.document.product.id.value}');
        expect(enabled(t), isTrue);
        await tap(t, 'save-product-links');
        expect(find.byType(HistoryPage), findsOneWidget);
        final saved = store.documents.single;
        validateProductLinkRevision(saved.document, base.document);
        expect(
          saved.document.snapshot.items.single.product!.id,
          product.document.product.id,
        );
        expect(saved.document.review.source, ocr ? 'ocr' : 'manual');
        expect(ReceiptDocumentCodec.encode(base.document), bytes);
        await tap(t, 'history-${base.document.snapshot.id.value}');
        await tap(t, ocr ? 'edit-ocr-receipt' : 'edit-manual-receipt');
        expect(
          ocr ? find.byType(OcrCorrectionPage) : find.byType(ManualReceiptPage),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'cancelling draft keeps receipt unchanged and retains independently created product',
    (t) async {
      final store = CategoryStore();
      final base = await seed(store);
      await open(t, store, base);
      await picker(t);
      await tap(t, 'picker-create-product');
      await saveCategory(t);
      await tap(t, 'product-recent');
      await tap(t, 'cancel-product-links');
      expect(find.byType(ReceiptDetailPage), findsOneWidget);
      expect(store.documents.single, base);
      expect(store.productRecords, hasLength(1));
    },
  );
  testWidgets(
    'uncertain committed save freezes identical command and supports retry',
    (t) async {
      final store = CategoryStore();
      final product = store.seedProduct();
      final base = await seed(store);
      await open(t, store, base);
      await picker(t);
      await tap(t, 'pick-product-${product.document.product.id.value}');
      store.failSaveAfterCommit = true;
      await tap(t, 'save-product-links');
      final command = store.saved.last;
      expect(
        t
            .widget<ReceiptProductSelector>(
              find.byKey(const Key('saved-product-0')),
            )
            .enabled,
        isFalse,
      );
      expect(find.byKey(const Key('cancel-product-links')), findsNothing);
      await tap(t, 'save-product-links');
      expect(identical(store.saved.last, command), isTrue);
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(store.documents.single.revision.sequence, BigInt.from(3));
    },
  );
  testWidgets(
    'stale receipt closes to refreshed history without editing frozen selections',
    (t) async {
      final store = CategoryStore();
      final product = store.seedProduct();
      final base = await seed(store);
      await open(t, store, base);
      await picker(t);
      await tap(t, 'pick-product-${product.document.product.id.value}');
      store.saveFailure = 'staleReceipt';
      await tap(t, 'save-product-links');
      expect(find.byKey(const Key('save-product-links')), findsNothing);
      await tap(t, 'close-product-links');
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(store.documents.single, base);
    },
  );
  testWidgets(
    'unlink only saves after explicit approval and restores unclassified reporting',
    (t) async {
      final store = CategoryStore();
      final product = store.seedProduct();
      final base = await store.seed([
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'LINKED',
          kind: LineKind.product,
          cents: BigInt.from(200),
          product: product.link,
        ),
      ]);
      await open(t, store, base);
      await picker(t);
      await tap(t, 'unlink-product');
      expect(store.documents.single, base);
      expect(enabled(t), isTrue);
      await tap(t, 'save-product-links');
      expect(
        store.documents.single.document.snapshot.items.single.product,
        isNull,
      );
    },
  );
  testWidgets(
    'reselecting original links disables save; replacement is explicit',
    (t) async {
      final store = CategoryStore();
      final first = store.seedProduct();
      final second = store.seedProduct(name: 'SECOND PRODUCT');
      final base = await store.seed([
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'LINKED',
          kind: LineKind.product,
          cents: BigInt.from(200),
          product: first.link,
        ),
      ]);
      await open(t, store, base);
      await picker(t);
      await tap(t, 'pick-product-${first.document.product.id.value}');
      expect(enabled(t), isFalse);
      await picker(t);
      await tap(t, 'pick-product-${second.document.product.id.value}');
      expect(enabled(t), isTrue);
      expect(store.documents.single, base);
      await tap(t, 'save-product-links');
      expect(
        store.documents.single.document.snapshot.items.single.product!.id,
        second.link.id,
      );
    },
  );
  testWidgets(
    'linking from unclassified history refreshes its category filter',
    (t) async {
      final store = CategoryStore();
      final product = store.seedProduct(category: 'Ruoka ja juoma');
      final base = await seed(store);
      await t.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async => store,
          dashboardClock: () => DateTime.utc(2026, 11, 18, 12),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'category-group-uncategorized-');
      await tap(t, 'history-${base.document.snapshot.id.value}');
      await tap(t, 'edit-product-links');
      await picker(t);
      await tap(t, 'pick-product-${product.document.product.id.value}');
      await tap(t, 'save-product-links');
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(
        find.byKey(ValueKey('history-${base.document.snapshot.id.value}')),
        findsNothing,
      );
      expect(store.historyCalls, 2);
    },
  );
  testWidgets('saved link editor supports narrow screens and large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = CategoryStore();
    final product = store.seedProduct();
    final base = await seed(store);
    await open(t, store, base);
    await picker(t);
    await tap(t, 'pick-product-${product.document.product.id.value}');
    await tap(t, 'save-product-links');
    expect(find.byType(ReceiptProductLinksPage), findsNothing);
    expect(t.takeException(), isNull);
  });
}
