import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_domain/receipt_domain.dart';

import 'support/fake_store.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

bool saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('manual-save')))
        .onPressed !=
    null;

Future<void> start(WidgetTester tester, FakeStore store) async {
  await tester.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lisää kuitti käsin'));
  await tester.pumpAndSettle();
  await tapKey(tester, 'manual-branch');
  await tester.tap(find.text(store.branch.name).last);
  await tester.pumpAndSettle();
  await enter(tester, 'manual-date', '16.11.2026');
  await enter(tester, 'manual-total', '2,00');
  await enter(tester, 'manual-row-name-0', 'SYNTHETIC MILK');
  await enter(tester, 'manual-row-amount-0', '2,00');
}

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

void main() {
  testWidgets(
    'save needs every check, edits invalidate them, confirmation can cancel',
    (tester) async {
      final store = FakeStore();
      await start(tester, store);
      expect(saveEnabled(tester), isFalse);
      await review(tester);
      expect(saveEnabled(tester), isTrue);
      await enter(tester, 'manual-row-name-0', 'SYNTHETIC MILK 1 L');
      expect(saveEnabled(tester), isFalse);
      for (final key in [
        'manual-branch-reviewed',
        'manual-date-reviewed',
        'manual-total-reviewed',
        'manual-row-reviewed-0',
      ]) {
        expect(
          tester.widget<CheckboxListTile>(find.byKey(ValueKey(key))).value,
          isFalse,
        );
      }
      await review(tester);
      await tapKey(tester, 'manual-save');
      await tester.tap(find.text('Peruuta'));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      await tapKey(tester, 'manual-save');
      await tapKey(tester, 'confirm-save');
      expect(store.saved, hasLength(1));
      final snapshot = store.saved.single.document.snapshot;
      expect(snapshot.branch.id, store.branch.id);
      expect(snapshot.branch.revision, store.branch.revision);
      expect(snapshot.items.single.name, 'SYNTHETIC MILK 1 L');
      expect(snapshot.totalCents, BigInt.from(200));
      expect(find.text('Kuittihistoria'), findsOneWidget);
      await tester.tap(find.text(store.branch.name));
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC MILK 1 L'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ambiguous failed save locks inputs and retries the identical command',
    (tester) async {
      final store = FakeStore()..failSaveAfterCommit = true;
      await start(tester, store);
      await review(tester);
      await tapKey(tester, 'manual-save');
      await tapKey(tester, 'confirm-save');
      expect(find.byKey(const Key('manual-save-error')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('manual-date'))).enabled,
        isFalse,
      );
      final pending = store.saved.single;
      store.failSaveAfterCommit = false;
      await tapKey(tester, 'manual-save');
      expect(store.saved, hasLength(2));
      expect(identical(store.saved.last, pending), isTrue);
      expect(store.documents, hasLength(1));
      expect(find.text(store.branch.name), findsOneWidget);
    },
  );

  testWidgets(
    'new branch is explicit even when its name matches an existing branch',
    (tester) async {
      final store = FakeStore();
      await start(tester, store);
      await tapKey(tester, 'manual-branch');
      await tester.tap(find.text('Luo uusi toimipiste').last);
      await tester.pumpAndSettle();
      await enter(tester, 'manual-branch-name', store.branch.name);
      await review(tester);
      await tapKey(tester, 'manual-save');
      await tapKey(tester, 'confirm-save');
      final branch = store.saved.single.document.snapshot.branch;
      expect(branch.name, store.branch.name);
      expect(branch.id, isNot(store.branch.id));
      expect(branch.revision, isNull);
    },
  );

  testWidgets(
    'discount needs explicit scope and removing parent clears its review',
    (tester) async {
      final store = FakeStore();
      await start(tester, store);
      await tapKey(tester, 'manual-add-row');
      await enter(tester, 'manual-row-name-1', 'SYNTHETIC DISCOUNT');
      await enter(tester, 'manual-row-amount-1', '-0,50');
      await enter(tester, 'manual-total', '1,50');
      await tapKey(tester, 'manual-row-kind-1');
      await tester.tap(find.text('Alennus').last);
      await tester.pumpAndSettle();
      await review(tester, rows: 2);
      expect(saveEnabled(tester), isFalse);
      final parent = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('manual-parent-1-'),
      );
      await tester.ensureVisible(parent);
      await tester.tap(parent);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('SYNTHETIC MILK').last);
      await tester.pumpAndSettle();
      await review(tester, rows: 2);
      expect(saveEnabled(tester), isTrue);
      await tapKey(tester, 'manual-remove-row-0');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('manual-row-reviewed-0')),
            )
            .value,
        isFalse,
      );
      expect(saveEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adjustment reason and complete exact quantity are required', (
    tester,
  ) async {
    final store = FakeStore();
    await start(tester, store);
    await tapKey(tester, 'manual-row-kind-0');
    await tester.tap(find.text('Erikseen vahvistettu oikaisu').last);
    await tester.pumpAndSettle();
    await review(tester);
    expect(saveEnabled(tester), isFalse);
    await enter(tester, 'manual-reason-0', 'SYNTHETIC REASON');
    await review(tester);
    expect(saveEnabled(tester), isTrue);
    await tester.ensureVisible(find.text('Määrä ja yksikköhinta'));
    await tester.tap(find.text('Määrä ja yksikköhinta'));
    await tester.pumpAndSettle();
    await enter(tester, 'manual-quantity-0', '0,5');
    await review(tester);
    expect(saveEnabled(tester), isFalse);
    await enter(tester, 'manual-rate-0', '4,00');
    await tapKey(tester, 'manual-unit-0');
    await tester.tap(find.text('kg').last);
    await tester.pumpAndSettle();
    await review(tester);
    expect(saveEnabled(tester), isTrue);
    await tapKey(tester, 'manual-save');
    await tapKey(tester, 'confirm-save');
    final row = store.saved.single.document.snapshot.items.single;
    expect(row.quantityValue, BigInt.from(500000));
    expect(row.rateMicros, BigInt.from(4000000));
    expect(row.quantityUnit, QuantityUnit.kg);
    expect(row.adjustmentReason, 'SYNTHETIC REASON');
  });

  testWidgets('typed discount and deposit parents survive the manual save', (
    tester,
  ) async {
    final store = FakeStore();
    await start(tester, store);
    for (final entry in [
      (1, 'SYNTHETIC DISCOUNT', '-0,50', 'Alennus'),
      (2, 'SYNTHETIC DEPOSIT', '0,15', 'Pantti tai pantin palautus'),
    ]) {
      await tapKey(tester, 'manual-add-row');
      await enter(tester, 'manual-row-name-${entry.$1}', entry.$2);
      await enter(tester, 'manual-row-amount-${entry.$1}', entry.$3);
      await tapKey(tester, 'manual-row-kind-${entry.$1}');
      await tester.tap(find.text(entry.$4).last);
      await tester.pumpAndSettle();
      final parent = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'manual-parent-${entry.$1}-',
            ),
      );
      await tester.ensureVisible(parent);
      await tester.tap(parent);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('SYNTHETIC MILK').last);
      await tester.pumpAndSettle();
    }
    await enter(tester, 'manual-total', '1,65');
    await review(tester, rows: 3);
    await tapKey(tester, 'manual-save');
    await tapKey(tester, 'confirm-save');
    final rows = store.saved.single.document.snapshot.items;
    expect(rows[1].discountScope, DiscountScope.item);
    expect(rows[1].parentItemId, rows[0].id);
    expect(rows[2].parentItemId, rows[0].id);
    expect(rows[2].kind, LineKind.deposit);
  });

  testWidgets('changed content during confirmation is rejected visibly', (
    tester,
  ) async {
    final store = FakeStore();
    await start(tester, store);
    await review(tester);
    await tapKey(tester, 'manual-save');
    tester
            .widget<TextField>(find.byKey(const Key('manual-row-name-0')))
            .controller!
            .text =
        'SYNTHETIC CHANGED';
    await tapKey(tester, 'confirm-save');
    expect(store.saved, isEmpty);
    expect(find.byKey(const Key('manual-prepare-error')), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous Helsinki times and integer overflow cannot save', (
    tester,
  ) async {
    final store = FakeStore();
    await start(tester, store);
    await enter(tester, 'manual-date', '25.10.2026 03:30');
    await review(tester);
    expect(saveEnabled(tester), isFalse);
    await enter(tester, 'manual-date', '16.11.2026');
    await enter(tester, 'manual-total', '92233720368547758,08');
    await enter(tester, 'manual-row-amount-0', '92233720368547758,08');
    await review(tester);
    expect(saveEnabled(tester), isFalse);
    expect(store.saved, isEmpty);
  });

  testWidgets('manual entry fits narrow and wide screens with enlarged text', (
    tester,
  ) async {
    final store = FakeStore();
    await start(tester, store);
    for (final size in [const Size(320, 568), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await tapKey(tester, 'manual-row-kind-0');
      await tester.tap(find.text('Erikseen vahvistettu oikaisu').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  });

  testWidgets(
    'database failure retries without reset and closes the one connection',
    (tester) async {
      final store = FakeStore();
      var opens = 0;
      await tester.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async {
            if (++opens == 1) throw StateError('synthetic failure');
            return store;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retry-storage')), findsOneWidget);
      await tapKey(tester, 'retry-storage');
      expect(opens, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(store.closeCount, 1);
    },
  );

  testWidgets(
    'opening after app disposal still closes the returned connection',
    (tester) async {
      final store = FakeStore();
      final opening = Completer<LocalStore>();
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () => opening.future),
      );
      await tester.pumpWidget(const SizedBox());
      opening.complete(store);
      await tester.pump();
      expect(store.closeCount, 1);
    },
  );
}
