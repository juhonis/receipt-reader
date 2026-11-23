import 'dart:convert';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'ocr_support.dart';

void main() {
  final head = RevisionId(id(70), BigInt.one);
  final link = ReceiptProductLink(id: id(80), storeId: id(2), revision: head);
  ReviewedReceipt select(
    ReceiptDocument base,
    Map<DurableId, ReceiptProductLink?> links,
  ) => ReviewedReceipt.productLinks(
    confirmation: ProductLinkReviewChecks(
      base: base,
      expectedHead: head,
      selections: links,
      mutationId: id(90),
    ).confirm(reviewedAtMs: BigInt.from(456), appVersion: 'link-test'),
  );

  test('only changed links are approved; round trip and original document stay exact', () {
    final base = command(
      receipt(
        items: [
          row(
            cents: BigInt.from(250),
            rawName: 'RAW',
            quantity: BigInt.one,
            scale: 0,
            unit: QuantityUnit.piece,
            rate: BigInt.from(2500000),
          ),
          row(
            number: 4,
            kind: LineKind.discount,
            cents: BigInt.from(-50),
            scope: DiscountScope.item,
            parent: id(3),
          ),
        ],
      ),
    ).document;
    final bytes = ReceiptDocumentCodec.encode(base);
    final selections = {id(3): link};
    final checks = ProductLinkReviewChecks(
      base: base,
      expectedHead: head,
      selections: selections,
      mutationId: id(90),
    );
    selections.clear();
    final saved = ReviewedReceipt.productLinks(
      confirmation: checks.confirm(
        reviewedAtMs: BigInt.from(456),
        appVersion: 'link-test',
      ),
    ).document;
    validateProductLinkRevision(saved, base);
    expect(saved.review, isA<ProductLinkReviewRecord>());
    expect(saved.review.reviewedRowIds, [id(3)]);
    expect(saved.review.source, 'manual');
    expect(saved.snapshot.items.first.product!.id, id(80));
    expect(
      ReceiptDocumentCodec.encode(
        ReceiptDocumentCodec.decode(ReceiptDocumentCodec.encode(saved)),
      ),
      ReceiptDocumentCodec.encode(saved),
    );
    expect(ReceiptDocumentCodec.encode(base), bytes);
    final cleared = select(saved, {id(3): null}).document;
    validateProductLinkRevision(cleared, saved);
    expect(cleared.snapshot.items.first.product, isNull);
  });

  test(
    'OCR link review preserves provenance and original identity evidence',
    () {
      final base = OcrFixture().save().document;
      final next = select(base, {id(3): link}).document;
      validateProductLinkRevision(next, base);
      expect(next.review.source, 'ocr');
      expect(originalReceiptRowIds(next), originalReceiptRowIds(base));
      expect(
        (next.review as ProductLinkReviewRecord).baseDocumentSha256,
        base.sha256Hex,
      );
      expect(
        jsonDecode(
          ReceiptDocumentCodec.encode(next),
        )['review'].containsKey('branch_reviewed'),
        isFalse,
      );
    },
  );

  test('reject empty, unchanged, foreign and nonproduct selections', () {
    final base = command(receipt()).document;
    for (final links in <Map<DurableId, ReceiptProductLink?>>[
      {},
      {id(3): null},
      {id(9): link},
    ]) {
      expect(() => select(base, links), throwsA(isA<ReceiptDataException>()));
    }
    final discount = command(
      receipt(
        items: [
          row(cents: BigInt.from(250)),
          row(
            number: 4,
            cents: BigInt.from(-50),
            kind: LineKind.discount,
            scope: DiscountScope.receipt,
          ),
        ],
      ),
    ).document;
    expect(
      () => select(discount, {id(4): link}),
      throwsA(isA<ReceiptDataException>()),
    );
  });

  for (final field in [
    'name',
    'date',
    'amounts',
    'base',
    'source',
    'evidence',
    'reviewed',
  ]) {
    test('historical link review rejects forged $field', () {
      final base = command(receipt()).document;
      final json = jsonDecode(
        ReceiptDocumentCodec.encode(select(base, {id(3): link}).document),
      ) as Map;
      final r = json['review'] as Map, s = json['receipt'] as Map;
      switch (field) {
        case 'name':
          s['items'][0]['name'] = 'ALTERED';
          s['items'][0]['normalized_name'] = 'altered';
        case 'date':
          s['date']['day'] = '17';
        case 'amounts':
          s['total_cents'] = '300';
          s['items'][0]['cents'] = '300';
        case 'base':
          r['base_document_sha256'] = '0' * 64;
        case 'source':
          r['source'] = 'ocr';
        case 'evidence':
          r['original_row_ids'] = [id(99).value];
        case 'reviewed':
          r['reviewed_product_row_ids'] = <String>[];
      }
      expect(() {
        final forged = ReceiptDocumentCodec.decode(jsonEncode(json));
        validateProductLinkRevision(forged, base);
      }, throwsA(isA<ReceiptDataException>()));
    });
  }
}
