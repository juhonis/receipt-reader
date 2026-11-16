import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/history_filter_dialog.dart';

import 'support/fake_store.dart';

StoredReceipt syntheticReceipt(
  FakeStore store, {
  ReceiptBranch? branch,
  String date = '16.11.2026',
  BigInt? amount,
}) {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: branch ?? store.branch,
    date: StoredReceiptDate.parse(date),
    totalCents: amount ?? sqliteInt64Min,
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'SYNTHETIC RETURN',
        kind: LineKind.product,
        cents: amount ?? sqliteInt64Min,
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
  return StoredReceipt(command.document, store.branch.revision!);
}

Future<void> openHistory(WidgetTester tester, FakeStore store) async {
  await tester.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-history')));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> filterText(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(Key('history-filter-$key')));
  await tester.enterText(find.byKey(Key('history-filter-$key')), text);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void historyTop(WidgetTester tester) {
  tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(HistoryPage),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .jumpTo(0);
}

void main() {
  test('date-only display preserves precision and printed local time', () {
    expect(
      receiptDateText(StoredReceiptDate.parse('16.11.2026')),
      '16.11.2026',
    );
    expect(
      receiptDateText(StoredReceiptDate.parse('16.11.2026 12:34')),
      '16.11.2026 12:34',
    );
    expect(
      receiptDateText(StoredReceiptDate.parse('16.11.2026 12:34:56')),
      '16.11.2026 12:34:56',
    );
  });

  testWidgets(
    'history retries reads, pages and refreshes without discarding data',
    (tester) async {
      final store = FakeStore()..failHistory = true;
      store.documents.addAll(List.generate(31, (_) => syntheticReceipt(store)));
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () async => store),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-history')));
      await tester.pumpAndSettle();
      expect(store.historyOffsets, [0]);
      store.failHistory = false;
      await tester.tap(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      expect(store.historyOffsets, [0, 0]);
      await tester.scrollUntilVisible(
        find.byKey(const Key('history-more')),
        500,
      );
      await tester.ensureVisible(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      expect(store.historyOffsets, [0, 0, 30]);
      expect(find.byKey(const Key('history-more')), findsNothing);
      await tester.tap(find.byKey(const Key('history-refresh')));
      await tester.pumpAndSettle();
      expect(store.historyOffsets, [0, 0, 30, 0]);
      expect(store.documents, hasLength(31));
    },
  );

  testWidgets(
    'history and detail fit exact large amounts on narrow enlarged screens',
    (tester) async {
      final store = FakeStore();
      store.documents.add(syntheticReceipt(store));
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () async => store),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-history')));
      await tester.tap(find.byKey(const Key('open-history')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text(store.branch.name), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.branch.name));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptDetailPage), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SYNTHETIC RETURN'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'filters combine, page, refresh, cancel drafts and reset at zero',
    (tester) async {
      final store = FakeStore();
      store.documents.add(
        syntheticReceipt(store, date: '15.11.2026', amount: BigInt.from(-50)),
      );
      store.documents.add(syntheticReceipt(store, amount: BigInt.from(100)));
      store.documents.add(
        syntheticReceipt(
          store,
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: store.branch.name,
          ),
          amount: BigInt.from(-50),
        ),
      );
      store.documents.addAll(
        List.generate(
          31,
          (_) => syntheticReceipt(store, amount: BigInt.from(-50)),
        ),
      );
      await openHistory(tester, store);
      await tapKey(tester, 'history-filters');
      await tapKey(tester, 'history-filter-branch');
      await tester.tap(find.text(store.branch.name).last);
      await tester.pumpAndSettle();
      await filterText(tester, 'from', '16.11.2026');
      await filterText(tester, 'through', '16.11.2026');
      await filterText(tester, 'min', '-0,50');
      await filterText(tester, 'max', '0.00');
      await tapKey(tester, 'history-filter-apply');
      final applied = store.historyFilters.last!;
      expect(applied.branchId, store.branch.id);
      expect(applied.fromDate!.day, 16);
      expect(applied.throughDate!.day, 16);
      expect(applied.minTotalCents, BigInt.from(-50));
      expect(applied.maxTotalCents, BigInt.zero);
      expect(store.historyOffsets, [0, 0]);
      expect(find.byKey(const Key('history-filter-summary')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('history-more')),
        500,
      );
      await tapKey(tester, 'history-more');
      expect(store.historyOffsets, [0, 0, 30]);
      expect(identical(store.historyFilters.last, applied), isTrue);
      expect(find.byKey(const Key('history-more')), findsNothing);
      await tapKey(tester, 'history-refresh');
      expect(store.historyOffsets.last, 0);
      expect(identical(store.historyFilters.last, applied), isTrue);
      historyTop(tester);
      await tester.pumpAndSettle();
      await tapKey(tester, 'history-filters');
      await filterText(tester, 'max', '999,99');
      await tapKey(tester, 'history-filter-cancel');
      expect(store.historyCalls, 4);
      await tapKey(tester, 'history-filters');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('history-filter-max')))
            .controller!
            .text,
        '0,00',
      );
      await tapKey(tester, 'history-filter-cancel');
      await tapKey(tester, 'history-reset');
      expect(store.historyOffsets.last, 0);
      expect(store.historyFilters.last, isNull);
      expect(find.byKey(const Key('history-filter-summary')), findsNothing);
      expect(store.documents, hasLength(34));
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'failed filtered reads retry the same filter and offset without old results',
    (tester) async {
      final store = FakeStore();
      store.documents.addAll(List.generate(31, (_) => syntheticReceipt(store)));
      await openHistory(tester, store);
      store.failHistory = true;
      await tapKey(tester, 'history-filters');
      await filterText(tester, 'max', '-0,01');
      await tapKey(tester, 'history-filter-apply');
      final filter = store.historyFilters.last;
      expect(find.byType(ListTile), findsNothing);
      store.failHistory = false;
      await tapKey(tester, 'history-more');
      expect(store.historyOffsets, [0, 0, 0]);
      expect(identical(store.historyFilters.last, filter), isTrue);
      store.failHistory = true;
      await tester.scrollUntilVisible(
        find.byKey(const Key('history-more')),
        500,
      );
      await tapKey(tester, 'history-more');
      expect(store.historyOffsets.last, 30);
      store.failHistory = false;
      await tapKey(tester, 'history-more');
      expect(store.historyOffsets, [0, 0, 0, 30, 30]);
      expect(identical(store.historyFilters.last, filter), isTrue);
      expect(find.byKey(const Key('history-more')), findsNothing);
      historyTop(tester);
      await tester.pumpAndSettle();
      await tapKey(tester, 'history-filters');
      await filterText(tester, 'min', '0,00');
      await filterText(tester, 'max', '0,00');
      await tapKey(tester, 'history-filter-apply');
      expect(
        find.text('Valituilla suodattimilla ei löytynyt kuitteja.'),
        findsOneWidget,
      );
      expect(find.byType(ListTile), findsNothing);
    },
  );

  testWidgets(
    'invalid filters and branch read failures cannot replace applied results',
    (tester) async {
      final store = FakeStore();
      store.documents.add(syntheticReceipt(store));
      await openHistory(tester, store);
      store.failBranches = true;
      await tapKey(tester, 'history-filters');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-filter-apply')))
            .onPressed,
        isNull,
      );
      store.failBranches = false;
      await tapKey(tester, 'history-branches-retry');
      await filterText(tester, 'from', '31.2.2026');
      await filterText(tester, 'max', '92233720368547758,08');
      await tapKey(tester, 'history-filter-apply');
      expect(find.byType(HistoryFilterDialog), findsOneWidget);
      expect(store.historyCalls, 1);
      await filterText(tester, 'from', '16.11.2026 12:34');
      await filterText(tester, 'max', '12,345');
      await tapKey(tester, 'history-filter-apply');
      expect(store.historyCalls, 1);
      await filterText(tester, 'from', '17.11.2026');
      await filterText(tester, 'through', '16.11.2026');
      await filterText(tester, 'max', '12,34');
      await tapKey(tester, 'history-filter-apply');
      expect(
        find.text('Alkupäivä ei voi olla loppupäivän jälkeen.'),
        findsOneWidget,
      );
      await filterText(tester, 'from', '16.11.2026');
      await filterText(tester, 'min', '12,35');
      await tapKey(tester, 'history-filter-apply');
      expect(
        find.text('Pienin summa ei voi olla suurinta summaa suurempi.'),
        findsOneWidget,
      );
      await tapKey(tester, 'history-filter-cancel');
      expect(store.historyCalls, 1);
      expect(find.text(store.branch.name), findsOneWidget);
    },
  );

  testWidgets(
    'filter dialog fits narrow screens with enlarged text and exact amounts',
    (tester) async {
      final store = FakeStore();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () async => store),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'open-history');
      await tapKey(tester, 'history-filters');
      await filterText(tester, 'min', '-92233720368547758,08');
      await filterText(tester, 'max', '92233720368547758,07');
      await tapKey(tester, 'history-filter-apply');
      expect(store.historyFilters.last!.minTotalCents, sqliteInt64Min);
      expect(store.historyFilters.last!.maxTotalCents, sqliteInt64Max);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'in-flight history disables filter changes to prevent mixed pages',
    (tester) async {
      final store = FakeStore();
      await openHistory(tester, store);
      final gate = Completer<void>();
      store.historyGate = gate.future;
      await tester.tap(find.byKey(const Key('history-refresh')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('history-filters')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-refresh')))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('history-filters')))
            .onPressed,
        isNotNull,
      );
    },
  );
}
