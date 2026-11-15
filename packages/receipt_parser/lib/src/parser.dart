import 'finance.dart';
import 'geometry.dart';
import 'receipt_date.dart';

enum ParseIssue {
  missingTotal,
  ambiguousTotal,
  unclassifiedRow,
  ambiguousGeometry,
  invalidAmount,
  quantityWithoutProduct,
  quantityMismatch,
  discountNeedsReview,
  wrappedNameNeedsReview,
  skewAdjusted,
  totalLabelNeedsReview,
  normalizedOcrAmount,
}

class WrappedNameCandidate {
  const WrappedNameCandidate(this.rowIndex, this.proposedName);
  final int rowIndex;
  final String proposedName;
}

class ReceiptDraft {
  ReceiptDraft(
    Iterable<FinancialRow> rows,
    this.printedTotal,
    Iterable<ParseIssue> issues,
    Iterable<String> notes,
    this.date,
    Iterable<WrappedNameCandidate> wrappedNames, {
    Iterable<Iterable<OcrWord>> rowEvidence = const [],
  }) : rowEvidence = List.unmodifiable(
         rowEvidence.map((words) => List<OcrWord>.unmodifiable(words)),
       ),
       rows = List.unmodifiable(rows),
       issues = Set.unmodifiable(issues),
       notes = List.unmodifiable(notes),
       wrappedNames = List.unmodifiable(wrappedNames);
  final List<FinancialRow> rows;

  /// Original words associated with each row, including attached quantity lines
  /// and proposed wrapped descriptions. Empty for manually constructed drafts.
  final List<List<OcrWord>> rowEvidence;
  final BigInt? printedTotal;
  final Set<ParseIssue> issues;
  final ReceiptDateResult date;
  final List<WrappedNameCandidate> wrappedNames;

  /// Explanatory discount text is not a second financial contribution.
  final List<String> notes;
  Reconciliation get totals => Reconciliation(rows, printedTotal);
  bool get requiresReview => true;
}

