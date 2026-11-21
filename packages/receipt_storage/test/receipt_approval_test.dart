import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import '../../receipt_domain/test/ocr_support.dart';
import 'support.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());
  for (final method in ReceiptReviewMethod.values) {
    test(
      '${method.name} policy-3 receipt survives reopen, retry and encrypted recovery',
      () async {
        final f = OcrFixture();
        f.rows = [
          for (final r in f.rows) OcrReviewRow(r.id, r.input, false, r.words),
        ];
        final audit = f.receiptAudit(
          approval: ReceiptReviewApproval(f.snapshot, method),
        );
        final command = f.save(
          current: audit,
          confirmation: f
              .checks(current: audit)
              .confirm(
                reviewedAtMs: BigInt.from(123),
                appVersion: 'policy-3-test',
              ),
        );
        final encoded = ReceiptDocumentCodec.encode(command.document);
        final result = await h.repository.saveOcr(command);
        expect(result.replayed, isFalse);
        await h.reopen();
        final saved = (await h.repository.history()).single;
        expect(saved.document.review.policyVersion, 3);
        expect(
          (saved.document.review as OcrReviewRecord).receiptReviewMethod,
          method,
        );
        expect(ReceiptDocumentCodec.encode(saved.document), encoded);
        expect(
          h.raw
              .select('SELECT policy_version FROM receipt_reviews')
              .single['policy_version'],
          3,
        );
        expect((await h.repository.saveOcr(command)).replayed, isTrue);
        final before = await h.repository.exportBackup();
        final encrypted = await ProtectedBackup.encrypt(
          before,
          'synthetic backup password',
        );
        final restored = await ReceiptRepository.restoreBackup(
          await ProtectedBackup.decrypt(encrypted, 'synthetic backup password'),
          stagingParent: h.directory,
        );
        final repository = await ReceiptRepository.open(restored.databaseFile);
        try {
          expect(await repository.exportBackup(), before);
          final record = (await repository.history()).single;
          expect(ReceiptDocumentCodec.encode(record.document), encoded);
          expect((await repository.saveOcr(command)).replayed, isTrue);
          await repository.verifyIntegrity();
        } finally {
          await repository.close();
        }
      },
    );
  }
}
