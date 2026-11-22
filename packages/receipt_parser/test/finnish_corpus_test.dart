import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'fixtures/finnish_receipts.dart';

void main() {
  for (final fixture in finnishReceiptFixtures) {
    for (final reverse in [false, true]) {
      test(
        '${fixture.id}: ${reverse ? 'reversed word order' : fixture.purpose}',
        () {
          final source = fixture.page();
          final page = reverse
              ? OcrPage(source.width, source.height, source.words.reversed)
              : source;
          final draft = parseReceipt(page, itemTop: 150, priceColumnLeft: 900);
          expect(draft.rows.map((r) => (r.name, r.cents, r.kind)), [
            for (final row in fixture.rows)
              (row.name, BigInt.from(row.cents), row.kind),
          ]);
          expect(
            draft.printedTotal,
            fixture.total == null ? null : BigInt.from(fixture.total!),
          );
          expect(draft.date.state, fixture.dateState);
          expect(
            draft.findings.map(
              (f) => (f.issue, f.rowIndex, f.scope, f.discountKind),
            ),
            [
              for (final f in fixture.findings)
                (f.issue, f.row, f.scope, f.discount),
            ],
          );
          expect(draft.issues, fixture.findings.map((f) => f.issue).toSet());
          expect(
            draft.wrappedNames.map((w) => w.proposedName),
            fixture.wrapped,
          );
          expect(
            draft.evidenceCoverage!.unassignedWords.map((w) => w.text).toSet(),
            fixture.unassigned.toSet(),
          );
          for (var i = 0; i < fixture.rows.length; i++) {
            final row = draft.rows[i], expected = fixture.rows[i];
            expect(
              row.quantity?.value,
              expected.quantityMicros == null
                  ? null
                  : BigInt.from(expected.quantityMicros!),
            );
            expect(
              row.rateMicros,
              expected.rateMicros == null
                  ? null
                  : BigInt.from(expected.rateMicros!),
            );
            expect(row.quantity?.unit, expected.unit);
            expect(row.quantityMatches, expected.quantityMatches);
            expect(draft.rowEvidence[i], isNotEmpty);
            expect(draft.rowEvidence[i].every(page.words.contains), isTrue);
          }
          final sum = fixture.rows.fold<int>(
            0,
            (value, row) => value + row.cents,
          );
          expect(
            draft.totals.difference,
            fixture.total == null ? null : BigInt.from(sum - fixture.total!),
          );
          final snapshot = OcrReviewSnapshot(
            draft,
            'SYNTHETIC BRANCH',
            fixture.date,
            fixture.total == null
                ? ''
                : formatCents(BigInt.from(fixture.total!)),
            true,
            [
              for (var i = 0; i < draft.rows.length; i++)
                OcrReviewRow(
                  Object(),
                  ReviewRowInput(
                    draft.rows[i].name,
                    formatCents(draft.rows[i].cents),
                    draft.rows[i].kind,
                    quantity: draft.rows[i].quantity == null
                        ? ''
                        : formatFixed(draft.rows[i].quantity!.value, 6),
                    rate: draft.rows[i].rateMicros == null
                        ? ''
                        : formatFixed(draft.rows[i].rateMicros!, 6),
                    unit: draft.rows[i].quantity?.unit ?? QuantityUnit.unknown,
                  ),
                  false,
                  draft.rowEvidence[i],
                ),
            ],
          );
          final audit = OcrEvidenceAudit(
            snapshot: snapshot,
            findings: reviewFindingsForDraft(draft),
            decisions: const {},
            originalRowIds: snapshot.rows.map((r) => r.id).toList(),
            imageMatchesSource: true,
            pageApproval: null,
            policy: OcrReviewPolicy.receipt,
          );
          // Readiness here covers parser evidence, not branch identity, deposit
          // choices, final human approval or persistence authorization.
          final expectedReady =
              fixture.findings.isEmpty &&
              fixture.unassigned.isEmpty &&
              fixture.dateState == ReceiptDateState.valid &&
              fixture.total == sum;
          expect(audit.automaticReady, expectedReady);
          expect(
            audit.ready,
            isFalse,
            reason: 'Automatic checks never approve a receipt',
          );
          final layout = proposeLayout(page);
          expect(layout.available, fixture.layout);
          if (layout.available) {
            final proposed = parseReceipt(
              page,
              itemTop: layout.itemTop!,
              priceColumnLeft: layout.priceColumnLeft!,
            );
            expect(
              proposed.rows.map((r) => (r.name, r.cents, r.kind)),
              draft.rows.map((r) => (r.name, r.cents, r.kind)),
            );
            expect(proposed.printedTotal, draft.printedTotal);
          }
        },
      );
    }
  }
}
