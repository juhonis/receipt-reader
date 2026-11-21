import 'finance.dart';
import 'geometry.dart';
import 'parser.dart';
import 'receipt_date.dart';
import 'relationships.dart';
import 'review.dart';
import 'row_evidence.dart';

class OcrReviewRow {
  OcrReviewRow(this.id, this.input, this.compared, Iterable<OcrWord> words)
    : words = List.unmodifiable(words);
  final Object id;
  final ReviewRowInput input;
  final bool compared;
  final List<OcrWord> words;
}

/// Immutable values approved on the evidence screen; compare with current
/// values to reject approval after edits, reordering, or evidence-link changes.
class OcrReviewSnapshot {
  OcrReviewSnapshot(
    this.draft,
    this.branch,
    this.date,
    this.total,
    this.branchConfirmed,
    Iterable<OcrReviewRow> rows,
  ) : rows = List.unmodifiable(rows);
  final ReceiptDraft draft;
  final String branch, date, total;
  final bool branchConfirmed;
  final List<OcrReviewRow> rows;

  bool matches(OcrReviewSnapshot other) {
    if (!identical(draft, other.draft) ||
        branch != other.branch ||
        date != other.date ||
        total != other.total ||
        branchConfirmed != other.branchConfirmed ||
        rows.length != other.rows.length)
      return false;
    for (var i = 0; i < rows.length; i++) {
      final a = rows[i], b = other.rows[i];
      if (!identical(a.id, b.id) ||
          !_sameInput(a.input, b.input) ||
          a.words.length != b.words.length)
        return false;
      for (var w = 0; w < a.words.length; w++) {
        if (!identical(a.words[w], b.words[w])) return false;
      }
    }
    return true;
  }
}

bool _sameInput(ReviewRowInput a, ReviewRowInput b) =>
    a.name == b.name &&
    a.amount == b.amount &&
    a.kind == b.kind &&
    a.quantity == b.quantity &&
    a.rate == b.rate &&
    a.unit == b.unit;

bool _validRow(ReviewRowInput row) =>
    row.name.trim().isNotEmpty &&
    parseCents(row.amount) != null &&
    (row.quantityState == QuantityReviewState.absent ||
        row.quantityState == QuantityReviewState.matched) &&
    (row.kind != LineKind.discount || parseCents(row.amount)! < BigInt.zero);

bool canApprovePageEvidence(OcrReviewSnapshot snapshot) =>
    snapshot.branchConfirmed &&
    snapshot.branch.trim().isNotEmpty &&
    parseReceiptDate(snapshot.date).state == ReceiptDateState.valid &&
    parseCents(snapshot.total) != null &&
    snapshot.rows.isNotEmpty &&
    snapshot.rows.every((row) => row.compared && _validRow(row.input));

class PageEvidenceApproval {
  const PageEvidenceApproval(
    this.snapshot,
    this.note, {
    required this.headerCompared,
    required this.footerCompared,
    required this.layoutCompared,
    required this.imageComplete,
  });
  final OcrReviewSnapshot snapshot;
  final String note;
  final bool headerCompared, footerCompared, layoutCompared, imageComplete;
  bool validFor(OcrReviewSnapshot current) =>
      snapshot.matches(current) &&
      note.trim().isNotEmpty &&
      headerCompared &&
      footerCompared &&
      layoutCompared &&
      imageComplete &&
      canApprovePageEvidence(current);
}

/// Legacy detailed evidence remains readable; new receipts use one explicit
/// receipt-level approval without claiming per-row or per-section comparisons.
enum OcrReviewPolicy { detailed, receipt }

enum ReceiptReviewMethod { quick, guided }

class ReceiptReviewApproval {
  const ReceiptReviewApproval(this.snapshot, this.method);
  final OcrReviewSnapshot snapshot;
  final ReceiptReviewMethod method;
  bool validFor(OcrReviewSnapshot current) =>
      snapshot.matches(current) && canAcceptReceipt(current);
}

