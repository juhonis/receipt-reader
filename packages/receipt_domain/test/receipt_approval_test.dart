import 'dart:convert';
import 'dart:io';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'ocr_support.dart';

OcrFixture fixture() {
  final f = OcrFixture();
  f.rows = [
    for (final r in f.rows) OcrReviewRow(r.id, r.input, false, r.words),
  ];
  return f;
}

ReviewedReceipt accept(OcrFixture f, ReceiptReviewMethod method) {
  final audit = f.receiptAudit(
    approval: ReceiptReviewApproval(f.snapshot, method),
  );
  return f.save(
    current: audit,
    confirmation: f
        .checks(current: audit)
        .confirm(
          reviewedAtMs: BigInt.from(123),
          appVersion: 'receipt-review-test',
        ),
  );
}

void main() {
  final rejects = throwsA(isA<ReceiptDataException>());
  for (final method in ReceiptReviewMethod.values) {
    test(
      '${method.name} approval records policy 3 without claiming detailed comparisons',
      () {
        final f = fixture();
        expect(f.receiptAudit().automaticReady, isTrue);
        expect(f.receiptAudit().ready, isFalse);
        final document = accept(f, method).document;
        final text = ReceiptDocumentCodec.encode(document);
        final golden = File('test/fixtures/ocr_document_v3_quick.json')
            .readAsStringSync()
            .trim()
            .replaceFirst(
              '"review_method":"quick"',
              '"review_method":"${method.name}"',
            );
        expect(text, golden);
        final evidence =
            (jsonDecode(text) as Map)['review']['ocr_evidence'] as Map;
        expect(document.review.policyVersion, 3);
        expect(
          (document.review as OcrReviewRecord).receiptReviewMethod,
          method,
        );
        expect(evidence['review_method'], method.name);
        expect(evidence['receipt_confirmed'], isTrue);
        for (final key in [
          'rows_compared',
          'page_header_compared',
          'page_footer_compared',
          'page_layout_compared',
          'image_complete',
        ]) {
          expect(evidence.containsKey(key), isFalse, reason: key);
        }
        expect(
          ReceiptDocumentCodec.encode(ReceiptDocumentCodec.decode(text)),
          text,
        );
      },
    );
  }
  test(
    'detailed policy cannot carry an unvalidated receipt-level approval',
    () {
      final f = OcrFixture();
      final legacy = f.audit();
      final mixed = OcrEvidenceAudit(
        snapshot: legacy.snapshot,
        findings: legacy.findings,
        decisions: legacy.decisions,
        originalRowIds: legacy.originalRowIds,
        imageMatchesSource: true,
        pageApproval: PageEvidenceApproval(
          f.snapshot,
          'legacy evidence',
          headerCompared: true,
          footerCompared: true,
          layoutCompared: true,
          imageComplete: true,
        ),
        receiptApproval: ReceiptReviewApproval(
          f.snapshot,
          ReceiptReviewMethod.quick,
        ),
      );
      expect(mixed.ready, isFalse);
      expect(() => f.checks(current: mixed), rejects);
    },
  );
  test('automatic checks alone do not authorize saving', () {
    final f = fixture();
    expect(() => f.checks(current: f.receiptAudit()), rejects);
  });
  test('approval cannot bypass source, dates, branch, quantity or totals', () {
    for (final corrupt in <void Function(OcrFixture)>[
      (f) => f.total = '2,01',
      (f) => f.date = '31.02.2026',
      (f) => f.branchConfirmed = false,
      (f) {
        final r = f.rows.single;
        f.rows = [
          OcrReviewRow(
            r.id,
            const ReviewRowInput(
              'MILK',
              '2,00',
              LineKind.product,
              quantity: '2',
              rate: '3',
              unit: QuantityUnit.piece,
            ),
            false,
            r.words,
          ),
        ];
      },
      (f) => f.findings = [ParseFinding(ParseIssue.missingTotal)],
    ]) {
      final f = fixture();
      corrupt(f);
      expect(f.receiptAudit().automaticReady, isFalse);
      expect(() => accept(f, ReceiptReviewMethod.quick), rejects);
    }
    final f = fixture();
    final approval = ReceiptReviewApproval(
      f.snapshot,
      ReceiptReviewMethod.quick,
    );
    expect(
      () => f.checks(current: f.receiptAudit(approval: approval, image: false)),
      rejects,
    );
  });
  test('edits reject stale approvals and final commands even when arithmetic still matches', () {
    final f = fixture();
    final approval = ReceiptReviewApproval(
      f.snapshot,
      ReceiptReviewMethod.quick,
    );
    final audit = f.receiptAudit(approval: approval);
    final confirmation = f
        .checks(current: audit)
        .confirm(reviewedAtMs: BigInt.one, appVersion: 'test');
    final r = f.rows.single;
    f.rows = [
      OcrReviewRow(
        r.id,
        const ReviewRowInput('BREAD', '2,00', LineKind.product),
        false,
        r.words,
      ),
    ];
    expect(f.receiptAudit(approval: approval).ready, isFalse);
    final fresh = f.receiptAudit(
      approval: ReceiptReviewApproval(f.snapshot, ReceiptReviewMethod.quick),
    );
    expect(() => f.save(current: fresh, confirmation: confirmation), rejects);
    expect(
      accept(f, ReceiptReviewMethod.quick).document.snapshot.items.single.name,
      'BREAD',
    );
  });
  test('approval method is frozen in final command', () {
    final f = fixture();
    final quick = f.receiptAudit(
      approval: ReceiptReviewApproval(f.snapshot, ReceiptReviewMethod.quick),
    );
    final checks = f
        .checks(current: quick)
        .confirm(reviewedAtMs: BigInt.one, appVersion: 'test');
    final guided = f.receiptAudit(
      approval: ReceiptReviewApproval(f.snapshot, ReceiptReviewMethod.guided),
    );
    expect(() => f.save(current: guided, confirmation: checks), rejects);
  });
  test('canonical decoder rejects false approval, unsupported methods and mixed policies', () {
    final text = ReceiptDocumentCodec.encode(
      accept(fixture(), ReceiptReviewMethod.quick).document,
    );
    for (final corrupt in <void Function(Map<String, dynamic>)>[
      (r) => r['ocr_evidence']['receipt_confirmed'] = false,
      (r) => r['ocr_evidence']['review_method'] = 'automatic',
      (r) => r['ocr_evidence']['rows_compared'] = true,
      (r) => r['policy_version'] = '2',
    ]) {
      final root = jsonDecode(text) as Map<String, dynamic>;
      corrupt(root['review'] as Map<String, dynamic>);
      expect(() => ReceiptDocumentCodec.decode(jsonEncode(root)), rejects);
    }
  });
}
