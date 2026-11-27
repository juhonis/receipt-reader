import 'geometry.dart';
import 'receipt_date.dart';
import 'receipt_syntax.dart';

/// A possible printed name, never an assertion about a branch's identity.
class ReceiptBranchCandidate {
  ReceiptBranchCandidate(this.name, Iterable<OcrWord> words)
    : words = List.unmodifiable(words);
  final String name;
  final List<OcrWord> words;
}

/// Uses reconstructed header baselines, ending names at explicit tax/phone
/// labels when those share a line. Metadata interrupts multiline
/// names; products, footer text and words crossing the item boundary are excluded
/// by the caller. Evidence retains original spelling and word identities.
List<ReceiptBranchCandidate> receiptBranchCandidates(
  Iterable<List<OcrWord>> header,
) {
  final result = <ReceiptBranchCandidate>[];
  List<OcrWord>? previous;
  for (final baseline in header) {
    final metadata = baseline.indexWhere(
      (w) => _suffixMetadata.hasMatch(w.text),
    );
    final line = metadata < 0 ? baseline : baseline.take(metadata).toList();
    var text = line.map((w) => w.text).join(' ').trim();
    // A comma before an explicit metadata label separates fields, rather than
    // belonging to the branch name. The original word remains in the evidence.
    if (metadata >= 0) text = text.replaceFirst(RegExp(r'[,;:]+$'), '').trim();
    if (!_possibleName(text) ||
        baseline.indexed
            .skip(1)
            .any(
              (entry) => baseline[entry.$1 - 1].box.right > entry.$2.box.left,
            )) {
      previous = null;
      continue;
    }
    result.add(ReceiptBranchCandidate(text, line));
    if (previous != null) {
      final before = previous.first.box, after = line.first.box;
      final height = before.height > after.height
          ? before.height
          : after.height;
      if (after.top - before.bottom <= height * 2 &&
          (after.left - before.left).abs() <= height * 2) {
        final words = [...previous, ...line];
        result.add(
          ReceiptBranchCandidate(
            '${previous.map((w) => w.text).join(' ')} $text'.trim(),
            words,
          ),
        );
      }
    }
    previous = metadata < 0 ? line : null;
  }
  return List.unmodifiable(result);
}

final _suffixMetadata = RegExp(
  r'^(?:Y-?TUNNUS(?::|$)|Y[-:]?\d|(?:PUH(?:ELIN)?|TEL)(?::|$))',
  caseSensitive: false,
);

bool _possibleName(String text) =>
    RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]{3}').hasMatch(text) &&
    !RegExp(
      r'^(?:Y(?:-?TUNNUS)?\s*[:\-]?\s*\d|(?:PUH(?:ELIN)?|TEL|PVM|KLO|KUITTI|KASSA|MYYJÄ|ASIAKAS|TERVETULOA|KIITOS)(?:\s|:|$)|WWW[.]|HTTPS?[:])',
      caseSensitive: false,
    ).hasMatch(text) &&
    !RegExp(r'\d{5}|\d+[,.]\d{2}|[@/%€]').hasMatch(text) &&
    findReceiptDate([text]).sourceText.isEmpty &&
    !receiptHeaderNotice(text) &&
    !receiptFooterLabel(text) &&
    receiptTotalLabel(text) == null;
