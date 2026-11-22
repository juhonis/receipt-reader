import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/receipt_ocr.dart';

import '../packages/receipt_parser/test/fixtures/finnish_receipts.dart';
import '../test/support/render_finnish_receipt.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final fixture in finnishReceiptFixtures.where((f) => f.native)) {
    testWidgets('native Finnish corpus: ${fixture.id}', (t) async {
      final bytes = await renderFinnishReceipt(fixture);
      final original = sha256.convert(bytes);
      final evidence = await ReceiptEvidence.decode(bytes);
      try {
        final page = await recognizeReceipt(evidence);
        final draft = parseReceipt(page, itemTop: 150, priceColumnLeft: 900);
        // Only invented fixture information is logged; never imported receipts.
        debugPrint(
          'SYNTHETIC_CORPUS ${jsonEncode({
            'case': fixture.id,
            'synthetic': true,
            'sourceImageSha256': original.toString(),
            'width': page.width,
            'height': page.height,
            'baselineSlope': page.baselineSlope,
            'backend': Platform.isWindows ? 'tesseract' : 'mlkit',
            'dateState': draft.date.state.name,
            'total': draft.printedTotal?.toString(),
            'rows': [
              for (final row in draft.rows) {'name': row.name, 'cents': row.cents.toString(), 'quantity': row.quantity?.value.toString(), 'rate': row.rateMicros?.toString(), 'unit': row.quantity?.unit.name},
            ],
            'findings': draft.findings.map((f) => f.issue.name).toList(),
            'coverageComplete': draft.evidenceCoverage!.complete,
            'words': [
              for (final w in page.words) [w.text, w.box.left, w.box.top, w.box.right, w.box.bottom],
            ],
          })}',
        );
        expect(draft.date.state, ReceiptDateState.valid);
        expect(draft.printedTotal, BigInt.from(fixture.total!));
        expect(draft.rows.map((r) => (r.name, r.cents, r.kind)), [
          for (final row in fixture.rows)
            (row.name, BigInt.from(row.cents), row.kind),
        ]);
        for (var i = 0; i < fixture.rows.length; i++) {
          final expected = fixture.rows[i], actual = draft.rows[i];
          expect(
            actual.quantity?.value,
            expected.quantityMicros == null
                ? null
                : BigInt.from(expected.quantityMicros!),
          );
          expect(
            actual.rateMicros,
            expected.rateMicros == null
                ? null
                : BigInt.from(expected.rateMicros!),
          );
          expect(actual.quantity?.unit, expected.unit);
          expect(actual.quantityMatches, expected.quantityMatches);
        }
        expect(
          draft.findings.every(
            (f) => fixture.nativeAllowedIssues.contains(f.issue),
          ),
          isTrue,
        );
        for (final finding in draft.findings) {
          expect(finding.issue, ParseIssue.normalizedOcrAmount);
          expect(finding.rowIndex, 0);
          expect(finding.scope, FindingScope.item);
          expect(
            Platform.isWindows
                ? finding.words.any(
                    (w) => RegExp(r'^[–—][0-9]').hasMatch(w.text),
                  )
                : finding.words
                      .map((w) => w.text)
                      .join(' ')
                      .contains('2, 00 €/kg'),
            isTrue,
          );
        }
        final expectedDate = parseReceiptDate(fixture.date).printed!;
        final actualDate = draft.date.printed!;
        expect(
          (actualDate.year, actualDate.month, actualDate.day),
          (expectedDate.year, expectedDate.month, expectedDate.day),
        );
        expect(draft.evidenceCoverage!.complete, isTrue);
        expect(sha256.convert(bytes), original);
      } finally {
        evidence.dispose();
      }
    });
  }
}
