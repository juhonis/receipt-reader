import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/receipt_deletion_dialog.dart';

import 'support/fake_store.dart';

void main() {
  StoredReceipt seed(FakeStore store, {String source = 'manual'}) {
    final receipt = StoredReceipt(
      ReceiptDocumentCodec.decode(
        File('packages/receipt_domain/test/fixtures/${source}_document_v1.json')
            .readAsStringSync()
            .trim(),
      ),
      RevisionId(store.branch.revision!.origin, BigInt.two),
    );
    store.documents.add(receipt);
    return receipt;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    if (target.evaluate().isEmpty) await tester.scrollUntilVisible(target, 200);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    FakeStore store, {
    bool filter = false,
  }) async {
    await tester.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
    await tester.pumpAndSettle();
    await tap(tester, 'open-history');
    if (filter) {
      await tap(tester, 'history-filters');
      await tester.enterText(
        find.byKey(const Key('history-filter-min')),
        '0,00',
      );
      await tap(tester, 'history-filter-apply');
    }
    final receipt = find.text(
      store.documents.single.document.snapshot.branch.name,
    );
    await tester.ensureVisible(receipt);
    await tester.pumpAndSettle();
    await tester.tap(receipt);
    await tester.pumpAndSettle();
    await tap(tester, 'delete-receipt');
  }

  Future<void> review(WidgetTester tester) async {
    final checkbox = find.descendant(
      of: find.byKey(const Key('delete-receipt-reviewed')),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  for (final source in ['manual', 'ocr']) {
    testWidgets(
      '$source deletion requires explicit review and refreshes filtered history',
      (tester) async {
        final store = FakeStore();
        final original = seed(store, source: source);
        await open(tester, store, filter: true);
        final filter = store.historyFilters.last;
        expect(filter, isNotNull);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('delete-receipt-confirm')),
              )
              .onPressed,
          isNull,
        );
        await review(tester);
        await tap(tester, 'delete-receipt-confirm');
        expect(store.deletions, hasLength(1));
        final command = store.deletions.single;
        expect(command.tombstone.receiptId, original.document.snapshot.id);
        expect(command.tombstone.expectedHead, original.revision);
        expect(command.tombstone.documentSha256, original.document.sha256Hex);
        expect(command.tombstone.source, source);
        expect(find.byType(ReceiptDetailPage), findsNothing);
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(store.documents, isEmpty);
        expect(identical(store.historyFilters.last, filter), isTrue);
        expect(store.historyOffsets.last, 0);
      },
    );
  }

  testWidgets(
    'cancelled deletion leaves the same receipt and detail untouched',
    (tester) async {
      final store = FakeStore();
      final original = seed(store);
      await open(tester, store);
      final reads = store.historyCalls;
      await review(tester);
      await tap(tester, 'delete-receipt-cancel');
      expect(store.deletions, isEmpty);
      expect(store.documents.single, same(original));
      expect(find.byType(ReceiptDetailPage), findsOneWidget);
      expect(store.historyCalls, reads);
    },
  );

  for (final committed in [false, true]) {
    testWidgets(
      'uncertain deletion (committed=$committed) locks confirmation and retries the identical command',
      (tester) async {
        final store = FakeStore();
        seed(store);
        if (committed) {
          store.failSaveAfterCommit = true;
        } else {
          store.saveFailure = 'database';
        }
        await open(tester, store);
        await review(tester);
        await tap(tester, 'delete-receipt-confirm');
        final first = store.deletions.single;
        expect(find.byKey(const Key('delete-receipt-reviewed')), findsNothing);
        expect(find.byKey(const Key('delete-receipt-cancel')), findsNothing);
        await Navigator.of(tester.element(find.byType(ReceiptDeletionDialog)))
            .maybePop();
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptDeletionDialog), findsOneWidget);
        store.failSaveAfterCommit = false;
        store.saveFailure = null;
        await tap(tester, 'delete-receipt-confirm');
        expect(store.deletions, hasLength(2));
        expect(identical(store.deletions.last, first), isTrue);
        expect(store.documents, isEmpty);
        expect(store.tombstones, hasLength(1));
        expect(find.byType(HistoryPage), findsOneWidget);
      },
    );
  }

  testWidgets('explicit close after uncertain deletion refreshes history', (
    tester,
  ) async {
    final store = FakeStore()..failSaveAfterCommit = true;
    seed(store);
    await open(tester, store);
    final reads = store.historyCalls;
    await review(tester);
    await tap(tester, 'delete-receipt-confirm');
    await tap(tester, 'delete-receipt-close');
    expect(store.historyCalls, reads + 1);
    expect(store.documents, isEmpty);
    expect(find.byType(ReceiptDetailPage), findsNothing);
  });

  testWidgets(
    'stale deletion never rebases or retries and returns to current history',
    (tester) async {
      final store = FakeStore();
      final original = seed(store);
      await open(tester, store);
      final current = StoredReceipt(
        original.document,
        RevisionId(original.revision.origin, BigInt.from(3)),
      );
      store.documents[0] = current;
      await review(tester);
      await tap(tester, 'delete-receipt-confirm');
      expect(
        find.textContaining('Tätä poistoa ei tallennettu.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delete-receipt-confirm')), findsNothing);
      expect(store.documents.single, same(current));
      await tap(tester, 'delete-receipt-close');
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(store.deletions, hasLength(1));
    },
  );

  testWidgets('deletion in flight cannot be dismissed or submitted twice', (
    tester,
  ) async {
    final store = FakeStore();
    seed(store);
    final gate = Completer<void>();
    store.deletionGate = gate.future;
    await open(tester, store);
    await review(tester);
    await tester.tap(find.byKey(const Key('delete-receipt-confirm')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('delete-receipt-confirm')))
          .onPressed,
      isNull,
    );
    await Navigator.of(tester.element(find.byType(ReceiptDeletionDialog)))
        .maybePop();
    await tester.pump();
    expect(find.byType(ReceiptDeletionDialog), findsOneWidget);
    expect(store.deletions, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(store.documents, isEmpty);
  });

  testWidgets('deletion confirmation fits a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = FakeStore();
    seed(store);
    await open(tester, store);
    await review(tester);
    await tap(tester, 'delete-receipt-confirm');
    expect(store.documents, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
