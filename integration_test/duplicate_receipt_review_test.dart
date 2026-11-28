import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_storage/src/database.dart';
import 'package:receipt_reader/local_store.dart';

import '../test/duplicate_receipt_review_test.dart'
    show
        runDuplicateReceiptReviewTests,
        openDuplicateOcr,
        tryDuplicateSave,
        duplicateTap;

class _ObservedStore implements LocalStore, ReceiptReplacementStore {
  _ObservedStore(this.repository);
  final ReceiptRepository repository;
  ReviewedReceipt? incoming;
  ReviewedReceiptDeletion? removed;
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
      repository.deleteReceipt(command);
  @override
  Future<SaveResult> replaceReceipt(
    ReviewedReceipt command,
    ReviewedReceiptDeletion duplicate,
  ) {
    incoming = command;
    removed = duplicate;
    return repository.replaceReceipt(command, duplicate);
  }

  @override
  Future<void> close() => repository.close();
}

ReviewedReceipt _manual(ReceiptBranch branch, int cents) {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: branch,
    date: StoredReceiptDate.parse('19.11.2026 12:34'),
    totalCents: BigInt.from(cents),
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'NATIVE TEST ITEM',
        kind: LineKind.product,
        cents: BigInt.from(cents),
      ),
    ],
  );
  final checks = ManualReviewChecks(
    snapshot: snapshot,
    expectedHeads: [],
    mutationId: DurableId.generate(),
    branchReviewed: true,
    dateReviewed: true,
    totalReviewed: true,
    reviewedRowIds: snapshot.items.map((r) => r.id),
  );
  return ReviewedReceipt.manual(
    current: snapshot,
    expectedHeads: [],
    confirmation: checks.confirm(
      reviewedAtMs: BigInt.one,
      appVersion: 'native-duplicate-test',
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runDuplicateReceiptReviewTests();
  testWidgets(
    'native SQLite replacement, rollback, reopen and backup preserve exactly one counted receipt',
    (t) async {
      final support = await getApplicationSupportDirectory();
      final directoryName =
          'receipt-duplicate-smoke-${DurableId.generate().value}';
      final directory = Directory('${support.path}/$directoryName');
      await directory.create();
      ReceiptRepository? repository;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        final database = ReceiptDatabase.file(file);
        final initial = repository = await ReceiptRepository.connect(database);
        await initial.saveManual(
          _manual(
            ReceiptBranch(id: DurableId.generate(), name: 'SYNTHETIC BRANCH'),
            300,
          ),
        );
        final old = (await initial.history()).single;
        final store = _ObservedStore(initial);
        await openDuplicateOcr(t, store);
        await tryDuplicateSave(t);
        await duplicateTap(
          t,
          'duplicate-replace-${old.document.snapshot.id.value}',
        );
        final replacement = (await initial.history()).single;
        expect(replacement.document.review.source, 'ocr');
        expect(replacement.document.snapshot.totalCents, BigInt.from(200));
        expect(
          (await initial.readDeleted(old.document.snapshot.id))!
              .tombstone
              .source,
          'manual',
        );
        final firstPair = (store.incoming!, store.removed!);

        final incoming = _manual((await initial.branches()).single, 400);
        final remove = ReceiptDeletionChecks(
          document: replacement.document,
          expectedHead: replacement.revision,
          mutationId: DurableId.generate(),
          receiptReviewed: true,
        ).confirm(deletedAtMs: BigInt.two, appVersion: 'native-duplicate-test');
        await database.customStatement(
          "CREATE TRIGGER fail_duplicate BEFORE DELETE ON receipt_items WHEN OLD.receipt_id = '${replacement.document.snapshot.id.value}' BEGIN SELECT RAISE(ABORT, 'synthetic replacement failure'); END",
        );
        await expectLater(
          initial.replaceReceipt(incoming, remove),
          throwsA(
            isA<StorageFailure>().having((e) => e.code, 'code', 'constraint'),
          ),
        );
        expect(
          (await initial.history()).single.document.sha256Hex,
          replacement.document.sha256Hex,
        );
        expect(await initial.read(incoming.document.snapshot.id), isNull);
        await database.customStatement('DROP TRIGGER fail_duplicate');
        await initial.replaceReceipt(incoming, remove);
        await t.pumpWidget(const SizedBox());
        await initial.close();
        repository = null;

        final reopened = repository = await ReceiptRepository.open(file);
        expect(
          (await reopened.history()).single.document.sha256Hex,
          incoming.document.sha256Hex,
        );
        expect(
          (await reopened.spendingSummary()).totals.totalCents,
          BigInt.from(400),
        );
        expect((await reopened.spendingSummary()).totals.receiptCount, 1);
        expect(
          (await reopened.replaceReceipt(incoming, remove)).replayed,
          isTrue,
        );
        expect(
          (await reopened.replaceReceipt(firstPair.$1, firstPair.$2)).replayed,
          isTrue,
        );
        final restored = await ReceiptRepository.restoreBackup(
          await reopened.exportBackup(),
          stagingParent: directory,
        );
        final recovered = await ReceiptRepository.open(restored.databaseFile);
        try {
          expect(
            (await recovered.history()).single.document.sha256Hex,
            incoming.document.sha256Hex,
          );
          expect((await recovered.spendingSummary()).totals.receiptCount, 1);
          expect(
            (await recovered.replaceReceipt(incoming, remove)).replayed,
            isTrue,
          );
          await recovered.verifyIntegrity();
        } finally {
          await recovered.close();
        }
        await reopened.verifyIntegrity();
      } finally {
        await t.pumpWidget(const SizedBox());
        await repository?.close();
        if (directory.absolute.parent.path != support.absolute.path ||
            directory.uri.pathSegments.where((s) => s.isNotEmpty).last !=
                directoryName) {
          throw StateError('Unexpected duplicate test directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
