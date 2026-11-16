import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled SQLite saves, reopens and retries synthetic data', (
    _,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'receipt-storage-smoke-',
    );
    ReceiptRepository? repository;
    try {
      final file = File('${directory.path}/smoke.sqlite');
      repository = await ReceiptRepository.open(file);
      final identity = await repository.identity();
      final rowId = DurableId.generate();
      final receiptId = DurableId.generate();
      final current = ReceiptSnapshot(
        id: receiptId,
        branch: ReceiptBranch(
          id: DurableId.generate(),
          name: 'SYNTHETIC TEST BRANCH',
        ),
        date: StoredReceiptDate.parse('16.11.2026'),
        totalCents: BigInt.from(200),
        items: [
          ReceiptItemSnapshot(
            id: rowId,
            name: 'SYNTHETIC MILK',
            kind: LineKind.product,
            cents: BigInt.from(200),
          ),
        ],
      );
      final checks = ManualReviewChecks(
        snapshot: current,
        expectedHeads: [],
        mutationId: DurableId.generate(),
        branchReviewed: true,
        dateReviewed: true,
        totalReviewed: true,
        reviewedRowIds: [rowId],
      );
      final pending = ReviewedReceipt.manual(
        current: current,
        expectedHeads: [],
        confirmation: checks.confirm(
          reviewedAtMs: BigInt.from(123),
          appVersion: 'native-storage-smoke',
        ),
      );
      final first = await repository.saveManual(pending);
      expect(first.revision.sequence, BigInt.two);
      expect(first.replayed, isFalse);
      await repository.close();
      repository = null;
      repository = await ReceiptRepository.open(file);
      expect((await repository.identity()).datasetId, identity.datasetId);
      expect((await repository.identity()).deviceId, identity.deviceId);
      expect((await repository.identity()).nextLocalSequence, BigInt.from(3));
      final saved = (await repository.read(receiptId))!;
      expect(saved.document.sha256Hex, pending.document.sha256Hex);
      expect(saved.document.snapshot.date.utcInstantMs, isNull);
      final retry = await repository.saveManual(pending);
      expect(retry.replayed, isTrue);
      expect(retry.revision, first.revision);
      expect((await repository.identity()).nextLocalSequence, BigInt.from(3));
      await repository.verifyIntegrity();
    } finally {
      await repository?.close();
      if (directory.parent.absolute.path !=
              Directory.systemTemp.absolute.path ||
          !directory.path.contains('receipt-storage-smoke-')) {
        throw StateError('unexpected_smoke_directory');
      }
      await directory.delete(recursive: true);
    }
  });
}
