import 'finance.dart';
import 'geometry.dart';
import 'receipt_date.dart';

enum LayoutIssue {
  missingHeaderDate,
  missingTotal,
  ambiguousTotal,
  insufficientRows,
  ambiguousColumn,
}

class LayoutProposal {
  LayoutProposal(
    this.itemTop,
    this.priceColumnLeft,
    Iterable<LayoutIssue> issues,
  ) : issues = Set.unmodifiable(issues);
  final double? itemTop, priceColumnLeft;
  final Set<LayoutIssue> issues;
  bool get available =>
      itemTop != null && priceColumnLeft != null && issues.isEmpty;
  bool get requiresReview => true;
}

/// Conservative single-column proposal. Never chooses boundaries by arithmetic.
/// Requires a header date, one pre-footer total and two aligned posted amounts.
LayoutProposal proposeLayout(OcrPage page) {
  LayoutProposal fail(LayoutIssue issue) => LayoutProposal(null, null, [issue]);
  bool sameLine(OcrWord a, OcrWord b) =>
      (page.baselineY(a) - page.baselineY(b)).abs() <=
      (a.box.height < b.box.height ? a.box.height : b.box.height) * .45;
  BigInt? money(OcrWord w) => parseCents(
    w.text
        .trim()
        .replaceAll(RegExp(r'(?<=[,.])\s+(?=[0-9])'), '')
        .replaceAll(RegExp(r'(?<=[0-9])\s+(?=[,.])'), ''),
  );
  final footers = page.words
      .where(
        (w) => RegExp(
          r'^(BONUSTA|JÄSENNUMERO|TID|VISA|MASTERCARD|ALV|VEROTON)(?:\s|:|$)',
        ).hasMatch(w.text.toUpperCase()),
      )
      .toList();
  final footerY = footers.isEmpty
      ? double.infinity
      : footers.map(page.baselineY).reduce((a, b) => a < b ? a : b);
  final totals = page.words
      .where(
        (w) =>
            RegExp(r'^YHTEENS[ÄAĂÀÁÂÃÅ]$')
                .hasMatch(w.text.trim().toUpperCase()) &&
            page.baselineY(w) < footerY,
      )
      .toList();
  if (totals.isEmpty) return fail(LayoutIssue.missingTotal);
  if (totals.length != 1) return fail(LayoutIssue.ambiguousTotal);
  final label = totals.single;
  final totalAmounts = page.words
      .where(
        (w) =>
            w.box.left > label.box.right &&
            sameLine(label, w) &&
            money(w) != null,
      )
      .toList();
  if (totalAmounts.length != 1) return fail(LayoutIssue.ambiguousTotal);
  final totalAmount = totalAmounts.single;
  if (page.words.any(
    (w) =>
        w != label &&
        w != totalAmount &&
        sameLine(label, w) &&
        w.box.left < totalAmount.box.left,
  )) {
    return fail(LayoutIssue.ambiguousTotal);
  }
  final headerWords =
      page.words
          .where((w) => page.baselineY(w) < page.baselineY(label))
          .toList()
        ..sort((a, b) => page.baselineY(a).compareTo(page.baselineY(b)));
  final headerLines = <List<OcrWord>>[];
  for (final word in headerWords) {
    final matching = headerLines
        .where((line) => sameLine(line.first, word))
        .toList();
    if (matching.length > 1) return fail(LayoutIssue.ambiguousColumn);
    if (matching.isEmpty) {
      headerLines.add([word]);
    } else {
      matching.single.add(word);
    }
  }
  for (final line in headerLines) {
    line.sort((a, b) => a.box.left.compareTo(b.box.left));
  }
  final dates = headerLines
      .where(
        (line) =>
            findReceiptDate([line.map((w) => w.text).join(' ')]).printed !=
            null,
      )
      .toList();
  if (dates.length != 1) return fail(LayoutIssue.missingHeaderDate);
  final date = dates.single.first;
  final tolerance = totalAmount.box.height;
  final candidates =
      page.words
          .where(
            (w) =>
                page.baselineY(w) > page.baselineY(date) &&
                page.baselineY(w) < page.baselineY(label) &&
                money(w) != null &&
                (w.box.right - totalAmount.box.right).abs() <= tolerance,
          )
          .toList()
        ..sort((a, b) => page.baselineY(a).compareTo(page.baselineY(b)));
  if (candidates.length < 2) return fail(LayoutIssue.insufficientRows);
  for (var i = 1; i < candidates.length; i++) {
    if (sameLine(candidates[i - 1], candidates[i]))
      return fail(LayoutIssue.ambiguousColumn);
  }
  final left = [
    ...candidates,
    totalAmount,
  ].map((w) => w.box.left).reduce((a, b) => a < b ? a : b);
  final boundary = left - tolerance * .25;
  final firstLine = page.words
      .where((w) => sameLine(w, candidates.first))
      .toList();
  if (boundary <= 0 ||
      !firstLine.any(
        (w) =>
            w.box.right < boundary &&
            RegExp(r'[A-Za-zÄÖÅäöå]').hasMatch(w.text),
      ))
    return fail(LayoutIssue.ambiguousColumn);
  // An additional decimal column may be unit prices or another receipt. Do not
  // silently decide its meaning, even if one interpretation reconciles.
  if (page.words.any(
    (w) =>
        money(w) != null &&
        w.box.right < boundary &&
        candidates.any((p) => sameLine(p, w)),
  ))
    return fail(LayoutIssue.ambiguousColumn);
  // Preserve unpriced lines before the first recognized price for review.
  final top =
      page.words
          .where((w) => sameLine(w, date))
          .map((w) => w.box.bottom)
          .reduce((a, b) => a > b ? a : b) +
      1;
  if (firstLine.any((w) => w.box.top <= top))
    return fail(LayoutIssue.ambiguousColumn);
  return LayoutProposal(top, boundary, []);
}