bool canAcceptReceipt(OcrReviewSnapshot snapshot) => ReviewValidation(
  branch: snapshot.branch,
  dateText: snapshot.date,
  totalText: snapshot.total,
  rows: snapshot.rows.map((r) => r.input).toList(),
  branchConfirmed: snapshot.branchConfirmed,
  reviewed: true,
).complete;

class FindingEvidenceDecision {
  const FindingEvidenceDecision({
    required this.note,
    required this.compared,
    this.target,
    this.rowKind,
    this.relationshipKind,
    this.nameHandled = false,
    this.geometrySnapshot,
  });
  final String note;
  final bool compared, nameHandled;
  final Object? target;
  final RowEvidenceKind? rowKind;
  final ReviewRelationshipKind? relationshipKind;
  final OcrReviewSnapshot? geometrySnapshot;
}

bool isGeometryFinding(ParseFinding finding) =>
    finding.issue == ParseIssue.ambiguousGeometry ||
    finding.issue == ParseIssue.skewAdjusted;

enum OcrEvidenceBlocker {
  sourceContext,
  rowReview,
  pageReview,
  receiptApproval,
  originalRows,
  originalQuantities,
  openFindings,
  omissions,
  discountRelationships,
  quantityRelationships,
}

/// Evidence readiness is independent of receipt-sum reconciliation and final
/// confirmation. It is not permission to persist the receipt.
class OcrEvidenceAudit {
  OcrEvidenceAudit({
    required this.snapshot,
    required List<ParseFinding> findings,
    required Map<int, FindingEvidenceDecision> decisions,
    required List<Object> originalRowIds,
    required bool imageMatchesSource,
    required PageEvidenceApproval? pageApproval,
    this.policy = OcrReviewPolicy.detailed,
    this.receiptApproval,
  }) : findings = List.unmodifiable(findings),
       decisions = Map.unmodifiable(decisions),
       originalRowIds = List.unmodifiable(originalRowIds) {
    final draft = snapshot.draft;
    final context = draft.parseContext, coverage = draft.evidenceCoverage;
    final source = context?.page.words ?? <OcrWord>[];
    final sourceSet = source.toSet();
    bool sameWords(List<OcrWord> a, List<OcrWord> b) =>
        a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => identical(a[i], b[i]));
    final contextValid =
        imageMatchesSource &&
        context != null &&
        coverage != null &&
        source.isNotEmpty &&
        sameWords(source, coverage.sourceWords) &&
        snapshot.rows.every((row) => row.words.every(sourceSet.contains)) &&
        findings.every((finding) => finding.words.every(sourceSet.contains)) &&
        findings.toSet().length == findings.length &&
        context.itemTop.isFinite &&
        context.itemTop >= 0 &&
        context.itemTop < context.page.height &&
        context.priceColumnLeft.isFinite &&
        context.priceColumnLeft > 0 &&
        context.priceColumnLeft < context.page.width &&
        originalRowIds.length == draft.rows.length &&
        originalRowIds.toSet().length == originalRowIds.length &&
        draft.rowEvidence.length == draft.rows.length &&
        draft.rowEvidence.every(
          (words) => words.isNotEmpty && words.every(sourceSet.contains),
        ) &&
        draft.findings.every(
          (f) => findings.where((current) => identical(current, f)).length == 1,
        ) &&
        draft.issues.every((issue) => findings.any((f) => f.issue == issue));
    if (!contextValid) _blockers.add(OcrEvidenceBlocker.sourceContext);
    OcrReviewRow? rowWithId(Object? id) {
      for (final row in snapshot.rows) {
        if (identical(row.id, id)) return row;
      }
      return null;
    }

