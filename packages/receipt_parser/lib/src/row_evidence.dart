import 'finance.dart';
import 'parser.dart';
import 'review.dart';

enum RowEvidenceKind {
  financialRow,
  description,
  headerMetadata,
  paymentOrTax,
  explanatoryText,
}

bool isUnparsedItemFinding(ParseFinding finding) =>
    finding.scope == FindingScope.item &&
    finding.rowIndex == null &&
    (finding.issue == ParseIssue.unclassifiedRow ||
        finding.issue == ParseIssue.invalidAmount ||
        finding.issue == ParseIssue.normalizedOcrAmount);

/// Field prerequisites only; image comparison and an explanation are required
/// by the review workflow. No arithmetic-based inference of missing rows.
bool canResolveRowEvidence(
  ParseFinding finding,
  RowEvidenceKind kind, {
  ReviewRowInput? target,
}) {
  if (!isUnparsedItemFinding(finding) || finding.words.isEmpty) return false;
  switch (kind) {
    case RowEvidenceKind.financialRow:
    case RowEvidenceKind.description:
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
