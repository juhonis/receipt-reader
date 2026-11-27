import 'finance.dart';
import 'parser.dart';
import 'review.dart';
import 'geometry.dart';

enum RowEvidenceKind {
  financialRow,
  description,
  headerMetadata,
  paymentOrTax,
  explanatoryText,
  duplicateOcr,
}

bool isUnparsedItemFinding(ParseFinding finding) =>
    finding.scope == FindingScope.item &&
    finding.rowIndex == null &&
    (finding.issue == ParseIssue.unclassifiedRow ||
        finding.issue == ParseIssue.invalidAmount ||
        finding.issue == ParseIssue.normalizedOcrAmount ||
        finding.issue == ParseIssue.unassignedSource ||
        finding.issue == ParseIssue.geometrySource ||
        finding.issue == ParseIssue.removedSource);

/// Review-only findings retain omissions separately from parser warnings.
List<ParseFinding> reviewFindingsForDraft(
  ReceiptDraft draft, {
  bool streamlined = false,
}) => List.unmodifiable([
  ...draft.findings,
  for (final issue in draft.issues)
    if (!draft.findings.any((finding) => finding.issue == issue))
      ParseFinding(issue),
  for (final word in draft.evidenceCoverage?.unassignedWords ?? <OcrWord>[])
    ParseFinding(
      ParseIssue.unassignedSource,
      scope: FindingScope.item,
      words: [word],
    ),
  if (!streamlined)
    for (final word in {
      for (final finding in draft.findings)
        if (finding.geometryKind == GeometryFindingKind.wordOverlap ||
            finding.geometryKind == GeometryFindingKind.ambiguousBand)
          ...finding.words,
    })
      if (!(draft.evidenceCoverage?.unassignedWords.contains(word) ?? false))
        ParseFinding(
          ParseIssue.geometrySource,
          scope: FindingScope.item,
          words: [word],
        ),
]);

List<OcrWord> unreviewedOmissions(
  ReceiptEvidenceCoverage coverage,
  List<ParseFinding> findings,
  Set<int> handled,
) {
  final accounted = {
    for (final index in handled)
      if (index >= 0 &&
          index < findings.length &&
          findings[index].issue == ParseIssue.unassignedSource &&
          findings[index].scope == FindingScope.item)
        ...findings[index].words,
  };
  return List.unmodifiable(
    coverage.unassignedWords.where((word) => !accounted.contains(word)),
  );
}

/// Field prerequisites only; the workflow still requires an image-backed,
/// explicit decision. Written notes are optional. No arithmetic-based inference
/// of missing rows.
bool canResolveRowEvidence(
  ParseFinding finding,
  RowEvidenceKind kind, {
  ReviewRowInput? target,
}) {
  final orphanInformation =
      finding.rowIndex == null &&
      ((finding.issue == ParseIssue.quantityWithoutProduct &&
              finding.discountKind == null) ||
          (finding.issue == ParseIssue.discountNeedsReview &&
              finding.discountKind == DiscountFindingKind.explanatoryPrice));
  if ((!isUnparsedItemFinding(finding) && !orphanInformation) ||
      finding.words.isEmpty)
    return false;
  if (orphanInformation &&
      kind != RowEvidenceKind.headerMetadata &&
      kind != RowEvidenceKind.paymentOrTax &&
      kind != RowEvidenceKind.explanatoryText)
    return false;
  switch (kind) {
    case RowEvidenceKind.financialRow:
    case RowEvidenceKind.description:
    case RowEvidenceKind.duplicateOcr:
      if (target == null ||
          target.name.trim().isEmpty ||
          parseCents(target.amount) == null)
        return false;
      // Discount repair also needs an explicit discount relationship; deferred
      // until conversion between financial/explanatory rows is implemented.
      if (target.kind == LineKind.discount) return false;
      if (kind == RowEvidenceKind.description &&
          target.kind != LineKind.product)
        return false;
      return target.quantityState == QuantityReviewState.absent ||
          target.quantityState == QuantityReviewState.matched;
    case RowEvidenceKind.headerMetadata:
    case RowEvidenceKind.paymentOrTax:
    case RowEvidenceKind.explanatoryText:
      return target == null;
  }
}
