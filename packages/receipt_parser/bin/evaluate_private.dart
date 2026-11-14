/// Explicit local evaluation. Never include these inputs/results in app assets.
import 'dart:convert';
import 'dart:io';

import 'package:receipt_parser/receipt_parser.dart';

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Pass the private OCR directory');
  final root = Directory(args.single).absolute;
  Map<String, dynamic> read(String path) =>
      jsonDecode(File('${root.path}/$path').readAsStringSync())
          as Map<String, dynamic>;
  final hints = read('parser-hints.json');
  final expected = read('expected.json')['samples'] as List<dynamic>;
  final reports = <Map<String, Object?>>[];
  for (final engine in [
    'mlkit',
    'tesseract-psm3',
    'tesseract-psm6',
    'android-tesseract-psm3',
    'android-tesseract-psm6',
  ]) {
    for (final sample in expected) {
      final id = sample['sampleId'] as String;
      final file = File('${root.path}/$engine/$id.json');
      if (!file.existsSync()) continue;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final hint = hints[id] as Map<String, dynamic>;
      if (json['inputSha256'] != hint['inputSha256']) {
        throw StateError('Layout hints belong to a different image');
      }
      final draft = parseReceipt(
        OcrPage.fromJson(json),
        itemTop: (hint['itemTop'] as num).toDouble(),
        priceColumnLeft: (hint['priceColumnLeft'] as num).toDouble(),
      );
      final actualAmounts = draft.rows.map((r) => r.cents.toString()).toList();
      final wantedAmounts = (sample['lineAmountsCents'] as List<dynamic>)
          .map((n) => n.toString())
          .toList();
      final date = draft.date.printed;
      final wantedDate = parseReceiptDate(sample['date'] as String).printed!;
      reports.add({
        'sampleId': id,
        'engine': engine,
        'inputSha256': json['inputSha256'],
        'layoutHints': hint,
        'postedAmountsMatchInOrder':
            jsonEncode(actualAmounts) == jsonEncode(wantedAmounts),
        'printedTotalMatches':
            draft.printedTotal?.toString() == sample['totalCents'].toString(),
        'dateMatches':
            date != null &&
            date.year == wantedDate.year &&
            date.month == wantedDate.month &&
            date.day == wantedDate.day,
        'dateState': draft.date.state.name,
        'reconciliation': draft.totals.state.name,
        'differenceCents': draft.totals.difference?.toString(),
        'issues': draft.issues.map((i) => i.name).toList(),
        'rows': [
          for (final row in draft.rows)
            {
              'name': row.name,
              'cents': row.cents.toString(),
              'kind': row.kind.name,
              'quantityMatches': row.quantityMatches,
            },
        ],
        'notes': draft.notes,
      });
    }
  }
  if (reports.isEmpty) throw StateError('No private baseline outputs found');
  File('${root.path}/parser-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(reports));
  stdout.writeln(
    'Evaluated ${reports.length} private cases; report kept in the input directory.',
  );
}
