import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';

import '../packages/receipt_domain/test/ocr_support.dart';

class _ObservedStore implements LocalStore {
  _ObservedStore(this.repository);
  final ReceiptRepository repository;
  Future<void>? _closing;
  Future<SaveResult>? lastDelete;
  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) => repository.history(limit: limit, offset: offset, filter: filter);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      repository.saveManual(command);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      repository.saveOcr(command);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      lastDelete = repository.deleteReceipt(command);
  @override
  Future<void> close() => _closing ??= repository.close();
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 250);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native structured recovery preserves history and writes on a fresh origin',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = await support.createTemp('backup-restore-smoke-');
      ReceiptRepository? source;
      _ObservedStore? store;
      try {
        final file = File('${directory.path}/source.sqlite');
        source = await ReceiptRepository.open(file);
        final snapshot = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: 'MANUAL BACKUP TEST',
          ),
          date: StoredReceiptDate.parse('16.11.2026'),
          totalCents: BigInt.from(250),
          items: [
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC PRODUCT',
              kind: LineKind.product,
              cents: BigInt.from(250),
            ),
          ],
        );
        final manual = ReviewedReceipt.manual(
          current: snapshot,
          expectedHeads: const [],
          confirmation: ManualReviewChecks(
            snapshot: snapshot,
            expectedHeads: const [],
            mutationId: DurableId.generate(),
            branchReviewed: true,
            dateReviewed: true,
            totalReviewed: true,
            reviewedRowIds: snapshot.items.map((r) => r.id),
          ).confirm(reviewedAtMs: BigInt.one, appVersion: 'backup-smoke'),
        );
        final initialManual = await source.saveManual(manual);
        final receipt = (await source.read(snapshot.id))!;
        final remove = ReceiptDeletionChecks(
          document: receipt.document,
          expectedHead: receipt.revision,
          mutationId: DurableId.generate(),
          receiptReviewed: true,
        ).confirm(deletedAtMs: BigInt.two, appVersion: 'backup-smoke');
        await source.deleteReceipt(remove);
        final ocr = OcrFixture().save();
        await source.saveOcr(ocr);
        final prior = await source.identity();
        final bytes = await source.exportBackup();
        final backupFile = File('${directory.path}/synthetic-backup.json');
        await backupFile.writeAsBytes(bytes, flush: true);
        await source.close();
        source = null;
        final staged = await ReceiptRepository.restoreBackup(
          await backupFile.readAsBytes(),
          stagingParent: directory,
        );
        expect(staged.identity.datasetId, prior.datasetId);
        expect(staged.identity.deviceId, isNot(prior.deviceId));
        expect(staged.identity.nextLocalSequence, BigInt.one);
        store = _ObservedStore(
          await ReceiptRepository.open(staged.databaseFile),
        );
        expect(await store.repository.exportBackup(), bytes);
        expect(
          (await store.repository.saveManual(manual)).revision,
          initialManual.revision,
        );
        expect((await store.repository.deleteReceipt(remove)).replayed, isTrue);
        expect((await store.repository.saveOcr(ocr)).replayed, isTrue);
        final current = store;
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => current),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'open-history');
        expect(find.text('MANUAL BACKUP TEST'), findsNothing);
        final target = find.text('TEST BRANCH');
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        await tap(tester, 'delete-receipt');
        final checkbox = find.descendant(
          of: find.byKey(const Key('delete-receipt-reviewed')),
          matching: find.byType(Checkbox),
        );
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tap(tester, 'delete-receipt-confirm');
        final result = await store.lastDelete;
        await tester.pumpAndSettle();
        expect(result!.revision.origin, staged.identity.deviceId);
        expect(result.revision.sequence, BigInt.one);
        expect(await store.repository.history(), isEmpty);
        final nextBytes = await store.repository.exportBackup();
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = null;
        final second = await ReceiptRepository.restoreBackup(
          nextBytes,
          stagingParent: directory,
        );
        store = _ObservedStore(
          await ReceiptRepository.open(second.databaseFile),
        );
        expect(second.identity.deviceId, isNot(staged.identity.deviceId));
        expect(await store.repository.exportBackup(), nextBytes);
        expect(await store.repository.history(), isEmpty);
        expect(await store.repository.readDeleted(snapshot.id), isNotNull);
        expect(
          await store.repository.readDeleted(ocr.document.snapshot.id),
          isNotNull,
        );
        await store.repository.verifyIntegrity();
        final before = (await directory.list().map((e) => e.path).toList())
          ..sort();
        final invalid = Uint8List.fromList(bytes)..[bytes.length - 1] = 33;
        await expectLater(
          ReceiptRepository.restoreBackup(invalid, stagingParent: directory),
          throwsA(isA<StorageFailure>()),
        );
        expect(
          (await directory.list().map((e) => e.path).toList())..sort(),
          before,
        );
        await store.close();
        store = null;
        source = await ReceiptRepository.open(file);
        expect((await source.identity()).deviceId, prior.deviceId);
        expect(await source.exportBackup(), bytes);
        expect(await source.history(), hasLength(1));
        await source.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await store?.close();
        await source?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('backup-restore-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
