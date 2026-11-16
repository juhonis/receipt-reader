import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/manual_receipt_page.dart';

import 'support/fake_store.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 300);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

bool saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('manual-save')))
        .onPressed !=
    null;

Future<void> review(WidgetTester tester, {int rows = 1}) async {
  for (final key in [
    'manual-branch-reviewed',
    'manual-date-reviewed',
    'manual-total-reviewed',
    for (var i = 0; i < rows; i++) 'manual-row-reviewed-$i',
  ]) {
    await tapKey(tester, key);
  }
}

StoredReceipt fixture(
  FakeStore store, {
  List<ReceiptItemSnapshot>? items,
  BigInt? total,
  ReceiptBranch? branch,
}) {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: branch ?? store.branch,
    date: StoredReceiptDate.parse('16.11.2026 23:59:56'),
    totalCents: total ?? BigInt.from(200),
    items:
        items ??
        [
          ReceiptItemSnapshot(
            id: DurableId.generate(),
            name: 'SYNTHETIC ORIGINAL',
            kind: LineKind.product,
            cents: BigInt.from(200),
          ),
        ],
  );
  final command = ReviewedReceipt.manual(
    current: snapshot,
    expectedHeads: [],
    confirmation: ManualReviewChecks(
      snapshot: snapshot,
      expectedHeads: [],
      mutationId: DurableId.generate(),
      branchReviewed: true,
      dateReviewed: true,
      totalReviewed: true,
      reviewedRowIds: snapshot.items.map((r) => r.id),
    ).confirm(reviewedAtMs: BigInt.one, appVersion: 'test'),
  );
  return StoredReceipt(
    command.document,
    RevisionId(store.branch.revision!.origin, BigInt.two),
  );
}

Future<void> openEditor(WidgetTester tester, FakeStore store) async {
  await tester.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await tester.pumpAndSettle();
  await tapKey(tester, 'open-history');
  await tester.scrollUntilVisible(find.text(store.branch.name), 300);
  await tester.ensureVisible(find.text(store.branch.name));
  await tester.pumpAndSettle();
  await tester.tap(find.text(store.branch.name));
  await tester.pumpAndSettle();
  await tapKey(tester, 'edit-manual-receipt');
}

Future<void> confirm(WidgetTester tester, {int rows = 1}) async {
  await review(tester, rows: rows);
  await tapKey(tester, 'manual-save');
  await tapKey(tester, 'confirm-save');
}