    OcrReviewRow? sourceRow(ParseFinding finding) =>
        finding.rowIndex == null ||
            finding.rowIndex! < 0 ||
            finding.rowIndex! >= originalRowIds.length
        ? null
        : rowWithId(originalRowIds[finding.rowIndex!]);
    bool ordinaryValid(int index) {
      final finding = findings[index], decision = decisions[index];
      if (decision == null ||
          !decision.compared ||
          decision.note.trim().isEmpty)
        return false;
      if ([
            ParseIssue.geometrySource,
            ParseIssue.unassignedSource,
            ParseIssue.removedSource,
          ].contains(finding.issue) &&
          finding.words.length != 1)
        return false;
      final target = rowWithId(decision.target)?.input;
      if (isUnparsedItemFinding(finding)) {
        return decision.rowKind != null &&
            (decision.target == null || target != null) &&
            canResolveRowEvidence(finding, decision.rowKind!, target: target);
      }
      if (finding.issue == ParseIssue.quantityWithoutProduct ||
          finding.discountKind != null) {
        return decision.relationshipKind != null &&
            (decision.target == null || target != null) &&
            canResolveRelationship(
              finding,
              decision.relationshipKind!,
              source: sourceRow(finding)?.input,
              target: target,
            );
      }
      return decision.rowKind == null &&
          decision.relationshipKind == null &&
          canResolveFinding(
            finding,
            row: sourceRow(finding)?.input,
            total: snapshot.total,
            nameHandled: decision.nameHandled,
          );
    }

