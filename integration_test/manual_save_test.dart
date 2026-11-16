import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';

class _ObservedStore implements LocalStore {
  _ObservedStore(this.repository);
  final ReceiptRepository repository;
  Future<void>? _closing;
  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({int limit = 30, int offset = 0}) =>
      repository.history(limit: limit, offset: offset);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      repository.saveManual(command);
  @override
  Future<void> close() => _closing ??= repository.close();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('manual review saves offline and history survives reopening', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}/manual-ui-smoke-${DurableId.generate().value}',
    );
    await directory.create();
    _ObservedStore? store;
    try {
      final file = File('${directory.path}/receipts.sqlite');
      store = _ObservedStore(await ReceiptRepository.open(file));
      final identity = await store.repository.identity();
      final initial = store;
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () async => initial),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lisää kuitti käsin'));
      await tester.pumpAndSettle();
      await _tap(tester, 'manual-branch');
      await tester.tap(find.text('Luo uusi toimipiste').last);
      await tester.pumpAndSettle();
      await _enter(tester, 'manual-branch-name', 'SYNTHETIC UI BRANCH');
      await _enter(tester, 'manual-date', '16.11.2026');
      await _enter(tester, 'manual-total', '2,00');
      await _enter(tester, 'manual-row-name-0', 'SYNTHETIC UI MILK');
      await _enter(tester, 'manual-row-amount-0', '2,00');
      for (final key in [
        'manual-branch-reviewed',
        'manual-date-reviewed',
        'manual-total-reviewed',
        'manual-row-reviewed-0',
      ]) {
        await _tap(tester, key);
      }
      await _tap(tester, 'manual-save');
      await _tap(tester, 'confirm-save');
      expect(find.text('SYNTHETIC UI BRANCH'), findsOneWidget);
      final saved = (await store.repository.history()).single;
      expect(saved.document.snapshot.totalCents, BigInt.from(200));
      await tester.pumpWidget(const SizedBox());
      await store.close();
      store = null;
      store = _ObservedStore(await ReceiptRepository.open(file));
      final reopened = store;
      expect((await store.repository.identity()).datasetId, identity.datasetId);
      expect((await store.repository.identity()).deviceId, identity.deviceId);
      expect(
        (await store.repository.history()).single.document.sha256Hex,
        saved.document.sha256Hex,
      );
      await store.repository.verifyIntegrity();
      await tester.pumpWidget(
        ReceiptReaderApp(storageOpener: () async => reopened),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'open-history');
      await tester.tap(find.text('SYNTHETIC UI BRANCH'));
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC UI MILK'), findsOneWidget);
      expect(find.text('16.11.2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await store?.close();
      if (directory.parent.absolute.path != support.absolute.path ||
          !directory.path.contains('manual-ui-smoke-')) {
        throw StateError('unexpected_smoke_directory');
      }
      await directory.delete(recursive: true);
    }
  });
}
