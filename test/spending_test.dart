import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/spending_service.dart';

import 'manual_save_test.dart' show tapKey, enter;
import 'support/fake_store.dart';

class SpendingStore extends FakeStore implements SpendingService {
  HistoryFilter? selected;
  Completer<void>? gate;
  String? failure;
  @override
  Future<SpendingSummary> spendingSummary({HistoryFilter? filter}) async {
    selected = filter;
    await gate?.future;
    if (failure != null) throw StorageFailure(failure!);
    final builder = SpendingSummaryBuilder();
    for (final value in await history(limit: 200, filter: filter)) {
      builder.add(value.document.snapshot);
    }
    return builder.build();
  }

  Future<void> seed() async {
    final rows = [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'UNLINKED',
        kind: LineKind.product,
        cents: BigInt.from(-50),
      ),
    ];
    final snapshot = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: branch,
      date: StoredReceiptDate.parse('17.11.2026 23:59:59'),
      totalCents: BigInt.from(-50),
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
        ).confirm(reviewedAtMs: BigInt.one, appVersion: 'widget-test'),
      ),
    );
  }
}

Future<void> open(WidgetTester t, SpendingStore store) async {
  await t.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await t.pumpAndSettle();
  await tapKey(t, 'open-spending');
}

void main() {
  testWidgets(
    'branch and month breakdowns expose exact amounts and receipt counts',
    (t) async {
      final store = SpendingStore();
      await store.seed();
      await open(t, store);
      Future<void> reveal(Finder finder) async {
        for (var i = 0; i < 25 && finder.evaluate().isEmpty; i++) {
          await t.drag(find.byType(ListView).last, const Offset(0, -180));
          await t.pumpAndSettle();
        }
        await t.ensureVisible(finder);
      }

      final branch = find.byKey(
        ValueKey('spending-branch-${store.branch.id.value}'),
      );
      await reveal(branch);
      expect(
        find.descendant(
          of: branch,
          matching: find.text('-0,50 € · Kuitteja: 1'),
        ),
        findsOneWidget,
      );
      await t.tap(
        find.descendant(of: branch, matching: find.text(store.branch.name)),
      );
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: branch,
          matching: find.text('Negatiivisen loppusumman kuitteja: 1'),
        ),
        findsOneWidget,
      );
      final month = find.byKey(const ValueKey('spending-month-2026-11'));
      await reveal(month);
      expect(
        find.descendant(of: month, matching: find.text('11.2026')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: month,
          matching: find.text('-0,50 € · Kuitteja: 1'),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'signed complete totals, inclusive date filter, reset and no amount fields',
    (t) async {
      final store = SpendingStore();
      await store.seed();
      await open(t, store);
      expect(
        find.text('Kuittien loppusummat yhteensä: -0,50 €'),
        findsOneWidget,
      );
      expect(find.text('Negatiivisen loppusumman kuitteja: 1'), findsOneWidget);
      await tapKey(t, 'spending-filter');
      expect(find.byKey(const Key('history-filter-min')), findsNothing);
      await enter(t, 'history-filter-from', '18.11.2026');
      await enter(t, 'history-filter-through', '17.11.2026');
      await tapKey(t, 'history-filter-apply');
      expect(find.byKey(const Key('history-filter-error')), findsOneWidget);
      await enter(t, 'history-filter-from', '17.11.2026');
      await tapKey(t, 'history-filter-apply');
      expect(store.selected!.throughDate!.day, 17);
      expect(
        find.text('Kuittien loppusummat yhteensä: -0,50 €'),
        findsOneWidget,
      );
      await tapKey(t, 'spending-filter');
      await enter(t, 'history-filter-from', '18.11.2026');
      await enter(t, 'history-filter-through', '');
      await tapKey(t, 'history-filter-apply');
      expect(
        find.text('Kuittien loppusummat yhteensä: 0,00 €'),
        findsOneWidget,
      );
      expect(
        find.text('Rajauksella ei löytynyt tallennettuja kuitteja.'),
        findsOneWidget,
      );
      await tapKey(t, 'spending-clear');
      expect(store.selected, isNull);
      expect(
        find.text('Kuittien loppusummat yhteensä: -0,50 €'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'refresh clears stale total while loading and failure supports retry',
    (t) async {
      final store = SpendingStore();
      await store.seed();
      await open(t, store);
      store.gate = Completer<void>();
      await t.tap(find.byKey(const Key('spending-refresh')));
      await t.pump();
      expect(find.byKey(const Key('spending-total')), findsNothing);
      store.failure = 'spendingGroupLimit';
      store.gate!.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('yli 128 toimipistettä'), findsOneWidget);
      expect(find.byKey(const Key('spending-total')), findsNothing);
      store.failure = null;
      store.gate = null;
      await tapKey(t, 'spending-retry');
      expect(find.byKey(const Key('spending-total')), findsOneWidget);
    },
  );
  testWidgets('narrow screen with large text remains usable', (t) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final store = SpendingStore();
    await store.seed();
    await open(t, store);
    expect(t.takeException(), isNull);
    await tapKey(t, 'spending-filter');
    expect(t.takeException(), isNull);
    await tapKey(t, 'history-filter-cancel');
    expect(t.takeException(), isNull);
  });
}
