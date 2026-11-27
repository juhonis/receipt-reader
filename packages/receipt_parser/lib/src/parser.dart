import 'finance.dart';
import 'amount_geometry.dart';
import 'geometry.dart';
import 'receipt_date.dart';
import 'receipt_branch.dart';
import 'receipt_syntax.dart';

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
  unassignedSource,
  geometrySource,
  removedSource,
}

class WrappedNameCandidate {
  const WrappedNameCandidate(this.rowIndex, this.proposedName);
  final int rowIndex;
  final String proposedName;
}

enum DiscountFindingKind { explanatoryPrice, postedDiscount }

class QuantityRateCandidate {
  const QuantityRateCandidate(this.quantity, this.rateMicros);
  final Quantity quantity;
  final BigInt rateMicros;
}

enum FindingScope { receipt, item, total }

enum GeometryFindingKind {
  sectionBoundary,
  priceBoundary,
  ambiguousBand,
  wordOverlap,
  skew,
}

class ReceiptParseContext {
  const ReceiptParseContext(this.page, this.itemTop, this.priceColumnLeft);
  final OcrPage page;
  final double itemTop, priceColumnLeft;
}

/// Structural source coverage, not proof that text was read or classified
/// correctly. Word identities are preserved, including identical OCR strings.
class ReceiptEvidenceCoverage {
  ReceiptEvidenceCoverage({
    required Iterable<OcrWord> sourceWords,
    required Iterable<OcrWord> header,
    required Iterable<OcrWord> rows,
    required Iterable<OcrWord> findings,
    required Iterable<OcrWord> totals,
    required Iterable<OcrWord> footer,
  }) : sourceWords = List.unmodifiable(sourceWords) {
    final assigned = {...header, ...rows, ...findings, ...totals, ...footer};
    unassignedWords = List.unmodifiable(
      this.sourceWords.where((w) => !assigned.contains(w)),
    );
  }
  final List<OcrWord> sourceWords;
  late final List<OcrWord> unassignedWords;
  bool get complete => unassignedWords.isEmpty;
}

