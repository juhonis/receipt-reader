import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import '../../receipt_domain/test/ocr_support.dart';
import 'support.dart';

Matcher fails(String code) =>
    throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());
  test('OCR saves atomically, reopens with provenance and retries without duplicate events', () async {
    final saved = OcrFixture().save(),
        json = ReceiptDocumentCodec.encode(OcrFixture().save().document);
    await expectLater(
      h.repository.saveManual(saved),
      fails('unsupportedSource'),
    );
    expect(h.count('change_log'), 0);
    final result = await h.repository.saveOcr(saved);
    expect(result.replayed, isFalse);
    expect(h.count('change_log'), 2);
    await h.reopen();
    final record = (await h.repository.read(saved.document.snapshot.id))!;
    expect(ReceiptDocumentCodec.encode(record.document), json);
    expect(record.document.review.source, 'ocr');
    expect((await h.repository.saveOcr(saved)).replayed, isTrue);
    expect(h.count('change_log'), 2);
    final review = h.raw
        .select('SELECT policy_version,source FROM receipt_reviews')
        .single;
    expect(review['policy_version'], 2);
    expect(review['source'], 'ocr');
    await expectLater(
      h.repository.saveManual(
        command(
          record.document.snapshot,
          heads: [result.revision],
          mutation: 70,
        ),
      ),
      fails('provenanceChange'),
    );
    expect(h.count('change_log'), 2);
    await h.repository.verifyIntegrity();
  });
  test('OCR write failure rolls back all records and keeps exact command retryable', () async {
    final saved = OcrFixture().save();
    h.raw.execute(
      "CREATE TRIGGER synthetic_failure BEFORE INSERT ON receipt_reviews BEGIN SELECT RAISE(ABORT,'synthetic'); END",
    );
    await expectLater(h.repository.saveOcr(saved), fails('constraint'));
    for (final table in [
      'receipts',
      'receipt_items',
      'row_identities',
      'stores',
      'change_log',
      'local_mutations',
    ]) {
      expect(h.count(table), 0, reason: table);
    }
    h.raw.execute('DROP TRIGGER synthetic_failure');
    expect((await h.repository.saveOcr(saved)).replayed, isFalse);
    await h.reopen();
    expect(
      (await h.repository.history()).single.document.review,
      isA<OcrReviewRecord>(),
    );
  });
  test('removed OCR source identities remain reserved after reopen', () async {
    final source = parseReceipt(
      OcrPage(500, 500, [
        OcrWord('16.11.2026', PixelBox(10, 10, 150, 26)),
        OcrWord('MILK', PixelBox(10, 70, 150, 86)),
        OcrWord('2,00', PixelBox(400, 70, 480, 86)),
        OcrWord('BREAD', PixelBox(10, 120, 150, 136)),
        OcrWord('1,00', PixelBox(400, 120, 480, 136)),
        OcrWord('YHTEENSÄ', PixelBox(10, 220, 200, 236)),
        OcrWord('3,00', PixelBox(400, 220, 480, 236)),
      ]),
      itemTop: 40,
      priceColumnLeft: 350,
    );
    final f = OcrFixture(source: source);
    f.rows = [f.rows.last];
    f.total = '1,00';
    f.findings = [
      ...reviewFindingsForDraft(source),
      for (final w in source.rowEvidence.first)
        ParseFinding(
          ParseIssue.removedSource,
          scope: FindingScope.item,
          words: [w],
        ),
    ];
    for (var i = 0; i < f.findings!.length; i++) {
      f.decisions[i] = FindingEvidenceDecision(
        note: 'PRIVATE',
        compared: true,
        rowKind: RowEvidenceKind.duplicateOcr,
        target: f.rows.single.id,
      );
    }
    await h.repository.saveOcr(f.save());
    expect(h.count('row_identities'), 2);
    expect(h.count('receipt_items'), 1);
    await h.reopen();
    await h.repository.verifyIntegrity();
    final branch = (await h.repository.branches()).single;
    await expectLater(
      h.repository.saveManual(
        command(snapshot(number: 60, branch: branch), mutation: 61),
      ),
      fails('rowIdentityReused'),
    );
    expect(h.count('change_log'), 2);
  });
  test('manual commands cannot use OCR API', () async {
    await expectLater(
      h.repository.saveOcr(command(snapshot())),
      fails('unsupportedSource'),
    );
    expect(h.count('change_log'), 0);
  });
}
