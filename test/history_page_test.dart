import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';

import 'support/fake_store.dart';

StoredReceipt syntheticReceipt(FakeStore store) {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: store.branch,
    date: StoredReceiptDate.parse('16.11.2026'),
    totalCents: sqliteInt64Min,
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'SYNTHETIC RETURN',
        kind: LineKind.product,
        cents: sqliteInt64Min,
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
}