/// One occurrence, rather than a deduplicated category. Indices refer to the
/// immutable draft rows, never the current position in an edited row list.
class ParseFinding {
  ParseFinding(
    this.issue, {
    this.rowIndex,
    Iterable<OcrWord> words = const [],
    this.quantityCandidate,
    this.discountKind,
    this.scope = FindingScope.receipt,
    this.geometryKind,
  }) : words = List.unmodifiable(words);
  final ParseIssue issue;
  final int? rowIndex;
  final List<OcrWord> words;
  final QuantityRateCandidate? quantityCandidate;
  final DiscountFindingKind? discountKind;
  final FindingScope scope;
  final GeometryFindingKind? geometryKind;
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
    Iterable<ParseFinding> findings = const [],
    this.evidenceCoverage,
    this.parseContext,
    Iterable<ReceiptBranchCandidate> branchCandidates = const [],
  }) : rowEvidence = List.unmodifiable(
         rowEvidence.map((words) => List<OcrWord>.unmodifiable(words)),
       ),
       rows = List.unmodifiable(rows),
       issues = Set.unmodifiable(issues),
       notes = List.unmodifiable(notes),
       wrappedNames = List.unmodifiable(wrappedNames),
       findings = List.unmodifiable(findings),
       branchCandidates = List.unmodifiable(branchCandidates);
  final List<ReceiptBranchCandidate> branchCandidates;
  final List<ParseFinding> findings;
  final ReceiptEvidenceCoverage? evidenceCoverage;
  final ReceiptParseContext? parseContext;
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
  final findings = <ParseFinding>[];
  Iterable<OcrWord> activeWords = const [];
  int? activeRow;
  var activeScope = FindingScope.receipt;
  void report(
    ParseIssue issue, {
    QuantityRateCandidate? quantityCandidate,
    DiscountFindingKind? discountKind,
    GeometryFindingKind? geometryKind,
  }) {
    issues.add(issue);
    findings.add(
      ParseFinding(
        issue,
        rowIndex: activeRow,
        words: activeWords,
        quantityCandidate: quantityCandidate,
        discountKind: discountKind,
        scope: activeScope,
        geometryKind: geometryKind,
      ),
    );
  }

  if (page.baselineSlope.abs() > .005) {
    activeWords = page.words;
    report(ParseIssue.skewAdjusted, geometryKind: GeometryFindingKind.skew);
  }
  for (final kind in [
    GeometryFindingKind.sectionBoundary,
    GeometryFindingKind.priceBoundary,
  ]) {
    final words = page.words
        .where(
          (w) => kind == GeometryFindingKind.sectionBoundary
              ? w.box.top < itemTop && w.box.bottom > itemTop
              : w.box.top >= itemTop &&
                    w.box.left < priceColumnLeft &&
                    w.box.right > priceColumnLeft,
        )
        .toList();
    if (words.isNotEmpty) {
      activeWords = words;
      report(ParseIssue.ambiguousGeometry, geometryKind: kind);
    }
  }
  final bands = <List<OcrWord>>[];
  final ordered = page.words.toList()
    ..sort((a, b) {
      final y = page.baselineY(a).compareTo(page.baselineY(b));
      return y != 0 ? y : a.box.left.compareTo(b.box.left);
    });
  for (final word in ordered) {
    activeWords = [word];
    final matches = bands.where((band) {
      final anchor = band.first.box;
      final tolerance =
          (anchor.height < word.box.height ? anchor.height : word.box.height) *
          .45;
      return (page.baselineY(band.first) - page.baselineY(word)).abs() <=
          tolerance;
    }).toList();
    if (matches.length > 1) {
      activeWords = [word, ...matches.expand((band) => band)];
      report(
        ParseIssue.ambiguousGeometry,
        geometryKind: GeometryFindingKind.ambiguousBand,
      );
    }
    if (matches.isEmpty) {
      bands.add([word]);
    } else {
      matches.first.add(word);
    }
  }
  for (final band in bands) {
    activeWords = band;
    band.sort((a, b) => a.box.left.compareTo(b.box.left));
    for (var i = 1; i < band.length; i++) {
      if (band[i].box.left < band[i - 1].box.right)
        report(
          ParseIssue.ambiguousGeometry,
          geometryKind: GeometryFindingKind.wordOverlap,
        );
    }
  }
  String label(List<OcrWord> band) => band
      .where((w) => w.box.left < priceColumnLeft)
      .map((w) => w.text)
      .join(' ')
      .trim();
  String price(List<OcrWord> band) {
    final tokens = band.where((w) => w.box.left >= priceColumnLeft).toList();
    return joinAmountWords(tokens) ?? tokens.map((w) => w.text).join(' | ');
  }

  BigInt? amount(String text) {
    text = amountWithoutCurrency(text);
    final strict = parseCents(text);
    if (strict != null) return strict;
    // Only decimal-adjacent whitespace and a leading OCR dash are recovered.
    // The printed value is proposed with an explicit review finding.
    final normalized = normalizedOcrAmountLiteral(text);
    final parsed = parseCents(normalized);
    if (parsed != null) report(ParseIssue.normalizedOcrAmount);
    return parsed;
  }

  final date = findReceiptDate(
    bands
        .where((b) => b.every((w) => w.box.bottom <= itemTop))
        .map((b) => b.map((w) => w.text).join(' ')),
  );
  final branchCandidates = receiptBranchCandidates(
    bands.where((b) => b.every((w) => w.box.bottom <= itemTop)),
  );
  bands.removeWhere((b) => b.any((w) => w.box.top < itemTop));
  final totals = bands
      .where((b) => receiptTotalLabel(label(b)) != null)
      .toList();
  // VAT and payment sections are never scanned for purchased items.
  final footer = bands.indexWhere((b) => receiptFooterLabel(label(b)));
  final candidates = totals
      .where((b) => footer < 0 || bands.indexOf(b) < footer)
      .toList();
  // Only an uninterrupted prefix of exact, unpriced boilerplate is header
  // evidence. Unknown descriptions or a posted amount end that prefix; they
  // may be an unpriced product and must not disappear into header metadata.
  final headerNotices = <List<OcrWord>>{};
  if (date.printed != null) {
    for (final band in bands) {
      if (!receiptHeaderNotice(band.map((w) => w.text).join(' '))) break;
      headerNotices.add(band);
    }
  }
  activeWords = candidates.expand((band) => band);
  activeScope = FindingScope.total;
  BigInt? total;
  if (candidates.isEmpty) {
    report(ParseIssue.missingTotal);
  } else if (candidates.length > 1) {
    report(ParseIssue.ambiguousTotal);
  } else {
    total = amount(price(candidates.single));
    if (receiptTotalLabel(label(candidates.single)) != 'YHTEENSÄ') {
      report(ParseIssue.totalLabelNeedsReview);
    }
    if (total == null) report(ParseIssue.invalidAmount);
  }
  // Finalize geometry only after identifying non-financial evidence. A unique
  // readable pre-footer total anchors footer exclusion. Unknown post-total text
  // stays uncovered; absent/ambiguous totals retain conservative geometry checks.
  final totalBottom = total == null
      ? null
      : candidates.single
            .map((word) => page.baselineY(word) + word.box.height / 2)
            .reduce((a, b) => a > b ? a : b);
  final nonFinancial = <OcrWord>{
    ...headerNotices.expand((band) => band),
    if (footer >= 0 && totalBottom != null)
      ...bands
          .skip(footer)
          .expand((band) => band)
          .where(
            (word) => page.baselineY(word) - word.box.height / 2 > totalBottom,
          ),
  };
  findings.removeWhere(
    (finding) =>
        finding.issue == ParseIssue.ambiguousGeometry &&
        finding.geometryKind != GeometryFindingKind.sectionBoundary &&
        finding.words.isNotEmpty &&
        finding.words.every(nonFinancial.contains),
  );
  issues
    ..clear()
    ..addAll(findings.map((finding) => finding.issue));
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
    r'^([-\u2212]?[0-9]+(?:[,.][0-9]+)?)\s+(kg|kpl|l)\s+(?:[x×]\s*)?([0-9]+(?:[,.][0-9]+)?)\s+(?:€|EUR)?/?(kg|kpl|l)$',
    caseSensitive: false,
  );
  for (final band in bands.take(end)) {
    if (headerNotices.contains(band)) continue;
    activeWords = band;
    activeScope = FindingScope.item;
    activeRow = null;
    final preceding = pendingDescription;
    pendingDescription = null;
    final name = label(band);
    final upper = name.toUpperCase();
    final amountText = price(band);
    final fullText = band.map((w) => w.text).join(' ');
    // Recover decimal-adjacent OCR whitespace only within the complete quantity
    // grammar. Distant fragments and separate digit runs must remain unparsed.
    final closeDecimalFragments = !List.generate(band.length - 1, (i) => i).any(
      (i) =>
          ((RegExp(r'[,.]$').hasMatch(band[i].text.trim()) &&
                  RegExp(r'^[0-9]').hasMatch(band[i + 1].text.trim())) ||
              (RegExp(r'[0-9]$').hasMatch(band[i].text.trim()) &&
                  RegExp(r'^[,.]').hasMatch(band[i + 1].text.trim()))) &&
          band[i + 1].box.left - band[i].box.right >
              (band[i].box.height < band[i + 1].box.height
                  ? band[i].box.height
                  : band[i + 1].box.height),
    );
    final quantityText = closeDecimalFragments
        ? fullText
              .replaceAll(RegExp(r'(?<=[,.])\s+(?=[0-9])'), '')
              .replaceAll(RegExp(r'(?<=[0-9])\s+(?=[,.])'), '')
        : fullText;
    final quantity = quantityPattern.firstMatch(quantityText);
    if (quantity != null) {
      final value = parseFixed(quantity[1]!, 6);
      final rate = parseFixed(quantity[3]!, 6);
      final unit = switch (quantity[2]!.toLowerCase()) {
        'kg' => QuantityUnit.kg,
        'kpl' => QuantityUnit.piece,
        'l' => QuantityUnit.litre,
        _ => QuantityUnit.unknown,
      };
      final candidate =
          value != null &&
              rate != null &&
              quantity[2]!.toLowerCase() == quantity[4]!.toLowerCase()
          ? QuantityRateCandidate(Quantity(value, 6, unit), rate)
          : null;
      if (!canAttachQuantity ||
          rows.isEmpty ||
          value == null ||
          rate == null ||
          quantity[2]!.toLowerCase() != quantity[4]!.toLowerCase()) {
        report(ParseIssue.quantityWithoutProduct, quantityCandidate: candidate);
        notes.add(fullText);
      } else {
        rows[rows.length - 1] = rows.last.withQuantity(
          Quantity(value, 6, unit),
          rate,
        );
        rowEvidence.last.addAll(band);
        activeRow = rows.length - 1;
        activeWords = rowEvidence.last;
        if (quantityText != fullText) report(ParseIssue.normalizedOcrAmount);
        if (rows.last.quantityMatches == false)
          report(ParseIssue.quantityMismatch);
      }
      canAttachQuantity = false;
      continue;
    }
    canAttachQuantity = false;
    if (RegExp(r'^(NORM\.?|NORMAALIHINTA|KAMPANJA)(?:\s|$)').hasMatch(upper)) {
      notes.add(fullText);
      report(
        ParseIssue.discountNeedsReview,
        discountKind: DiscountFindingKind.explanatoryPrice,
      );
      continue;
    }
    // A valid posted row will use this index; malformed/unclassified bands
    // are reset below because they never become a row.
    activeRow = name.isEmpty ? null : rows.length;
    final cents = amount(amountText);
    if (name.isEmpty || cents == null) {
      activeRow = null;
      notes.add(fullText);
      report(
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
    if (kind == LineKind.discount) {
      report(
        ParseIssue.discountNeedsReview,
        discountKind: DiscountFindingKind.postedDiscount,
      );
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
      activeWords = rowEvidence.last;
      report(ParseIssue.wrappedNameNeedsReview);
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
    findings: findings,
    branchCandidates: branchCandidates,
    parseContext: ReceiptParseContext(page, itemTop, priceColumnLeft),
    evidenceCoverage: ReceiptEvidenceCoverage(
      sourceWords: page.words,
      header: [
        ...page.words.where((word) => word.box.bottom <= itemTop),
        ...headerNotices.expand((band) => band),
      ],
      rows: rowEvidence.expand((words) => words),
      // Geometry evidence locates a problem; it does not classify its words.
      // Whole-page skew evidence must not conceal section omissions.
      findings: findings
          .where(
            (finding) =>
                finding.issue != ParseIssue.ambiguousGeometry &&
                finding.issue != ParseIssue.skewAdjusted,
          )
          .expand((finding) => finding.words),
      totals: candidates.expand((words) => words),
      footer: footer < 0
          ? const []
          : bands.skip(footer).expand((words) => words),
    ),
  );
}
