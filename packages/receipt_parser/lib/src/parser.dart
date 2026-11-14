import 'finance.dart';
import 'geometry.dart';

enum ParseIssue {
  missingTotal,
  ambiguousTotal,
  unclassifiedRow,
  ambiguousGeometry,
  invalidAmount,
  quantityWithoutProduct,
  quantityMismatch,
  discountNeedsReview,
}

class ReceiptDraft {
  ReceiptDraft(
    Iterable<FinancialRow> rows,
    this.printedTotal,
    Iterable<ParseIssue> issues,
    Iterable<String> notes,
  ) : rows = List.unmodifiable(rows),
      issues = Set.unmodifiable(issues),
      notes = List.unmodifiable(notes);
  final List<FinancialRow> rows;
  final BigInt? printedTotal;
  final Set<ParseIssue> issues;

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
  final ordered = page.words.where((w) => w.box.top >= itemTop).toList()
    ..sort((a, b) {
      final y = a.box.centerY.compareTo(b.box.centerY);
      return y != 0 ? y : a.box.left.compareTo(b.box.left);
    });
  for (final word in ordered) {
    final matches = bands.where((band) {
      final anchor = band.first.box;
      final tolerance =
          (anchor.height < word.box.height ? anchor.height : word.box.height) *
          .45;
      return (anchor.centerY - word.box.centerY).abs() <= tolerance;
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
  String price(List<OcrWord> band) => band
      .where((w) => w.box.left >= priceColumnLeft)
      .map((w) => w.text)
      .join('')
      .trim();
  final totals = bands
      .where((b) => label(b).toUpperCase() == 'YHTEENSÄ')
      .toList();
  // VAT and payment sections are never scanned for purchased items.
  final footer = bands.indexWhere(
    (b) =>
        RegExp(r'^(ALV|VISA|MASTERCARD|KÄTEINEN|MAKSETTU)(?:\s|$)')
            .hasMatch(label(b).toUpperCase()),
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
    total = parseCents(price(candidates.single));
    if (total == null) issues.add(ParseIssue.invalidAmount);
  }
  final end = candidates.isNotEmpty
      ? bands.indexOf(candidates.first)
      : footer >= 0
      ? footer
      : bands.length;
  final rows = <FinancialRow>[];
  final notes = <String>[];
  var canAttachQuantity = false;
  final quantityPattern = RegExp(
    r'^(-?[0-9]+(?:[,.][0-9]+)?)\s+(kg|kpl|l)\s+([0-9]+(?:[,.][0-9]+)?)\s+(?:€|EUR)?/?(kg|kpl|l)$',
    caseSensitive: false,
  );
  for (final band in bands.take(end)) {
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
    final amount = parseCents(amountText);
    if (name.isEmpty || amount == null) {
      notes.add(fullText);
      issues.add(
        amountText.isNotEmpty
            ? ParseIssue.invalidAmount
            : ParseIssue.unclassifiedRow,
      );
      continue;
    }
    final kind = RegExp(r'^PANTTI(?:\s|$)').hasMatch(upper)
        ? LineKind.deposit
        : RegExp(r'^(ALENNUS|ALE)(?:\s|$)').hasMatch(upper)
        ? LineKind.discount
        : LineKind.product;
    if (kind == LineKind.discount && !amount.isNegative) {
      issues.add(ParseIssue.discountNeedsReview);
    }
    rows.add(FinancialRow(name: name, cents: amount, kind: kind));
    canAttachQuantity = kind == LineKind.product;
  }
  return ReceiptDraft(rows, total, issues, notes);
}
