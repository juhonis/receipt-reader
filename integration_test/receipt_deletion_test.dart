import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/local_store.dart';

import '../packages/receipt_domain/test/ocr_support.dart';
import '../test/support/navigation.dart';

class _ObservedStore implements LocalStore {
  _ObservedStore(this.repository);
  final ReceiptRepository repository;
  Future<void>? _closing;
  Future<SaveResult>? lastWrite;
  Future<SaveResult>? lastDelete;
  ReviewedReceiptDeletion? deletion;
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
      lastWrite = repository.saveManual(command);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      repository.saveOcr(command);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) {
    deletion = command;
    return lastDelete = repository.deleteReceipt(command);
  }

  @override
  Future<void> close() => _closing ??= repository.close();
}

ReviewedReceipt _command(
  ReceiptSnapshot snapshot, {
  List<RevisionId> heads = const [],
}) => ReviewedReceipt.manual(
  current: snapshot,
  expectedHeads: heads,
  confirmation: ManualReviewChecks(
    snapshot: snapshot,
    expectedHeads: heads,
    mutationId: DurableId.generate(),
    branchReviewed: true,
    dateReviewed: true,
    totalReviewed: true,
    reviewedRowIds: snapshot.items.map((r) => r.id),
  ).confirm(reviewedAtMs: BigInt.one, appVersion: 'correction-smoke'),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: verticalScrollable(),
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

ReviewedReceipt _concurrent(StoredReceipt receipt, ReceiptBranch branch) {
  final f = OcrFixture();
  final audit = f.audit();
  final checks = OcrReviewChecks(
    audit: audit,
    branch: branch,
    receiptId: receipt.document.snapshot.id,
    rowIds: f.ids,
    rowDetails: const {},
    expectedHeads: [receipt.revision],
    mutationId: DurableId.generate(),
    dateReviewed: true,
    totalReviewed: true,
  );
  return ReviewedReceipt.ocr(
    current: audit,
    branch: branch,
    rowDetails: const {},
    expectedHeads: [receipt.revision],
    confirmation: checks.confirm(
      reviewedAtMs: BigInt.from(456),
      appVersion: 'native-correction-test',
    ),
  );
}

Future<void> _openDetail(WidgetTester tester, String branch) async {
  final target = find.text(branch);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  await _tap(tester, 'delete-receipt');
}

Future<void> _review(WidgetTester tester) async {
  final checkbox = find.descendant(
    of: find.byKey(const Key('delete-receipt-reviewed')),
    matching: find.byType(Checkbox),
  );
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native reviewed deletion preserves tombstones and rejects stale screens',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        '${support.path}/receipt-deletion-smoke-${DurableId.generate().value}',
      );
      await directory.create();
      _ObservedStore? store;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        store = _ObservedStore(await ReceiptRepository.open(file));
        final manual = _command(
          ReceiptSnapshot(
            id: DurableId.generate(),
            branch: ReceiptBranch(
              id: DurableId.generate(),
              name: 'MANUAL DELETE TEST',
            ),
            date: StoredReceiptDate.parse('16.11.2026'),
            totalCents: BigInt.from(200),
            items: [
              ReceiptItemSnapshot(
                id: DurableId.generate(),
                name: 'SYNTHETIC ITEM',
                kind: LineKind.product,
                cents: BigInt.from(200),
              ),
            ],
          ),
        );
        final initialManual = await store.repository.saveManual(manual);
        final ocr = OcrFixture().save();
        await store.repository.saveOcr(ocr);
        var currentStore = store;
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => currentStore),
        );
        await tester.pumpAndSettle();
        await openReceiptManagement(tester);
        await _tap(tester, 'open-history');
        await _openDetail(tester, 'MANUAL DELETE TEST');
        await _tap(tester, 'delete-receipt-cancel');
        expect(find.byType(ReceiptDetailPage), findsOneWidget);
        expect(
          await store.repository.read(manual.document.snapshot.id),
          isNotNull,
        );
        await _tap(tester, 'delete-receipt');
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('delete-receipt-confirm')),
              )
              .onPressed,
          isNull,
        );
        await _review(tester);
        await _tap(tester, 'delete-receipt-confirm');
        await store.lastDelete;
        await tester.pumpAndSettle();
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(find.text('MANUAL DELETE TEST'), findsNothing);
        final manualDelete = store.deletion!;
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = _ObservedStore(await ReceiptRepository.open(file));
        expect(
          (await store.repository.readDeleted(manual.document.snapshot.id))!
              .tombstone
              .sha256Hex,
          manualDelete.tombstone.sha256Hex,
        );
        expect(
          (await store.repository.deleteReceipt(manualDelete)).replayed,
          isTrue,
        );
        expect(
          (await store.repository.saveManual(manual)).revision,
          initialManual.revision,
        );
        expect(
          await store.repository.read(manual.document.snapshot.id),
          isNull,
        );
        expect(await store.repository.history(), hasLength(1));
        await store.repository.verifyIntegrity();
        currentStore = store;
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => currentStore),
        );
        await tester.pumpAndSettle();
        await openReceiptManagement(tester);
        await _tap(tester, 'open-history');
        await _openDetail(tester, 'TEST BRANCH');
        final prior = (await store.repository.history()).single;
        final branch = (await store.repository.branches()).singleWhere(
          (b) => b.id == prior.document.snapshot.branch.id,
        );
        final correction = _concurrent(prior, branch);
        await store.repository.saveOcr(correction);
        await _review(tester);
        await _tap(tester, 'delete-receipt-confirm');
        await expectLater(
          store.lastDelete,
          throwsA(
            isA<StorageFailure>().having((e) => e.code, 'code', 'staleReceipt'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('delete-receipt-confirm')), findsNothing);
        expect(
          (await store.repository.history()).single.document.sha256Hex,
          correction.document.sha256Hex,
        );
        await _tap(tester, 'delete-receipt-close');
        await _openDetail(tester, 'TEST BRANCH');
        await _review(tester);
        await _tap(tester, 'delete-receipt-confirm');
        await store.lastDelete;
        await tester.pumpAndSettle();
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(find.text('TEST BRANCH'), findsNothing);
        final ocrDelete = store.deletion!;
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = _ObservedStore(await ReceiptRepository.open(file));
        expect(await store.repository.history(), isEmpty);
        expect(
          (await store.repository.readDeleted(ocr.document.snapshot.id))!
              .tombstone
              .sha256Hex,
          ocrDelete.tombstone.sha256Hex,
        );
        expect(
          (await store.repository.deleteReceipt(ocrDelete)).replayed,
          isTrue,
        );
        expect((await store.repository.saveOcr(ocr)).replayed, isTrue);
        expect(await store.repository.history(), isEmpty);
        expect(await store.repository.branches(), hasLength(2));
        await store.repository.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('receipt-deletion-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