void main() {
  testWidgets(
    'correction requires fresh review and a change, then refreshes the same receipt',
    (tester) async {
      final store = FakeStore();
      final original = fixture(
        store,
        branch: ReceiptBranch(id: store.branch.id, name: store.branch.name),
      );
      store.documents.add(original);
      await openEditor(tester, store);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('manual-date')))
            .controller!
            .text,
        '16.11.2026 23:59:56',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('manual-row-name-0')))
            .controller!
            .text,
        'SYNTHETIC ORIGINAL',
      );
      await review(tester);
      expect(saveEnabled(tester), isFalse);
      await enter(tester, 'manual-row-name-0', 'SYNTHETIC CORRECTED');
      expect(saveEnabled(tester), isFalse);
      await review(tester);
      await tapKey(tester, 'manual-save');
      await tester.tap(find.text('Peruuta'));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      expect(
        store.documents.single.document.sha256Hex,
        original.document.sha256Hex,
      );
      await tapKey(tester, 'manual-save');
      await tapKey(tester, 'confirm-save');
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(find.byType(ReceiptDetailPage), findsNothing);
      final command = store.saved.single;
      expect(command.document.snapshot.id, original.document.snapshot.id);
      expect(
        command.document.snapshot.items.single.id,
        original.document.snapshot.items.single.id,
      );
      expect(command.document.review.expectedHeads, [original.revision]);
      expect(command.document.review.source, 'manual');
      expect(store.documents, hasLength(1));
      expect(store.historyOffsets, [0, 0]);
      await tester.tap(find.text(store.branch.name));
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC CORRECTED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained quantities, raw names, parents and reasons survive correction exactly',
    (tester) async {
      final store = FakeStore();
      final product = DurableId.generate();
      final items = [
        ReceiptItemSnapshot(
          id: product,
          name: 'SYNTHETIC APPLE',
          rawName: 'PRINTED APPLE',
          kind: LineKind.product,
          cents: BigInt.from(300),
          quantityValue: BigInt.from(15),
          quantityScale: 1,
          quantityUnit: QuantityUnit.kg,
          rateMicros: BigInt.from(2000000),
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SYNTHETIC DISCOUNT',
          kind: LineKind.discount,
          cents: BigInt.from(-50),
          parentItemId: product,
          discountScope: DiscountScope.item,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SYNTHETIC DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(10),
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SYNTHETIC ADJUSTMENT',
          kind: LineKind.adjustment,
          cents: BigInt.from(-10),
          adjustmentReason: 'SYNTHETIC REASON',
        ),
      ];
      final original = fixture(store, items: items, total: BigInt.from(250));
      store.documents.add(original);
      await openEditor(tester, store);
      await enter(tester, 'manual-date', '17.11.2026');
      await confirm(tester, rows: 4);
      final saved = store.documents.single.document.snapshot;
      expect(saved.items.map((r) => r.id), items.map((r) => r.id));
      expect(saved.items.first.rawName, 'PRINTED APPLE');
      expect(saved.items.first.quantityValue, BigInt.from(15));
      expect(saved.items.first.quantityScale, 1);
      expect(saved.items.first.rateMicros, BigInt.from(2000000));
      expect(saved.items[1].parentItemId, product);
      expect(saved.items[1].discountScope, DiscountScope.item);
      expect(saved.items[2].parentItemId, isNull);
      expect(saved.items[3].adjustmentReason, 'SYNTHETIC REASON');
      expect(saved.date.hour, isNull);
      expect(saved.date.day, 17);
    },
  );

  testWidgets(
    'removed parents require a fresh relationship and new rows get fresh IDs',
    (tester) async {
      final store = FakeStore();
      final product = DurableId.generate();
      final discount = DurableId.generate();
      final original = fixture(
        store,
        total: BigInt.from(150),
        items: [
          ReceiptItemSnapshot(
            id: product,
            name: 'SYNTHETIC PRODUCT',
            kind: LineKind.product,
            cents: BigInt.from(200),
          ),
          ReceiptItemSnapshot(
            id: discount,
            name: 'SYNTHETIC DISCOUNT',
            kind: LineKind.discount,
            cents: BigInt.from(-50),
            parentItemId: product,
            discountScope: DiscountScope.item,
          ),
        ],
      );
      store.documents.add(original);
      await openEditor(tester, store);
      await tapKey(tester, 'manual-remove-row-0');
      expect(saveEnabled(tester), isFalse);
      await tapKey(tester, 'manual-parent-0-null');
      await tester.tap(find.text('Koko kuitin alennus').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'manual-add-row');
      await enter(tester, 'manual-row-name-1', 'SYNTHETIC REPLACEMENT');
      await enter(tester, 'manual-row-amount-1', '2,00');
      await confirm(tester, rows: 2);
      final items = store.documents.single.document.snapshot.items;
      expect(items.first.id, discount);
      expect(items.first.discountScope, DiscountScope.receipt);
      expect(items.first.parentItemId, isNull);
      expect(items.last.id, isNot(product));
      expect(items.last.id, isNot(discount));
    },
  );

  for (final stale in ['staleReceipt', 'staleBranch']) {
    testWidgets(
      '$stale stops retries and returns to fresh history without overwriting',
      (tester) async {
        final store = FakeStore();
        final original = fixture(store);
        store.documents.add(original);
        await openEditor(tester, store);
        await enter(tester, 'manual-row-name-0', 'SYNTHETIC LOSING EDIT');
        if (stale == 'staleReceipt') {
          store.documents[0] = StoredReceipt(
            original.document,
            RevisionId(original.revision.origin, BigInt.from(5)),
          );
        } else {
          store.saveFailure = stale;
        }
        await confirm(tester);
        expect(saveEnabled(tester), isFalse);
        expect(
          find.textContaining('Tätä korjausta ei tallennettu.'),
          findsOneWidget,
        );
        await tapKey(tester, 'manual-close-pending');
        expect(find.byType(ReceiptDetailPage), findsNothing);
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(store.historyOffsets, [0, 0]);
        expect(
          store.documents.single.document.sha256Hex,
          original.document.sha256Hex,
        );
      },
    );
  }

  for (final retry in [true, false]) {
    testWidgets(
      'uncertain correction locks edits and ${retry ? 'retries the same command' : 'exits to refreshed history'}',
      (tester) async {
        final store = FakeStore()..failSaveAfterCommit = true;
        store.documents.add(fixture(store));
        await openEditor(tester, store);
        await enter(tester, 'manual-row-name-0', 'SYNTHETIC CORRECTED');
        await confirm(tester);
        final pending = store.saved.single;
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('manual-date')))
              .enabled,
          isFalse,
        );
        final context = tester.element(find.byType(ManualReceiptPage));
        await Navigator.of(context).maybePop();
        await tester.pumpAndSettle();
        expect(find.byType(ManualReceiptPage), findsOneWidget);
        if (retry) {
          store.failSaveAfterCommit = false;
          await tapKey(tester, 'manual-save');
          expect(identical(store.saved.last, pending), isTrue);
        } else {
          await tapKey(tester, 'manual-close-pending');
        }
        expect(store.documents, hasLength(1));
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(find.byType(ReceiptDetailPage), findsNothing);
        expect(store.historyOffsets, [0, 0]);
      },
    );
  }

  testWidgets(
    'cancelled correction never writes and OCR receipts cannot enter manual correction',
    (tester) async {
      final store = FakeStore();
      final original = fixture(store);
      store.documents.add(original);
      await openEditor(tester, store);
      await enter(tester, 'manual-total', '9,99');
      Navigator.of(tester.element(find.byType(ManualReceiptPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptDetailPage), findsOneWidget);
      expect(store.saved, isEmpty);
      expect(
        store.documents.single.document.sha256Hex,
        original.document.sha256Hex,
      );
      final ocr = ReceiptDocumentCodec.decode(
        File('packages/receipt_domain/test/fixtures/ocr_document_v1.json')
            .readAsStringSync()
            .trim(),
      );
      final storedOcr = StoredReceipt(ocr, original.revision);
      expect(
        () => ManualReceiptPage.correction(store: store, receipt: storedOcr),
        throwsArgumentError,
      );
      Navigator.of(tester.element(find.byType(ReceiptDetailPage))).pop();
      await tester.pumpAndSettle();
      store.documents[0] = storedOcr;
      await tapKey(tester, 'history-refresh');
      await tester.tap(find.text(ocr.snapshot.branch.name));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-manual-receipt')), findsNothing);
      expect(find.byKey(const Key('edit-ocr-receipt')), findsOneWidget);
    },
  );

  testWidgets(
    'correction leaving a filter refreshes its result set at offset zero',
    (tester) async {
      final store = FakeStore();
      store.documents.add(fixture(store));
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () async => store),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'open-history');
      await tapKey(tester, 'history-filters');
      await tester.enterText(
        find.byKey(const Key('history-filter-max')),
        '2,00',
      );
      await tapKey(tester, 'history-filter-apply');
      final filter = store.historyFilters.last;
      await tester.tap(find.text(store.branch.name));
      await tester.pumpAndSettle();
      await tapKey(tester, 'edit-manual-receipt');
      await enter(tester, 'manual-total', '3,00');
      await enter(tester, 'manual-row-amount-0', '3,00');
      await confirm(tester);
      expect(identical(store.historyFilters.last, filter), isTrue);
      expect(store.historyOffsets, [0, 0, 0]);
      expect(find.byType(ListTile), findsNothing);
      expect(
        find.text('Valituilla suodattimilla ei löytynyt kuitteja.'),
        findsOneWidget,
      );
      expect(
        store.documents.single.document.snapshot.totalCents,
        BigInt.from(300),
      );
    },
  );

  testWidgets(
    'correction and final confirmation fit a narrow screen with enlarged text',
    (tester) async {
      final store = FakeStore();
      store.documents.add(
        fixture(
          store,
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC RETURN',
              kind: LineKind.product,
              cents: sqliteInt64Min,
            ),
          ],
          total: sqliteInt64Min,
        ),
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openEditor(tester, store);
      await enter(tester, 'manual-date', '17.11.2026');
      await confirm(tester);
      expect(
        store.documents.single.document.snapshot.totalCents,
        sqliteInt64Min,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
