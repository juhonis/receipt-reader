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
}

bool isUnparsedItemFinding(ParseFinding finding) =>
    finding.scope == FindingScope.item &&
    finding.rowIndex == null &&
    (finding.issue == ParseIssue.unclassifiedRow ||
        finding.issue == ParseIssue.invalidAmount ||
        finding.issue == ParseIssue.normalizedOcrAmount ||
        finding.issue == ParseIssue.unassignedSource);

/// Review-only findings retain omissions separately from parser warnings.
List<ParseFinding> reviewFindingsForDraft(ReceiptDraft draft) =>
    List.unmodifiable([
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