    final ordinary = <int>{
      for (var i = 0; i < findings.length; i++)
        if (!isGeometryFinding(findings[i]) && ordinaryValid(i)) i,
    };
    final accountedWords = <OcrWord>{
      for (final index in ordinary)
        if (findings[index].issue == ParseIssue.geometrySource ||
            findings[index].issue == ParseIssue.unassignedSource ||
            findings[index].issue == ParseIssue.removedSource)
          ...findings[index].words,
    };
    final rowsReady =
        snapshot.rows.isNotEmpty &&
        snapshot.rows.map((r) => r.id).toSet().length == snapshot.rows.length &&
        snapshot.rows.every(
          (row) =>
              (policy == OcrReviewPolicy.receipt || row.compared) &&
              _validRow(row.input),
        );
    if (!rowsReady) _blockers.add(OcrEvidenceBlocker.rowReview);
    final pageReady =
        policy == OcrReviewPolicy.receipt ||
        (pageApproval?.validFor(snapshot) ?? false);
    if (!pageReady) _blockers.add(OcrEvidenceBlocker.pageReview);
    if ((policy == OcrReviewPolicy.receipt &&
            !(receiptApproval?.validFor(snapshot) ?? false)) ||
        (policy == OcrReviewPolicy.detailed && receiptApproval != null)) {
      _blockers.add(OcrEvidenceBlocker.receiptApproval);
    }
    for (var i = 0; i < draft.rows.length && i < originalRowIds.length; i++) {
      final current = rowWithId(originalRowIds[i]);
      if (current == null) {
        // Removed financial rows need explicit per-word duplicate/non-financial
        // dispositions. A matching sum never justifies dropping source evidence.
        final words = i < draft.rowEvidence.length
            ? draft.rowEvidence[i]
            : <OcrWord>[];
        final disposed =
            words.isNotEmpty &&
            words.every(
              (word) => ordinary.any(
                (index) =>
                    findings[index].words.contains(word) &&
                    [
                      RowEvidenceKind.duplicateOcr,
                      RowEvidenceKind.headerMetadata,
                      RowEvidenceKind.paymentOrTax,
                      RowEvidenceKind.explanatoryText,
                    ].contains(decisions[index]?.rowKind) &&
                    (decisions[index]?.rowKind !=
                            RowEvidenceKind.duplicateOcr ||
                        (draft.rows[i].quantity == null &&
                            draft.rows[i].rateMicros == null) ||
                        rowWithId(decisions[index]?.target)
                                ?.input
                                .quantityState ==
                            QuantityReviewState.matched),
              ),
            );
        if (!disposed) _blockers.add(OcrEvidenceBlocker.originalRows);
      } else if ((draft.rows[i].quantity != null ||
              draft.rows[i].rateMicros != null) &&
          current.input.quantityState != QuantityReviewState.matched) {
        _blockers.add(OcrEvidenceBlocker.originalQuantities);
      }
    }
    if (coverage == null ||
        coverage.unassignedWords.any((w) => !accountedWords.contains(w))) {
      _blockers.add(OcrEvidenceBlocker.omissions);
    }
    for (final row in snapshot.rows.where(
      (r) => r.input.kind == LineKind.discount,
    )) {
      if (!ordinary.any(
        (i) =>
            findings[i].discountKind == DiscountFindingKind.postedDiscount &&
            identical(sourceRow(findings[i])?.id, row.id) &&
            decisions[i]?.relationshipKind != null,
      )) {
        _blockers.add(OcrEvidenceBlocker.discountRelationships);
      }
    }
    final nonGeometryReady = Iterable<int>.generate(findings.length)
        .where((i) => !isGeometryFinding(findings[i]))
        .every(ordinary.contains);
    final quantityTargets = <Object>{};
    for (final index in ordinary) {
      final decision = decisions[index]!;
      if (decision.relationshipKind == ReviewRelationshipKind.quantity &&
          decision.target != null &&
          !quantityTargets.add(decision.target!))
        _blockers.add(OcrEvidenceBlocker.quantityRelationships);
    }
    for (var i = 0; i < findings.length; i++) {
      final finding = findings[i];
      if (!isGeometryFinding(finding)) {
        if (!ordinary.contains(i)) _unresolved.add(i);
        continue;
      }
      final kind = finding.geometryKind;
      final supportsGeometry =
          (finding.issue == ParseIssue.ambiguousGeometry &&
              (kind == GeometryFindingKind.wordOverlap ||
                  kind == GeometryFindingKind.ambiguousBand)) ||
          (finding.issue == ParseIssue.skewAdjusted &&
              kind == GeometryFindingKind.skew);
      final prerequisites =
          contextValid &&
          supportsGeometry &&
          rowsReady &&
          pageReady &&
          nonGeometryReady &&
          !_blockers.contains(OcrEvidenceBlocker.originalRows) &&
          !_blockers.contains(OcrEvidenceBlocker.originalQuantities) &&
          !_blockers.contains(OcrEvidenceBlocker.omissions) &&
          !_blockers.contains(OcrEvidenceBlocker.discountRelationships) &&
          !_blockers.contains(OcrEvidenceBlocker.quantityRelationships) &&
          finding.words.isNotEmpty &&
          finding.words.every(sourceSet.contains) &&
          (kind == GeometryFindingKind.skew ||
              finding.words.every(accountedWords.contains));
      if (prerequisites) _resolvableGeometry.add(i);
      final decision = decisions[i];
      if (!prerequisites ||
          decision == null ||
          !decision.compared ||
          decision.note.trim().isEmpty ||
          !(decision.geometrySnapshot?.matches(snapshot) ?? false))
        _unresolved.add(i);
    }
    if (_unresolved.isNotEmpty) _blockers.add(OcrEvidenceBlocker.openFindings);
  }
  final OcrReviewSnapshot snapshot;
  final OcrReviewPolicy policy;
  final ReceiptReviewApproval? receiptApproval;
  final List<Object> originalRowIds;
  final List<ParseFinding> findings;
  final Map<int, FindingEvidenceDecision> decisions;
  final _blockers = <OcrEvidenceBlocker>{};
  final _unresolved = <int>{};
  final _resolvableGeometry = <int>{};
  Set<OcrEvidenceBlocker> get blockers => Set.unmodifiable(_blockers);
  Set<int> get unresolved => Set.unmodifiable(_unresolved);
  Set<int> get resolvableGeometry => Set.unmodifiable(_resolvableGeometry);

  /// Does not establish human approval or authorize persistence.
  bool get automaticReady =>
      policy == OcrReviewPolicy.receipt &&
      _blockers.every((b) => b == OcrEvidenceBlocker.receiptApproval) &&
      canAcceptReceipt(snapshot);
  bool get ready => _blockers.isEmpty;
}