/// Initial S-style single-column parser. Caller supplies the item section top
/// and price-column left edge in this page's pixel coordinates. These are
/// explicit layout hints, not inferred branch/date recognition.
ReceiptDraft parseReceipt(
  OcrPage page, {
  required double itemTop,
  required double priceColumnLeft,
}) {
  if (!itemTop.isFinite ||
      !priceColumnLeft.isFinite ||
      itemTop < 0 ||
      itemTop >= page.height ||
      priceColumnLeft <= 0 ||
      priceColumnLeft >= page.width) {
    throw ArgumentError('Layout hints outside page');
  }
  final issues = <ParseIssue>{};
  if (page.baselineSlope.abs() > .005) issues.add(ParseIssue.skewAdjusted);
  if (page.words.any(
    (w) =>
        (w.box.top < itemTop && w.box.bottom > itemTop) ||
        (w.box.top >= itemTop &&
            w.box.left < priceColumnLeft &&
            w.box.right > priceColumnLeft),
  )) {
    issues.add(ParseIssue.ambiguousGeometry);
  }
  final bands = <List<OcrWord>>[];
  final ordered = page.words.toList()
    ..sort((a, b) {
      final y = page.baselineY(a).compareTo(page.baselineY(b));
      return y != 0 ? y : a.box.left.compareTo(b.box.left);
    });
  for (final word in ordered) {
    final matches = bands.where((band) {
      final anchor = band.first.box;
      final tolerance =
          (anchor.height < word.box.height ? anchor.height : word.box.height) *
          .45;
      return (page.baselineY(band.first) - page.baselineY(word)).abs() <=
          tolerance;
    }).toList();
    if (matches.length > 1) issues.add(ParseIssue.ambiguousGeometry);
    if (matches.isEmpty) {
      bands.add([word]);
    } else {
      matches.first.add(word);
    }
  }
  for (final band in bands) {
    band.sort((a, b) => a.box.left.compareTo(b.box.left));
    for (var i = 1; i < band.length; i++) {
      if (band[i].box.left < band[i - 1].box.right)
        issues.add(ParseIssue.ambiguousGeometry);
    }
  }
  String label(List<OcrWord> band) => band
      .where((w) => w.box.left < priceColumnLeft)
      .map((w) => w.text)
      .join(' ')
      .trim();
  String price(List<OcrWord> band) {
    final tokens = band.where((w) => w.box.left >= priceColumnLeft).toList();
    for (var i = 1; i < tokens.length; i++) {
      if (tokens[i].box.left - tokens[i - 1].box.right > tokens[i].box.height ||
          (RegExp(r'[0-9]$').hasMatch(tokens[i - 1].text.trim()) &&
              RegExp(r'^[0-9]').hasMatch(tokens[i].text.trim()))) {
        return tokens
            .map((w) => w.text)
            .join(' | '); // Never fuse separate amounts.
      }
    }
    return tokens.map((w) => w.text).join('').trim();
  }

  BigInt? amount(String text) {
    final strict = parseCents(text);
    if (strict != null) return strict;
    // Only whitespace directly beside a decimal separator is recoverable.
    final normalized = text
        .replaceAll(RegExp(r'(?<=[,.])\s+(?=[0-9])'), '')
        .replaceAll(RegExp(r'(?<=[0-9])\s+(?=[,.])'), '');
    final parsed = parseCents(normalized);
    if (parsed != null) issues.add(ParseIssue.normalizedOcrAmount);
    return parsed;
  }

  final date = findReceiptDate(
    bands
        .where((b) => b.every((w) => w.box.bottom <= itemTop))
        .map((b) => b.map((w) => w.text).join(' ')),
  );
  bands.removeWhere((b) => b.any((w) => w.box.top < itemTop));
  final totals = bands
      .where(
        (b) => RegExp(r'^YHTEENS[ÄAĂÀÁÂÃÅ]$').hasMatch(label(b).toUpperCase()),
      )
      .toList();
  // VAT and payment sections are never scanned for purchased items.
  final footer = bands.indexWhere(
    (b) => RegExp(
      r'^(ALV|VEROTON|VISA|MASTERCARD|KÄTEINEN|MAKSETTU|PANKKIKORTTI|VAIHTORAHA|BONUSTA|JÄSENNUMERO|TID)(?:\s|:|$)',
    ).hasMatch(label(b).toUpperCase()),
  );
  final candidates = totals
      .where((b) => footer < 0 || bands.indexOf(b) < footer)
      .toList();
  BigInt? total;
  if (candidates.isEmpty) {
    issues.add(ParseIssue.missingTotal);
  } else if (candidates.length > 1) {
    issues.add(ParseIssue.ambiguousTotal);
  } else {
    total = amount(price(candidates.single));
    if (label(candidates.single).toUpperCase() != 'YHTEENSÄ') {
      issues.add(ParseIssue.totalLabelNeedsReview);
    }
    if (total == null) issues.add(ParseIssue.invalidAmount);
  }
  final end = candidates.isNotEmpty
      ? bands.indexOf(candidates.first)
      : footer >= 0
      ? footer
      : bands.length;
  final rows = <FinancialRow>[];
  final rowEvidence = <List<OcrWord>>[];
  final notes = <String>[];
  final wrappedNames = <WrappedNameCandidate>[];
  List<OcrWord>? pendingDescription;
  var canAttachQuantity = false;
  final quantityPattern = RegExp(
    r'^(-?[0-9]+(?:[,.][0-9]+)?)\s+(kg|kpl|l)\s+([0-9]+(?:[,.][0-9]+)?)\s+(?:€|EUR)?/?(kg|kpl|l)$',
    caseSensitive: false,
  );
  for (final band in bands.take(end)) {
    final preceding = pendingDescription;
    pendingDescription = null;
    final name = label(band);
    final upper = name.toUpperCase();
    final amountText = price(band);
    final fullText = band.map((w) => w.text).join(' ');
    final quantity = quantityPattern.firstMatch(fullText);
    if (quantity != null) {
      final value = parseFixed(quantity[1]!, 6);
      final rate = parseFixed(quantity[3]!, 6);
      if (!canAttachQuantity ||
          rows.isEmpty ||
          value == null ||
          rate == null ||
          quantity[2]!.toLowerCase() != quantity[4]!.toLowerCase()) {
        issues.add(ParseIssue.quantityWithoutProduct);
        notes.add(fullText);
      } else {
        final unit = switch (quantity[2]!.toLowerCase()) {
          'kg' => QuantityUnit.kg,
          'kpl' => QuantityUnit.piece,
          'l' => QuantityUnit.litre,
          _ => QuantityUnit.unknown,
        };
        rows[rows.length - 1] = rows.last.withQuantity(
          Quantity(value, 6, unit),
          rate,
        );
        rowEvidence.last.addAll(band);
        if (rows.last.quantityMatches == false)
          issues.add(ParseIssue.quantityMismatch);
      }
      canAttachQuantity = false;
      continue;
    }
    canAttachQuantity = false;
    if (RegExp(r'^(NORM\.?|NORMAALIHINTA|KAMPANJA)(?:\s|$)').hasMatch(upper)) {
      notes.add(fullText);
      issues.add(ParseIssue.discountNeedsReview);
      continue;
    }
    final cents = amount(amountText);
    if (name.isEmpty || cents == null) {
      notes.add(fullText);
      issues.add(
        amountText.isNotEmpty
            ? ParseIssue.invalidAmount
            : ParseIssue.unclassifiedRow,
      );
      // Only propose a single adjacent description line. Keep the original
      // row and note unchanged; missing prices can masquerade as wrapping.
      if (name.isNotEmpty &&
          amountText.isEmpty &&
          !RegExp(r'[0-9€/=]').hasMatch(name))
        pendingDescription = band;
      continue;
    }
    final kind = RegExp(r'^PANTTI(?:\s|$)').hasMatch(upper)
        ? LineKind.deposit
        : RegExp(r'^(ALENNUS|ALE)(?:\s|$)').hasMatch(upper)
        ? LineKind.discount
        : LineKind.product;
    if (kind == LineKind.discount && !cents.isNegative) {
      issues.add(ParseIssue.discountNeedsReview);
    }
    rows.add(FinancialRow(name: name, cents: cents, kind: kind));
    rowEvidence.add(List.of(band));
    if (preceding != null &&
        kind == LineKind.product &&
        (preceding.first.box.left - band.first.box.left).abs() <=
            band.first.box.height &&
        band.first.box.top - preceding.first.box.bottom <=
            1.5 * band.first.box.height) {
      wrappedNames.add(
        WrappedNameCandidate(rows.length - 1, '${label(preceding)} $name'),
      );
      rowEvidence.last.insertAll(0, preceding);
      issues.add(ParseIssue.wrappedNameNeedsReview);
    }
    canAttachQuantity = kind == LineKind.product;
  }
  return ReceiptDraft(
    rows,
    total,
    issues,
    notes,
    date,
    wrappedNames,
    rowEvidence: rowEvidence,
  );
}
