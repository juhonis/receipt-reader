import 'finance.dart';
import 'geometry.dart';
import 'receipt_syntax.dart';

/// Join one left-to-right monetary field without fusing separate digit runs.
/// Callers retain the original words for evidence and report text normalization.
String? joinAmountWords(List<OcrWord> words) {
  for (var i = 1; i < words.length; i++) {
    final previous = words[i - 1], current = words[i];
    final currency = i == words.length - 1 && euroCurrencyMarker(current.text);
    final height = previous.box.height < current.box.height
        ? previous.box.height
        : current.box.height;
    if ((!currency && current.box.left - previous.box.right > height) ||
        (RegExp(r'[0-9]$').hasMatch(previous.text.trim()) &&
            RegExp(r'^[0-9]').hasMatch(current.text.trim()))) {
      return null;
    }
  }
  return words.map((w) => w.text).join('').trim();
}

/// Amount candidates on one projected text baseline. Grouping is geometry-only;
/// values never determine which column or receipt layout should be selected.
/// Returned boxes cover the numeric tokens, excluding a separate currency suffix.
/// These temporary words are for layout only; source words remain untouched.
List<OcrWord> amountCandidates(List<OcrWord> line) {
  final ordered = line.toList()
    ..sort((a, b) => a.box.left.compareTo(b.box.left));
  bool numeric(OcrWord w) =>
      RegExp(r'^[-\u2212\u2013\u2014]$').hasMatch(w.text.trim()) ||
      RegExp(
        r'^[-\u2212\u2013\u2014]?[0-9.,\s]+(?:€|EUR)?$',
        caseSensitive: false,
      ).hasMatch(w.text.trim());
  final result = <OcrWord>[];
  for (var i = 0; i < ordered.length; i++) {
    if (!numeric(ordered[i])) continue;
    final group = <OcrWord>[ordered[i]];
    while (i + 1 < ordered.length) {
      final next = ordered[i + 1], last = group.last;
      final currency = euroCurrencyMarker(next.text);
      final height = last.box.height < next.box.height
          ? last.box.height
          : next.box.height;
      if (!currency &&
          (!numeric(next) || next.box.left - last.box.right > height)) {
        break;
      }
      group.add(next);
      i++;
      if (currency) break;
    }
    final literal = joinAmountWords(group);
    if (literal == null ||
        parseCents(normalizedOcrAmountLiteral(literal)) == null) {
      continue;
    }
    final numericWords = group.where((w) => !euroCurrencyMarker(w.text));
    result.add(
      OcrWord(
        literal,
        PixelBox(
          numericWords.map((w) => w.box.left).reduce((a, b) => a < b ? a : b),
          numericWords.map((w) => w.box.top).reduce((a, b) => a < b ? a : b),
          numericWords.map((w) => w.box.right).reduce((a, b) => a > b ? a : b),
          numericWords.map((w) => w.box.bottom).reduce((a, b) => a > b ? a : b),
        ),
      ),
    );
  }
  return result;
}
