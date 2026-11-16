import 'dart:convert';
import 'dart:io';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'ocr_support.dart';
import 'support.dart' show id;

final rejects = throwsA(isA<ReceiptDataException>());
void main() {
  test('ready OCR command has separate provenance, canonical bytes, and no pixels or free-text evidence', () {
    final f = OcrFixture(), saved = OcrFixture();
    final command = f.save();
    final text = ReceiptDocumentCodec.encode(command.document);
    expect(
      text,
      File('test/fixtures/ocr_document_v1.json').readAsStringSync().trim(),
    );
    expect(
      ReceiptDocumentCodec.encode(ReceiptDocumentCodec.decode(text)),
      text,
    );
    expect(command.document.review, isA<OcrReviewRecord>());
    expect(command.document.review.source, 'ocr');
    expect(command.document.review.policyVersion, 2);
    expect(command.document.snapshot.items.single.rawName, 'MILK');
    expect(text, isNot(contains('PRIVATE NOTE')));
    expect(text, isNot(contains('PixelBox')));
    expect(saved.save().document.sha256Hex, command.document.sha256Hex);
    expect(
      () => (command.document.review as OcrReviewRecord).originalRowIds.clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'missing source, page, row, final field and arithmetic checks reject',
    () {
      final f = OcrFixture();
      for (final audit in [f.audit(image: false), f.audit(page: false)]) {
        expect(() => f.checks(current: audit), rejects);
      }
      for (final checks in [
        f.checks(dateChecked: false),
        f.checks(totalChecked: false),
      ]) {
        expect(
          () => checks.confirm(reviewedAtMs: BigInt.one, appVersion: 'test'),
          rejects,
        );
      }
      final r = f.rows.single;
      f.rows = [OcrReviewRow(r.id, r.input, false, r.words)];
      expect(() => f.checks(), rejects);
      f.rows = [r];
      f.total = '2,01';
      expect(() => f.checks(), rejects);
      f.total = '2,00';
      f.branchConfirmed = false;
      expect(() => f.checks(), rejects);
    },
  );
  test('changes to values, identity, evidence, compared flag, branch or expected heads require fresh review', () {
    final f = OcrFixture(), confirmation = OcrFixture().confirm();
    expect(() => f.save(confirmation: confirmation), rejects);
    final approved = f.confirm(), row = f.rows.single;
    for (final input in [
      const ReviewRowInput('CORRECTED', '2,00', LineKind.product),
      const ReviewRowInput('MILK', '2,00', LineKind.deposit),
    ]) {
      f.rows = [OcrReviewRow(row.id, input, true, row.words)];
      expect(() => f.save(confirmation: approved), rejects);
    }
    f.rows = [OcrReviewRow(row.id, row.input, false, row.words)];
    expect(() => f.save(confirmation: approved), rejects);
    f.rows = [row];
    f.branchName = 'OTHER';
    expect(() => f.save(confirmation: approved), rejects);
    f.branchName = 'TEST BRANCH';
    expect(
      () => f.save(
        confirmation: approved,
        heads: [RevisionId(id(80), BigInt.one)],
      ),
      rejects,
    );
    f.rows = [
      OcrReviewRow(row.id, row.input, true, [
        ...row.words,
        f.draft.parseContext!.page.words.first,
      ]),
    ];
    expect(() => f.save(confirmation: approved), rejects);
  });
  test('corrected name retains original; deposits and adjustments need explicit metadata bound to review', () {
    final f = OcrFixture(), r = OcrFixture();
    final original = f.rows.single;
    f.rows = [
      OcrReviewRow(
        original.id,
        const ReviewRowInput('CORRECTED', '2,00', LineKind.product),
        true,
        original.words,
      ),
    ];
    expect(f.save().document.snapshot.items.single.rawName, 'MILK');
    for (final kind in [LineKind.deposit, LineKind.adjustment]) {
      f.rows = [
        OcrReviewRow(
          original.id,
          ReviewRowInput('CORRECTED', '2,00', kind),
          true,
          original.words,
        ),
      ];
      expect(() => f.save(), rejects);
      final details = {
        original.id: kind == LineKind.deposit
            ? const OcrRowDetails(standaloneDeposit: true)
            : const OcrRowDetails(adjustmentReason: 'Printed correction'),
      };
      final approved = f.confirm(details: details);
      expect(
        f
            .save(details: details, confirmation: approved)
            .document
            .snapshot
            .items
            .single
            .kind,
        kind,
      );
      expect(
        () => f.save(
          details: {r.rows.single.id: const OcrRowDetails()},
          confirmation: approved,
        ),
        rejects,
      );
    }
  });
  test('typed discount and quantity decisions survive canonical encoding and reject foreign or inconsistent targets', () {
    final source = parseReceipt(
      OcrPage(500, 500, [
        OcrWord('16.11.2026', PixelBox(10, 10, 150, 26)),
        OcrWord('2 kpl 1,00 EUR/kpl', PixelBox(10, 45, 300, 61)),
        OcrWord('MILK', PixelBox(10, 100, 150, 116)),
        OcrWord('2,00', PixelBox(400, 100, 480, 116)),
        OcrWord('ALENNUS', PixelBox(10, 140, 150, 156)),
        OcrWord('-0,50', PixelBox(400, 140, 480, 156)),
        OcrWord('YHTEENSÄ', PixelBox(10, 220, 200, 236)),
        OcrWord('1,50', PixelBox(400, 220, 480, 236)),
      ]),
      itemTop: 40,
      priceColumnLeft: 350,
    );
    final f = OcrFixture(source: source),
        product = source.rows.indexWhere((r) => r.kind == LineKind.product);
    final r = f.rows[product];
    f.rows[product] = OcrReviewRow(
      r.id,
      ReviewRowInput(
        r.input.name,
        r.input.amount,
        r.input.kind,
        quantity: '2',
        rate: '1',
        unit: QuantityUnit.piece,
      ),
      true,
      r.words,
    );
    final findings = reviewFindingsForDraft(source);
    for (var i = 0; i < findings.length; i++) {
      f.decisions[i] = FindingEvidenceDecision(
        note: 'PRIVATE NOTE',
        compared: true,
        target: r.id,
        relationshipKind: findings[i].issue == ParseIssue.quantityWithoutProduct
            ? ReviewRelationshipKind.quantity
            : ReviewRelationshipKind.productDiscount,
      );
    }
    expect(f.audit().blockers, isEmpty);
    final approved = f.confirm(), saved = f.save(confirmation: approved);
    final roundtrip = ReceiptDocumentCodec.decode(
      ReceiptDocumentCodec.encode(saved.document),
    );
    final discount = roundtrip.snapshot.items.singleWhere(
      (r) => r.kind == LineKind.discount,
    );
    expect(discount.parentItemId, id(3 + product));
    expect(discount.discountScope, DiscountScope.item);
    expect(
      roundtrip.snapshot.items[product].quantityValue,
      BigInt.from(2000000),
    );
    final review = roundtrip.review as OcrReviewRecord;
    expect(review.decisions, hasLength(findings.length));
    final encoded = jsonDecode(
      ReceiptDocumentCodec.encode(saved.document),
    ) as Map<String, dynamic>;
    void invalid(void Function(Map<String, dynamic>) change) {
      final copy = jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;
      change(copy);
      expect(() => ReceiptDocumentCodec.decode(jsonEncode(copy)), rejects);
    }

    invalid(
      (o) =>
          o['review']['ocr_evidence']['decisions'][0]['target_row_id'] = id(80)
              .value,
    );
    invalid(
      (o) =>
          o['review']['ocr_evidence']['decisions'][0]['source_row_id'] = id(80)
              .value,
    );
    invalid(
      (o) =>
          o['review']['ocr_evidence']['decisions'][0]['row_kind'] = 'unknown',
    );
    invalid((o) => o['receipt']['items'].last['parent_item_id'] = null);
    final index = findings.indexWhere(
      (r) => r.discountKind == DiscountFindingKind.postedDiscount,
    );
    f.decisions[index] = const FindingEvidenceDecision(
      note: 'changed scope',
      compared: true,
      relationshipKind: ReviewRelationshipKind.receiptDiscount,
    );
    expect(() => f.save(confirmation: approved), rejects);
  });
  test('removed original rows retain stable identities and typed per-word dispositions', () {
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
    expect(() => f.save(), rejects);
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
        note: 'PRIVATE NOTE',
        compared: true,
        rowKind: RowEvidenceKind.duplicateOcr,
        target: f.rows.single.id,
      );
    }
    final saved = f.save(), review = saved.document.review as OcrReviewRecord;
    expect(review.originalRowIds, [id(3), id(4)]);
    expect(saved.document.snapshot.items.single.id, id(4));
    expect(
      review.decisions.map((d) => d.rowKind),
      everyElement(RowEvidenceKind.duplicateOcr),
    );
    expect(
      ReceiptDocumentCodec.encode(
        ReceiptDocumentCodec.decode(
          ReceiptDocumentCodec.encode(saved.document),
        ),
      ),
      ReceiptDocumentCodec.encode(saved.document),
    );
  });
  test('geometry and nonfinancial explanatory links remain typed without extra financial rows', () {
    final base = OcrFixture().draft.parseContext!.page;
    final source = parseReceipt(
      OcrPage(500, 500, [
        ...base.words,
        OcrWord('NORM. 2,50', PixelBox(10, 130, 300, 146)),
      ], baselineSlope: .01),
      itemTop: 40,
      priceColumnLeft: 350,
    );
    final f = OcrFixture(source: source),
        findings = reviewFindingsForDraft(source);
    for (var i = 0; i < findings.length; i++) {
      f.decisions[i] = findings[i].issue == ParseIssue.skewAdjusted
          ? FindingEvidenceDecision(
              note: 'Compared skew',
              compared: true,
              geometrySnapshot: f.snapshot,
            )
          : FindingEvidenceDecision(
              note: 'Compared price explanation',
              compared: true,
              relationshipKind: ReviewRelationshipKind.explanatoryPrice,
              target: f.rows.single.id,
            );
    }
    expect(f.audit().blockers, isEmpty);
    final saved = f.save(),
        decoded = ReceiptDocumentCodec.decode(
          ReceiptDocumentCodec.encode(saved.document),
        );
    expect(decoded.snapshot.items, hasLength(1));
    expect(decoded.snapshot.totalCents, BigInt.from(200));
    final review = decoded.review as OcrReviewRecord;
    expect(
      review.decisions.any((d) => d.geometryKind == GeometryFindingKind.skew),
      isTrue,
    );
    expect(
      review.decisions.any(
        (d) => d.relationshipKind == ReviewRelationshipKind.explanatoryPrice,
      ),
      isTrue,
    );
  });
  test('unknown policy and malformed OCR metadata cannot be decoded into authorization', () {
    final object = jsonDecode(
      ReceiptDocumentCodec.encode(OcrFixture().save().document),
    ) as Map<String, dynamic>;
    void invalid(void Function(Map<String, dynamic>) mutate) {
      final copy = jsonDecode(jsonEncode(object)) as Map<String, dynamic>;
      mutate(copy);
      expect(() => ReceiptDocumentCodec.decode(jsonEncode(copy)), rejects);
    }

    invalid((o) => o['review']['policy_version'] = '3');
    invalid((o) => o['review']['ocr_evidence']['parser_version'] = 'unknown');
    invalid((o) => o['review']['ocr_evidence']['page_layout_compared'] = false);
    invalid((o) => o['review']['ocr_evidence']['unresolved_count'] = '1');
    invalid((o) => o['review']['ocr_evidence']['reviewed_finding_count'] = '1');
    invalid((o) => o['review']['source'] = 'manual');
    invalid(
      (o) => o['review']['ocr_evidence']['original_row_ids'] = [id(7).value],
    );
    invalid(
      (o) => o['review']['ocr_evidence']['original_row_ids'] = [
        id(3).value,
        id(3).value,
      ],
    );
    invalid((o) => o['review']['ocr_evidence']['notes'] = 'PRIVATE');
    expect(
      ReceiptDocumentCodec.decode(jsonEncode(object)),
      isNot(isA<ReviewedReceipt>()),
    );
  });
}
