import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

final rejectsData = throwsA(isA<ReceiptDataException>());

void main() {
  test(
    'manual review needs all explicit fields and exactly the current rows',
    () {
      final snapshot = receipt();
      for (final checklist in [
        checks(snapshot, branch: false),
        checks(snapshot, date: false),
        checks(snapshot, total: false),
        checks(snapshot, rows: []),
        checks(snapshot, rows: [id(3), id(99)]),
        checks(snapshot, rows: [id(99)]),
      ]) {
        expect(
          () => checklist.confirm(reviewedAtMs: BigInt.one, appVersion: 'test'),
          rejectsData,
        );
      }
      expect(
        () =>
            checks(snapshot)
                .confirm(reviewedAtMs: -BigInt.one, appVersion: 'test'),
        rejectsData,
      );
      expect(
        () => checks(snapshot).confirm(
          reviewedAtMs: sqliteInt64Max + BigInt.one,
          appVersion: 'test',
        ),
        rejectsData,
      );
      expect(
        () =>
            checks(snapshot).confirm(reviewedAtMs: BigInt.one, appVersion: ' '),
        rejectsData,
      );
      final saved = command(snapshot);
      expect(saved.mutationId, id(4));
      expect(saved.document.review.reviewedRowIds, [id(3)]);
      expect(
        ReceiptDocumentCodec.decode(
          ReceiptDocumentCodec.encode(saved.document),
        ),
        isNot(isA<ReviewedReceipt>()),
      );
      expect(
        () => saved.document.review.reviewedRowIds.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('edits invalidate confirmation even while totals still match', () {
    final snapshot = receipt();
    final confirmation = confirm(snapshot);
    final changed = [
      receipt(items: [row(name: 'Different product')]),
      receipt(items: [row(number: 9)]),
      receipt(number: 9),
      receipt(date: '17.11.2026'),
      receipt(
        branch: ReceiptBranch(id: id(9), name: 'TEST BRANCH'),
      ),
      receipt(
        branch: ReceiptBranch(id: id(2), name: 'Other branch'),
      ),
      receipt(
        branch: ReceiptBranch(
          id: id(2),
          name: 'TEST BRANCH',
          revision: RevisionId(id(8), BigInt.one),
        ),
      ),
      receipt(
        items: [row(cents: BigInt.from(300))],
        total: BigInt.from(300),
      ),
      receipt(items: [row(rawName: 'Original source name')]),
      receipt(
        items: [
          row(
            quantity: BigInt.two,
            scale: 0,
            unit: QuantityUnit.piece,
            rate: BigInt.from(1000000),
          ),
        ],
      ),
      receipt(
        items: [
          row(
            product: ReceiptProductLink(
              id: id(6),
              storeId: id(2),
              revision: RevisionId(id(8), BigInt.one),
            ),
          ),
        ],
      ),
      receipt(items: [row(kind: LineKind.deposit)]),
    ];
    for (final current in changed) {
      expect(
        () => ReviewedReceipt.manual(
          current: current,
          expectedHeads: [],
          confirmation: confirmation,
        ),
        rejectsData,
      );
    }
    // Equal immutable values may be reconstructed without invalidating review.
    expect(
      ReviewedReceipt.manual(
        current: receipt(),
        expectedHeads: [],
        confirmation: confirmation,
      ).document.sha256Hex,
      command(snapshot).document.sha256Hex,
    );
  });

  test('row order and parent targets are part of the approval', () {
    final a = row(), b = row(number: 5);
    final discount = row(
      number: 6,
      kind: LineKind.discount,
      cents: BigInt.from(-50),
      scope: DiscountScope.item,
      parent: a.id,
    );
    final snapshot = receipt(items: [a, b, discount], total: BigInt.from(350));
    final confirmation = confirm(snapshot);
    for (final current in [
      receipt(items: [b, a, discount], total: snapshot.totalCents),
      receipt(
        items: [
          a,
          b,
          row(
            number: 6,
            kind: LineKind.discount,
            cents: BigInt.from(-50),
            scope: DiscountScope.item,
            parent: b.id,
          ),
        ],
        total: snapshot.totalCents,
      ),
    ]) {
      expect(
        () => ReviewedReceipt.manual(
          current: current,
          expectedHeads: [],
          confirmation: confirmation,
        ),
        rejectsData,
      );
    }
  });

  test('expected heads are immutable sets; changing bases requires review', () {
    final snapshot = receipt();
    final first = RevisionId(id(8), BigInt.one),
        second = RevisionId(id(9), BigInt.two);
    final heads = [second, first];
    final rows = {id(3)};
    final checklist = checks(snapshot, heads: heads, rows: rows);
    heads.clear();
    rows.clear();
    final confirmation = checklist.confirm(
      reviewedAtMs: BigInt.one,
      appVersion: 'test',
    );
    final reviewed = ReviewedReceipt.manual(
      current: snapshot,
      expectedHeads: [first, second],
      confirmation: confirmation,
    );
    expect(reviewed.document.review.expectedHeads, [first, second]);
    expect(
      () => reviewed.document.review.expectedHeads.clear(),
      throwsUnsupportedError,
    );
    for (final changed in <List<RevisionId>>[
      [],
      [first],
      [first, RevisionId(id(9), BigInt.from(3))],
    ]) {
      expect(
        () => ReviewedReceipt.manual(
          current: snapshot,
          expectedHeads: changed,
          confirmation: confirmation,
        ),
        rejectsData,
      );
    }
    expect(() => checks(snapshot, heads: [first, first]), rejectsData);
    expect(() => checklist.reviewedRowIds.clear(), throwsUnsupportedError);
  });
}
