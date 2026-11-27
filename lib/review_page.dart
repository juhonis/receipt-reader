import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart' show StoredReceipt;

import 'l10n/generated/app_localizations.dart';
import 'receipt_import.dart';
import 'receipt_ocr.dart';
import 'receipt_evidence_painter.dart';
import 'relationship_dialog.dart';
import 'row_evidence_dialog.dart';
import 'layout_review_dialog.dart';
import 'page_evidence_dialog.dart';
import 'local_store.dart';
import 'catalog_service.dart';
import 'product_picker.dart';
import 'ocr_save_dialog.dart';
import 'app_version.dart';
import 'branch_recommendations.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    this.draft,
    this.evidence,
    this.recognizer,
    this.store,
  }) : _initial = null;
  factory ReviewPage.correction({
    Key? key,
    required LocalStore store,
    required StoredReceipt receipt,
    required ReceiptEvidence evidence,
    ReceiptDraft? draft,
    Future<OcrPage> Function(ReceiptEvidence)? recognizer,
  }) {
    if (receipt.document.review.source != 'ocr') {
      throw ArgumentError.value(receipt, 'receipt', 'OCR receipt required');
    }
    return ReviewPage._correction(
      key: key,
      store: store,
      receipt: receipt,
      evidence: evidence,
      draft: draft,
      recognizer: recognizer,
    );
  }
  const ReviewPage._correction({
    super.key,
    required this.store,
    required StoredReceipt receipt,
    required this.evidence,
    this.draft,
    this.recognizer,
  }) : _initial = receipt;
  final StoredReceipt? _initial;
  final Future<OcrPage> Function(ReceiptEvidence)? recognizer;
  final LocalStore? store;
  final ReceiptDraft? draft;
  final ReceiptEvidence? evidence;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _RowFields {
  final anchor = GlobalKey();
  final name = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final rate = TextEditingController();
  final reason = TextEditingController();
  Object? depositParent;
  ReceiptProductLink? product;
  String? productName;
  bool standaloneDeposit = false;
  QuantityUnit unit = QuantityUnit.unknown;
  bool imageCompared = false;
  String? savedRowChoice;
  List<OcrWord> evidence = const [];
  ReviewRowInput get input => ReviewRowInput(
    name.text,
    amount.text,
    kind,
    quantity: quantity.text,
    rate: rate.text,
    unit: unit,
  );
  LineKind kind = LineKind.product;
  void dispose() {
    name.dispose();
    amount.dispose();
    quantity.dispose();
    rate.dispose();
    reason.dispose();
  }
}

class _ReviewPageState extends State<ReviewPage> {
  final _reviewScroll = ScrollController();
  final _branchAnchor = GlobalKey(),
      _dateAnchor = GlobalKey(),
      _totalAnchor = GlobalKey();
  final _branch = TextEditingController();
  final _date = TextEditingController();
  final _total = TextEditingController();
  final _rows = [_RowFields()];
  bool _branchConfirmed = false;
  bool _reviewed = false;
  bool _guidedReviewCompleted = false;
  bool _saving = false;
  bool get _streamlined => widget.store != null;
  bool get _branchIsConfirmed =>
      _streamlined ? _selectedBranch != null : _branchConfirmed;
  late final _receiptId =
      widget._initial?.document.snapshot.id ?? DurableId.generate();
  final _newBranchId = DurableId.generate();
  List<RevisionId> get _expectedHeads => [
    if (widget._initial case final initial?) initial.revision,
  ];
  bool get _mappingReady =>
      widget._initial == null ||
      (_rows.every((r) => r.savedRowChoice != null) &&
          _rows
                  .where((r) => r.savedRowChoice != 'new')
                  .map((r) => r.savedRowChoice)
                  .toSet()
                  .length ==
              _rows.where((r) => r.savedRowChoice != 'new').length);
  bool get _detailsReady => _rows.every(
    (r) =>
        (r.kind != LineKind.adjustment || r.reason.text.trim().isNotEmpty) &&
        (r.kind != LineKind.deposit ||
            r.standaloneDeposit ||
            _rows.any(
              (parent) =>
                  identical(parent, r.depositParent) &&
                  parent.kind == LineKind.product,
            )),
  );

  Future<void> _showField(GlobalKey anchor) async {
    if (!_reviewScroll.hasClients) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // The form is lazy. Materialize the target before asking ensureVisible to
    // reveal it; this also works with enlarged text and long receipts.
    if (anchor.currentContext == null) {
      _reviewScroll.jumpTo(0);
      for (var i = 0; mounted && i < 200; i++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            !_reviewScroll.hasClients ||
            anchor.currentContext != null) {
          break;
        }
        final p = _reviewScroll.position;
        if (p.pixels >= p.maxScrollExtent) break;
        _reviewScroll.jumpTo(
          (p.pixels + p.viewportDimension * .7).clamp(0, p.maxScrollExtent),
        );
      }
    }
    final target = anchor.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: .15,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  String _savedRowLabel(ReceiptItemSnapshot item) {
    final items = widget._initial!.document.snapshot.items;
    return '${items.indexOf(item) + 1}. ${item.name} (${formatCents(item.cents)} €)';
  }

  List<ReceiptBranch>? _branches;
  String? _branchChoice;
  bool _branchTouched = false;
  String? _automaticBranchChoice;
  bool _branchLoadFailed = false, _savePreparationFailed = false;

  List<ReceiptBranch> get _recommendedBranches => recommendedBranches(
    _draft?.branchCandidates ?? const [],
    _branches ?? const [],
  );

  void _recommendBranch() {
    // A saved receipt's branch and all explicit user choices take precedence.
    if (_branchTouched || widget._initial != null) return;
    final matches = _recommendedBranches;
    if (matches.length != 1) return;
    _branchChoice = matches.single.id.value;
    _branch.text = matches.single.name;
    _automaticBranchChoice = _branchChoice;
  }

  void _chooseBranch(String value, {String? proposedName}) {
    _branchTouched = true;
    _automaticBranchChoice = null;
    _branchChoice = value;
    _branch.text = value == 'new'
        ? proposedName ?? ''
        : _branches!.firstWhere((b) => b.id.value == value).name;
    _branchConfirmed = false;
    _edit();
  }

  ReceiptBranch? get _selectedBranch => _branchChoice == 'new'
      ? (_branch.text.trim().isEmpty
            ? null
            : ReceiptBranch(id: _newBranchId, name: _branch.text.trim()))
      : _branches?.where((b) => b.id.value == _branchChoice).firstOrNull;

  Map<Object, OcrRowDetails> get _rowDetails => {
    for (final row in _rows)
      row: OcrRowDetails(
        product: row.product,
        depositParent: row.kind == LineKind.deposit ? row.depositParent : null,
        standaloneDeposit:
            row.kind == LineKind.deposit && row.standaloneDeposit,
        adjustmentReason: row.kind == LineKind.adjustment
            ? row.reason.text.trim()
            : null,
      ),
  };

  Future<void> _loadBranches() async {
    if (widget.store == null) return;
    setState(() => _branchLoadFailed = false);
    try {
      final branches = await widget.store!.branches();
      if (mounted) {
        setState(() {
          _branches = branches;
          if (branches.isEmpty && _branchChoice == null) _branchChoice = 'new';
          _recommendBranch();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _branchLoadFailed = true);
    }
  }

  Future<void> _saveOcr() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _performSaveOcr();
    } finally {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _performSaveOcr() async {
    // The user's save action approves these exact current values. This does not
    // synthesize legacy per-row comparisons or section-specific approvals.
    final receiptApproval = _streamlined
        ? ReceiptReviewApproval(
            _snapshot,
            _guidedReviewCompleted
                ? ReceiptReviewMethod.guided
                : ReceiptReviewMethod.quick,
          )
        : null;
    final approved = _auditFor(receiptApproval), branch = _selectedBranch;
    if (approved == null ||
        !approved.ready ||
        branch == null ||
        (!_streamlined && !_reviewed) ||
        !_mappingReady) {
      return;
    }
    final approvedDetails = Map<Object, OcrRowDetails>.unmodifiable(
      _rowDetails,
    );
    final s = AppLocalizations.of(context)!;
    var dateChecked = _streamlined, totalChecked = _streamlined;
    var identitiesChecked = widget._initial == null;
    final mapping = {for (final row in _rows) row: row.savedRowChoice};
    final rowIds = ReviewRowIds();
    for (final row in _rows) {
      if (row.savedRowChoice != null && row.savedRowChoice != 'new') {
        rowIds.retain(row, DurableId.parse(row.savedRowChoice!));
      }
    }
    late final OcrReviewChecks checks;
    try {
      checks = OcrReviewChecks(
        audit: approved,
        branch: branch,
        receiptId: _receiptId,
        rowIds: rowIds,
        rowDetails: approvedDetails,
        expectedHeads: _expectedHeads,
        mutationId: DurableId.generate(),
        // Quick saving explicitly approves date and total along with the
        // displayed receipt. Corrections also confirm identity changes below.
        dateReviewed: true,
        totalReviewed: true,
      );
    } on ReceiptDataException {
      setState(() {
        _savePreparationFailed = true;
        _reviewed = false;
      });
      return;
    }
    final removed =
        widget._initial?.document.snapshot.items
            .where(
              (item) => !_rows.any((r) => r.savedRowChoice == item.id.value),
            )
            .toList() ??
        <ReceiptItemSnapshot>[];
    final matchedLabels = widget._initial == null
        ? <String>[]
        : [
            for (final row in _rows)
              '${row.name.text}: ${row.savedRowChoice == 'new' ? s.ocrCorrectionNewRow : _savedRowLabel(widget._initial!.document.snapshot.items.firstWhere((item) => item.id.value == row.savedRowChoice))}',
          ];
    final yes = _streamlined && widget._initial == null
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(
                  widget._initial == null
                      ? s.ocrSaveFinalTitle
                      : s.manualCorrectionFinalTitle,
                ),
                scrollable: true,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(branch.name),
                    Text(approved.snapshot.date),
                    Text(approved.snapshot.total),
                    Text(
                      _streamlined ? s.ocrAcceptNotice : s.ocrSaveFinalNotice,
                    ),
                    if (widget.store is CatalogService) ...[
                      Text(s.productLinksReview),
                      if (widget._initial != null) Text(s.productOcrCorrection),
                      for (final row in _rows.where(
                        (r) => r.kind == LineKind.product,
                      )) ...[
                        Text(row.name.text),
                        if (row.product == null)
                          Text(s.productUnlinked)
                        else
                          ProductLinkLabel(
                            service: widget.store! as CatalogService,
                            link: row.product!,
                          ),
                      ],
                    ],
                    if (widget._initial != null) ...[
                      for (final label in matchedLabels) Text(label),
                      Text(
                        removed.isEmpty
                            ? s.ocrCorrectionNoRemoved
                            : s.ocrCorrectionRemoved,
                      ),
                      for (final item in removed) Text(_savedRowLabel(item)),
                      Text(s.ocrCorrectionFinal),
                      CheckboxListTile(
                        key: const Key('ocr-save-identities'),
                        title: Text(s.ocrCorrectionIdentitiesReviewed),
                        value: identitiesChecked,
                        onChanged: (v) =>
                            update(() => identitiesChecked = v ?? false),
                      ),
                    ],
                    if (!_streamlined)
                      CheckboxListTile(
                        key: const Key('ocr-save-date'),
                        title: Text(s.manualDateReviewed),
                        value: dateChecked,
                        onChanged: (v) =>
                            update(() => dateChecked = v ?? false),
                      ),
                    if (!_streamlined)
                      CheckboxListTile(
                        key: const Key('ocr-save-total'),
                        title: Text(s.manualTotalReviewed),
                        value: totalChecked,
                        onChanged: (v) =>
                            update(() => totalChecked = v ?? false),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(s.cancelAction),
                  ),
                  FilledButton(
                    key: const Key('ocr-confirm-save'),
                    onPressed: dateChecked && totalChecked && identitiesChecked
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: Text(s.saveReceipt),
                  ),
                ],
              ),
            ),
          );
    if (!mounted ||
        yes != true ||
        !dateChecked ||
        !totalChecked ||
        !identitiesChecked) {
      return;
    }
    ReviewedReceipt command;
    try {
      if ((!_streamlined && !_reviewed) ||
          !_hasLayoutContext ||
          _selectedBranch == null ||
          _evidenceAudit == null ||
          !_mappingReady ||
          _rows.length != mapping.length ||
          !_rows.every(
            (row) =>
                mapping.containsKey(row) && mapping[row] == row.savedRowChoice,
          )) {
        throw const ReceiptDataException('review', 'staleEvidence');
      }
      command = ReviewedReceipt.ocr(
        current: _auditFor(receiptApproval)!,
        branch: _selectedBranch!,
        rowDetails: _rowDetails,
        expectedHeads: _expectedHeads,
        confirmation: checks.confirm(
          reviewedAtMs: BigInt.from(
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
          appVersion: receiptAppVersion,
        ),
      );
      ReceiptDocumentCodec.decode(
        ReceiptDocumentCodec.encode(command.document),
      );
    } on ReceiptDataException {
      setState(() {
        _savePreparationFailed = true;
        _reviewed = false;
      });
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OcrSaveDialog(store: widget.store!, command: command),
    );
    if (mounted) Navigator.pop(context, true);
  }

  final _handledNames = <int>{};
  final _resolvedFindings = <int>{};
  final _findingNotes = <int, String>{};
  final _relationships = <int, RelationshipDecision>{};
  final _rowDecisions = <int, RowEvidenceDecision>{};
  List<ParseFinding> _findings = [];
  PageEvidenceApproval? _pageApproval;
  final _geometryApprovals = <int, OcrReviewSnapshot>{};

  OcrReviewSnapshot get _snapshot => OcrReviewSnapshot(
    _draft!,
    _branch.text,
    _date.text,
    _total.text,
    _branchIsConfirmed,
    [
      for (final row in _rows)
        OcrReviewRow(row, row.input, row.imageCompared, _rowEvidence(row)),
    ],
  );

  OcrEvidenceAudit? get _evidenceAudit => _auditFor();

  OcrEvidenceAudit? _auditFor([ReceiptReviewApproval? approval]) =>
      _draft == null
      ? null
      : OcrEvidenceAudit(
          snapshot: _snapshot,
          findings: _findings,
          originalRowIds: _sourceRows,
          imageMatchesSource: _hasLayoutContext,
          pageApproval: _pageApproval,
          policy: _streamlined
              ? OcrReviewPolicy.receipt
              : OcrReviewPolicy.detailed,
          receiptApproval: approval,
          decisions: {
            for (final index in _resolvedFindings)
              index: FindingEvidenceDecision(
                note: _findingNotes[index] ?? '',
                compared: true,
                rowKind: _rowDecisions[index]?.kind,
                relationshipKind: _relationships[index]?.kind,
                target:
                    _rowDecisions[index]?.target ??
                    _relationships[index]?.target,
                nameHandled: _draft!.wrappedNames.asMap().entries.any(
                  (entry) =>
                      entry.value.rowIndex == _findings[index].rowIndex &&
                      _handledNames.contains(entry.key),
                ),
                geometrySnapshot: _geometryApprovals[index],
              ),
          },
        );

  void _invalidatePageEvidence() {
    _pageApproval = null;
    _geometryApprovals.clear();
    _resolvedFindings.removeWhere(
      (index) => isGeometryFinding(_findings[index]),
    );
  }

  Future<void> _reviewPageEvidence() async {
    if (!_hasLayoutContext) return;
    final approval = await showDialog<Object>(
      context: context,
      builder: (_) => PageEvidenceDialog(
        image: widget.evidence!.image,
        snapshot: _snapshot,
        guided: _streamlined,
        initiallyCompleted: _guidedReviewCompleted,
      ),
    );
    if (!mounted || approval == null) return;
    if (_streamlined) {
      if (approval == true) setState(() => _guidedReviewCompleted = true);
    } else if (approval is PageEvidenceApproval &&
        approval.validFor(_snapshot)) {
      setState(() {
        _pageApproval = approval;
        _reviewed = false;
      });
    }
  }

  Future<void> _reviewGeometry(int index) async {
    if (!_hasLayoutContext) return;
    final audit = _evidenceAudit!;
    final note = await showDialog<String>(
      context: context,
      builder: (_) => GeometryEvidenceDialog(
        image: widget.evidence!.image,
        contextData: _draft!.parseContext!,
        finding: _findings[index],
        allowed: audit.resolvableGeometry.contains(index),
        blockers: audit.blockers,
        initialNote: _findingNotes[index] ?? '',
      ),
    );
    if (!mounted ||
        note == null ||
        !_evidenceAudit!.resolvableGeometry.contains(index)) {
      return;
    }
    setState(() {
      _findingNotes[index] = note;
      _geometryApprovals[index] = _snapshot;
      _resolvedFindings.add(index);
      _reviewed = false;
    });
  }

  void _addRemovedSourceReviews(_RowFields row) {
    if (!_sourceRows.contains(row)) return;
    for (final word in row.evidence) {
      if (!_findings.any(
        (f) =>
            [
              ParseIssue.removedSource,
              ParseIssue.geometrySource,
              ParseIssue.unassignedSource,
            ].contains(f.issue) &&
            f.words.length == 1 &&
            identical(f.words.single, word),
      )) {
        _findings.add(
          ParseFinding(
            ParseIssue.removedSource,
            scope: FindingScope.item,
            words: [word],
          ),
        );
      }
    }
  }

  bool get _hasLayoutContext {
    final data = _draft?.parseContext;
    final image = widget.evidence?.isDisposed == false
        ? widget.evidence!.image
        : null;
    return data != null &&
        image != null &&
        data.page.width == image.width &&
        data.page.height == image.height;
  }

  void _resetRowComparisons() {
    _invalidatePageEvidence();
    for (final row in _rows) {
      row.imageCompared = false;
    }
  }

  Future<void> _inspectLayout([List<OcrWord> highlights = const []]) async {
    if (!_hasLayoutContext) return;
    final fresh = await showDialog<ReceiptDraft>(
      context: context,
      builder: (_) => LayoutReviewDialog(
        contextData: _draft!.parseContext!,
        image: widget.evidence!.image,
        highlights: highlights,
      ),
    );
    if (!mounted || fresh == null) return;
    final evidence = widget.evidence!.clone();
    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => widget._initial == null
              ? ReviewPage(
                  draft: fresh,
                  evidence: evidence,
                  store: widget.store,
                )
              : ReviewPage.correction(
                  draft: fresh,
                  evidence: evidence,
                  store: widget.store!,
                  receipt: widget._initial!,
                ),
        ),
      );
      if (saved == true && mounted) Navigator.pop(context, true);
    } finally {
      evidence.dispose();
    }
  }

  bool _isRelationship(ParseFinding finding) =>
      finding.issue == ParseIssue.quantityWithoutProduct ||
      finding.discountKind != null;

  _RowFields? _relationshipTarget(RelationshipDecision decision) {
    for (final row in _rows) {
      if (identical(row, decision.target)) return row;
    }
    return null;
  }

  List<OcrWord> _rowEvidence(_RowFields row) => [
    ...row.evidence,
    for (final entry in _relationships.entries)
      if (identical(entry.value.target, row)) ..._findings[entry.key].words,
    for (final entry in _rowDecisions.entries)
      if (identical(entry.value.target, row)) ..._findings[entry.key].words,
  ];

  _RowFields? _rowDecisionTarget(RowEvidenceDecision decision) {
    for (final row in _rows) {
      if (identical(row, decision.target)) return row;
    }
    return null;
  }

  Future<void> _reviewUnparsedRow(int index) async {
    final decision = await showDialog<RowEvidenceDecision>(
      context: context,
      builder: (_) => RowEvidenceDialog(
        finding: _findings[index],
        image: widget.evidence?.image,
        targets: [
          for (var i = 0; i < _rows.length; i++)
            RelationshipTarget(_rows[i], _rows[i].input, i + 1),
        ],
        initial: _rowDecisions[index],
      ),
    );
    if (!mounted || decision == null) return;
    var target = _rowDecisionTarget(decision);
    final created = decision.newRow;
    if (created != null) {
      target = _RowFields()
        ..name.text = created.name
        ..amount.text = created.amount
        ..kind = created.kind;
    }
    if ((decision.kind == RowEvidenceKind.financialRow ||
            decision.kind == RowEvidenceKind.description ||
            decision.kind == RowEvidenceKind.duplicateOcr) &&
        target == null) {
      return;
    }
    setState(() {
      if (created != null) {
        _rows.add(target!);
        _resolvedFindings.clear();
        _resetRowComparisons();
      }
      final previous = _rowDecisions[index];
      _invalidatePageEvidence();
      if (previous != null) _rowDecisionTarget(previous)?.imageCompared = false;
      target?.imageCompared = false;
      _rowDecisions[index] = RowEvidenceDecision(
        decision.kind,
        target,
        decision.note,
        createdTarget:
            created != null ||
            (_rowDecisions[index]?.createdTarget == true &&
                identical(_rowDecisions[index]?.target, target)),
      );
      _findingNotes[index] = decision.note;
      _resolvedFindings.add(index);
      _reviewed = false;
      _edited = true;
    });
  }

  Future<void> _reviewRelationship(int index) async {
    final finding = _findings[index];
    final decision = await showDialog<RelationshipDecision>(
      context: context,
      builder: (_) => RelationshipDialog(
        finding: finding,
        image: widget.evidence?.image,
        source: _findingRow(finding)?.input,
        targets: [
          for (var i = 0; i < _rows.length; i++)
            if (_rows[i].kind == LineKind.product)
              RelationshipTarget(_rows[i], _rows[i].input, i + 1),
        ],
        initial: _relationships[index],
        previousTargetInput: _relationships[index] == null
            ? null
            : _relationshipTarget(_relationships[index]!)?.input,
        occupiedQuantityTargets: {
          for (final entry in _relationships.entries)
            if (entry.key != index &&
                entry.value.kind == ReviewRelationshipKind.quantity &&
                entry.value.target != null)
              entry.value.target!,
        },
      ),
    );
    if (!mounted || decision == null) return;
    final target = _relationshipTarget(decision);
    if (decision.kind == ReviewRelationshipKind.quantity && target == null) {
      return;
    }
    setState(() {
      if (decision.kind == ReviewRelationshipKind.quantity) {
        if (target!.quantity.text != decision.quantity ||
            target.rate.text != decision.rate ||
            target.unit != decision.unit) {
          _resolvedFindings.clear();
          _resetRowComparisons();
        }
        target.quantity.text = decision.quantity;
        target.rate.text = decision.rate;
        target.unit = decision.unit;
      }
      // Keep original rows/evidence intact; links are separate temporary state.
      final previous = _relationships[index];
      _invalidatePageEvidence();
      if (previous != null) {
        _relationshipTarget(previous)?.imageCompared = false;
      }
      target?.imageCompared = false;
      _relationships[index] = decision;
      _findingNotes[index] = decision.note;
      _resolvedFindings.add(index);
      _reviewed = false;
      _edited = true;
    });
  }

  _RowFields? _findingRow(ParseFinding finding) {
    final index = finding.rowIndex;
    if (index == null || index < 0 || index >= _sourceRows.length) return null;
    final row = _sourceRows[index];
    return _rows.contains(row) ? row : null;
  }

  bool _canResolve(ParseFinding finding) => canResolveFinding(
    finding,
    row: _findingRow(finding)?.input,
    total: _total.text,
    nameHandled: _draft!.wrappedNames.asMap().entries.any(
      (entry) =>
          entry.value.rowIndex == finding.rowIndex &&
          _handledNames.contains(entry.key),
    ),
  );

  Future<void> _reviewFinding(int index, String message) async {
    final finding = _findings[index];
    if ((finding.issue == ParseIssue.ambiguousGeometry ||
            finding.issue == ParseIssue.skewAdjusted) &&
        _hasLayoutContext) {
      await _inspectLayout(finding.words);
      return;
    }
    if (isUnparsedItemFinding(finding)) {
      await _reviewUnparsedRow(index);
      return;
    }
    if (_isRelationship(finding)) {
      await _reviewRelationship(index);
      return;
    }
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _FindingDialog(
        finding: finding,
        image: widget.evidence?.image,
        message: message,
        initialNote: _findingNotes[index] ?? '',
        allowed: _canResolve(finding),
      ),
    );
    if (mounted && note != null) {
      setState(() {
        _findingNotes[index] = note;
        _resolvedFindings.add(index);
        _reviewed = false;
      });
    }
  }

  List<_RowFields> _sourceRows = [];
  ReceiptDraft? _draft;
  OcrPage? _ocr;
  ReceiptRecognition? _recognition;
  bool _recognizing = false;
  bool _ocrFailed = false;
  bool _edited = false;
  double _itemTop = .2, _priceLeft = .75;

  Future<void> _recognize() async {
    if (_recognizing || _edited || _draft != null) return;
    setState(() {
      _recognizing = true;
      _ocrFailed = false;
    });
    try {
      final custom = widget.recognizer;
      final Future<OcrPage> result;
      if (custom == null) {
        final request = ReceiptRecognition(widget.evidence!);
        _recognition = request;
        result = request.result;
      } else {
        result = custom(widget.evidence!);
      }
      final page = await result;
      if (!mounted) return;
      final proposal = proposeLayout(page);
      setState(() {
        _ocr = page;
        if (proposal.available) {
          _itemTop = proposal.itemTop! / page.height;
          _priceLeft = proposal.priceColumnLeft! / page.width;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _ocrFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _recognizing = false;
        });
      }
    }
  }

  void _applyLayout() {
    if (_edited || _draft != null || _ocr == null) return;
    final draft = parseReceipt(
      _ocr!,
      itemTop: _itemTop * _ocr!.height,
      priceColumnLeft: _priceLeft * _ocr!.width,
    );
    final oldRows = List.of(_rows);
    setState(() {
      _rows.clear();
      _seed(draft);
      _reviewed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in oldRows) {
        row.dispose();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadBranches();
    if (widget.draft != null) {
      _rows.single.dispose();
      _rows.clear();
      _seed(widget.draft!);
    }
  }

  void _seed(ReceiptDraft draft) {
    _draft = draft;
    _findings = List.of(reviewFindingsForDraft(draft));
    if (draft.parseContext case final data?) {
      _ocr = data.page;
      _itemTop = data.itemTop / data.page.height;
      _priceLeft = data.priceColumnLeft / data.page.width;
    }
    for (final row in draft.rows) {
      _rows.add(
        _RowFields()
          ..name.text = row.name
          ..amount.text = formatCents(row.cents)
          ..kind = row.kind
          ..quantity.text = row.quantity == null
              ? ''
              : formatFixed(row.quantity!.value, row.quantity!.scale)
          ..unit = row.quantity?.unit ?? QuantityUnit.unknown
          ..rate.text = row.rateMicros == null
              ? ''
              : formatFixed(row.rateMicros!, 6)
          ..evidence = _rows.length < draft.rowEvidence.length
              ? draft.rowEvidence[_rows.length]
              : const [],
      );
    }
    _total.text = draft.printedTotal == null
        ? ''
        : formatCents(draft.printedTotal!);
    final date = draft.date.printed;
    if (date != null) {
      _date.text =
          '${date.day}.${date.month}.${date.year}'
          '${date.hour == null ? '' : ' ${date.hour!.toString().padLeft(2, '0')}:${date.minute!.toString().padLeft(2, '0')}'}'
          '${date.second == null ? '' : ':${date.second!.toString().padLeft(2, '0')}'}';
    }
    _sourceRows = List.of(_rows);
    _recommendBranch();
  }

  @override
  void dispose() {
    _recognition?.cancel();
    widget.evidence?.dispose();
    _reviewScroll.dispose();
    _branch.dispose();
    _date.dispose();
    _total.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _edit([String? _]) => setState(() {
    _savePreparationFailed = false;
    for (final row in _rows) {
      if (row.kind != LineKind.product ||
          row.name.text.trim() != row.productName ||
          row.product?.storeId.value != _branchChoice) {
        row.product = null;
      }
    }
    _reviewed = false;
    _edited = true;
    _resolvedFindings.clear();
    _resetRowComparisons();
  });

  void _showEvidence(_RowFields row) {
    _showEvidenceWords(_rowEvidence(row));
  }

  void _showEvidenceWords(List<OcrWord> words) {
    final s = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.rowEvidence),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.rowEvidenceHint),
                if (widget.evidence != null)
                  SizedBox(
                    height: 240,
                    width: 600,
                    child: CustomPaint(
                      key: const Key('row-evidence-crop'),
                      painter: ReceiptEvidencePainter(
                        widget.evidence!.image,
                        words,
                      ),
                    ),
                  ),
                SelectableText(words.map((word) => word.text).join(' ')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.closeEvidence),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final audit = _evidenceAudit;
    final validation = ReviewValidation(
      branch: _branch.text,
      dateText: _date.text,
      totalText: _total.text,
      branchConfirmed: _branchIsConfirmed,
      reviewed: _streamlined || _reviewed,
      hasUnresolvedParserIssues: _draft != null
          ? !(_streamlined
                ? (audit?.automaticReady ?? false)
                : (audit?.ready ?? false))
          : _ocr != null,
      rows: [for (final row in _rows) row.input],
    );
    final kinds = {
      LineKind.product: s.productKind,
      LineKind.discount: s.discountKind,
      LineKind.deposit: s.depositKind,
      LineKind.adjustment: s.adjustmentKind,
    };
    String issueText(ParseIssue issue) => switch (issue) {
      ParseIssue.missingTotal ||
      ParseIssue.ambiguousTotal ||
      ParseIssue.totalLabelNeedsReview => s.ocrTotalIssue,
      ParseIssue.ambiguousGeometry ||
      ParseIssue.skewAdjusted => s.ocrLayoutIssue,
      ParseIssue.quantityWithoutProduct ||
      ParseIssue.quantityMismatch => s.quantityReviewPending,
      ParseIssue.discountNeedsReview => s.ocrDiscountIssue,
      _ => s.ocrRowIssue,
    };
    String findingText(ParseFinding finding) =>
        finding.scope == FindingScope.total
        ? s.ocrTotalIssue
        : issueText(finding.issue);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    Widget preview() => Column(
      children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(s.imageEvidenceHint),
          ),
        Expanded(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: widget.evidence!.image.width.toDouble(),
                  height: widget.evidence!.image.height.toDouble(),
                  child: Stack(
                    children: [
                      RawImage(
                        key: const Key('receipt-evidence'),
                        image: widget.evidence!.image,
                        fit: BoxFit.contain,
                      ),
                      if (_ocr != null && _draft == null) ...[
                        Positioned(
                          top: _itemTop * widget.evidence!.image.height,
                          left: 0,
                          right: 0,
                          child: Container(height: 4, color: Colors.red),
                        ),
                        Positioned(
                          left: _priceLeft * widget.evidence!.image.width,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 4, color: Colors.blue),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.reviewTitle)),
      body: SafeArea(
        child: Row(
          children: [
            if (wide && widget.evidence != null) Expanded(child: preview()),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    controller: _reviewScroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        widget.store == null
                            ? s.reviewNotice
                            : s.ocrQuickReviewNotice,
                      ),
                      if (widget.evidence != null && !wide) ...[
                        Text(s.imageEvidenceHint),
                        SizedBox(height: 360, child: preview()),
                      ],
                      if (widget.evidence != null &&
                          (supportsReceiptOcr ||
                              widget.recognizer != null)) ...[
                        Text(s.ocrExperiment),
                        if (_draft == null && _ocr == null)
                          OutlinedButton(
                            key: const Key('recognize'),
                            onPressed: _recognizing || _edited
                                ? null
                                : _recognize,
                            child: Text(
                              _recognizing ? s.ocrLoading : s.ocrRecognize,
                            ),
                          ),
                        if (_ocrFailed) Text(s.ocrFailure),
                        if (_edited && _draft == null) Text(s.ocrEditsKept),
                        if (_ocr != null && _draft == null && !_edited) ...[
                          Text(
                            proposeLayout(_ocr!).available
                                ? s.ocrLayoutProposal
                                : s.ocrLayoutManual,
                          ),
                          Text(s.ocrItemTop),
                          Slider(
                            key: const Key('ocr-layout-item-top'),
                            value: _itemTop.clamp(0, .99),
                            min: 0,
                            max: .99,
                            onChanged: (v) => setState(() {
                              _itemTop = v;
                            }),
                          ),
                          Text(s.ocrPriceLeft),
                          Slider(
                            key: const Key('ocr-layout-price-left'),
                            value: _priceLeft.clamp(.01, .99),
                            min: .01,
                            max: .99,
                            onChanged: (v) => setState(() {
                              _priceLeft = v;
                            }),
                          ),
                          OutlinedButton(
                            key: const Key('ocr-use-layout'),
                            onPressed: _applyLayout,
                            child: Text(s.ocrUseLayout),
                          ),
                        ],
                        if (_ocr != null)
                          ExpansionTile(
                            title: Text(s.ocrSourceWords),
                            children: [
                              for (final word in _ocr!.words)
                                ListTile(
                                  title: Text(word.text),
                                  subtitle: Text(
                                    'x ${word.box.left.round()}–${word.box.right.round()}, y ${word.box.top.round()}–${word.box.bottom.round()}',
                                  ),
                                ),
                            ],
                          ),
                      ],
                      if (_draft case final draft?) ...[
                        const SizedBox(height: 16),
                        Text(
                          _streamlined
                              ? s.ocrQuickDraftNotice
                              : s.ocrDraftNotice,
                          key: const Key('ocr-draft-blocked'),
                        ),
                        Text(
                          s.ocrIssuesPresent(
                            _findings.length - _resolvedFindings.length,
                          ),
                        ),
                        if (!_streamlined)
                          Text(
                            s.rowImageProgress(
                              _rows.where((row) => row.imageCompared).length,
                              _rows.length,
                            ),
                            key: const Key('row-image-progress'),
                          ),
                        if (_hasLayoutContext)
                          OutlinedButton(
                            key: const Key('inspect-layout'),
                            onPressed: () => _inspectLayout(),
                            child: Text(s.layoutReviewTitle),
                          ),
                        for (var f = 0; f < _findings.length; f++)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(findingText(_findings[f])),
                                  if (_findings[f].rowIndex != null)
                                    Text(
                                      _findingRow(_findings[f])?.name.text ??
                                          s.findingRowRemoved,
                                    ),
                                  Text(
                                    _resolvedFindings.contains(f)
                                        ? s.findingResolved
                                        : s.findingOpen,
                                  ),
                                  if (_findingNotes[f] != null)
                                    Text(_findingNotes[f]!),
                                  if (_rowDecisions[f]
                                      case final decision?) ...[
                                    Text(
                                      rowEvidenceKindLabel(s, decision.kind),
                                    ),
                                    if (decision.target != null)
                                      Text(
                                        _rowDecisionTarget(decision)
                                                ?.name
                                                .text ??
                                            s.findingRowRemoved,
                                      ),
                                  ],
                                  if (_relationships[f]
                                      case final relation?) ...[
                                    Text(switch (relation.kind) {
                                      ReviewRelationshipKind.quantity =>
                                        s.linkQuantityTitle,
                                      ReviewRelationshipKind.explanatoryPrice =>
                                        s.relationshipExplanatory,
                                      ReviewRelationshipKind.productDiscount =>
                                        s.relationshipProduct,
                                      ReviewRelationshipKind.receiptDiscount =>
                                        s.relationshipReceipt,
                                    }),
                                    if (relation.target != null)
                                      Text(
                                        _relationshipTarget(relation)
                                                ?.name
                                                .text ??
                                            s.findingRowRemoved,
                                      ),
                                  ],
                                  TextButton(
                                    key: ValueKey('finding-$f'),
                                    onPressed: () => _reviewFinding(
                                      f,
                                      findingText(_findings[f]),
                                    ),
                                    child: Text(s.reviewFinding),
                                  ),
                                  if (_hasLayoutContext &&
                                      isGeometryFinding(_findings[f]))
                                    TextButton(
                                      key: ValueKey('geometry-review-$f'),
                                      onPressed: () => _reviewGeometry(f),
                                      child: Text(s.geometryEvidenceTitle),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        for (final note in draft.notes) Text(note),
                        if (draft.evidenceCoverage case final coverage?)
                          ExpansionTile(
                            key: const Key('evidence-coverage'),
                            title: Text(s.coverageTitle),
                            subtitle: Text(
                              s.coverageSummary(
                                coverage.sourceWords.length,
                                coverage.unassignedWords.length,
                              ),
                            ),
                            children: [
                              Text(s.coverageHint),
                              Text(
                                s.coverageReviewRemaining(
                                  unreviewedOmissions(
                                    coverage,
                                    _findings,
                                    _resolvedFindings,
                                  ).length,
                                ),
                              ),
                              if (!coverage.complete) ...[
                                Text(s.coverageMissing),
                                for (final word in coverage.unassignedWords)
                                  Text(word.text),
                                if (widget.evidence != null)
                                  TextButton(
                                    onPressed: () => _showEvidenceWords(
                                      coverage.unassignedWords,
                                    ),
                                    child: Text(s.coverageShowMissing),
                                  ),
                              ],
                            ],
                          ),
                        for (var n = 0; n < draft.wrappedNames.length; n++)
                          if (!_handledNames.contains(n) &&
                              draft.wrappedNames[n].rowIndex >= 0 &&
                              draft.wrappedNames[n].rowIndex <
                                  _sourceRows.length &&
                              _rows.contains(
                                _sourceRows[draft.wrappedNames[n].rowIndex],
                              ))
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      s.proposedName(
                                        draft.wrappedNames[n].proposedName,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        _sourceRows[draft
                                                    .wrappedNames[n]
                                                    .rowIndex]
                                                .name
                                                .text =
                                            draft.wrappedNames[n].proposedName;
                                        _handledNames.add(n);
                                        _edit();
                                      },
                                      child: Text(s.acceptName),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        _handledNames.add(n);
                                        _edit();
                                      },
                                      child: Text(s.keepName),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                      const SizedBox(height: 16),
                      if (widget.store != null) ...[
                        Text(s.ocrBranchChoiceHelp),
                        if (_automaticBranchChoice != null)
                          Text(
                            s.ocrBranchAutomaticallySelected,
                            key: const Key('ocr-branch-auto-selected'),
                          ),
                        if (_branches != null &&
                            (_draft?.branchCandidates.isNotEmpty ?? false)) ...[
                          Text(s.ocrBranchSuggestions),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final branch in _recommendedBranches)
                                ActionChip(
                                  key: ValueKey(
                                    'ocr-branch-match-${branch.id.value}',
                                  ),
                                  label: Text(
                                    s.ocrUseExistingBranch(branch.name),
                                  ),
                                  onPressed: () =>
                                      _chooseBranch(branch.id.value),
                                ),
                              for (final name in {
                                for (final candidate
                                    in _draft!.branchCandidates)
                                  if (!_recommendedBranches.any(
                                    (b) =>
                                        normalizeReceiptNameV1(b.name) ==
                                        normalizeReceiptNameV1(candidate.name),
                                  ))
                                    candidate.name,
                              })
                                ActionChip(
                                  key: ValueKey('ocr-branch-name-$name'),
                                  label: Text(s.ocrUseBranchName(name)),
                                  onPressed: () =>
                                      _chooseBranch('new', proposedName: name),
                                ),
                            ],
                          ),
                        ],
                        if (_branches == null && !_branchLoadFailed)
                          const LinearProgressIndicator(),
                        if (_branchLoadFailed) ...[
                          Text(s.branchLoadFailed),
                          TextButton(
                            onPressed: _loadBranches,
                            child: Text(s.retryAction),
                          ),
                        ],
                        if (_branches != null)
                          DropdownButtonFormField<String>(
                            key: const Key('ocr-branch'),
                            initialValue: _branchChoice,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: InputDecoration(
                              labelText: s.ocrBranchSelectionLabel,
                            ),
                            items: [
                              for (final branch in _branches!)
                                DropdownMenuItem(
                                  value: branch.id.value,
                                  child: Text(
                                    branch.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              DropdownMenuItem(
                                value: 'new',
                                child: Text(s.newBranch),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) _chooseBranch(value);
                            },
                          ),
                        if (_branchChoice == 'new') Text(s.newBranchNotice),
                      ],
                      KeyedSubtree(
                        key: _branchAnchor,
                        child: TextField(
                          enabled:
                              !_recognizing &&
                              (widget.store == null || _branchChoice == 'new'),
                          key: const Key('branch'),
                          controller: _branch,
                          decoration: InputDecoration(
                            labelText: s.branchLabel,
                            hintText: s.ocrBranchNameHint,
                            errorText:
                                _streamlined &&
                                    _draft != null &&
                                    _selectedBranch == null
                                ? s.ocrChooseBranch
                                : null,
                            errorMaxLines: 3,
                          ),
                          onChanged: (_) {
                            _branchTouched = true;
                            _automaticBranchChoice = null;
                            _branchConfirmed = false;
                            _edit();
                          },
                        ),
                      ),
                      if (!_streamlined)
                        CheckboxListTile(
                          key: const Key('ocr-branch-confirmation'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.branchConfirmation),
                          value: _branchConfirmed,
                          onChanged: (value) => setState(() {
                            _branchConfirmed = value ?? false;
                            _invalidatePageEvidence();
                            _edited = true;
                            _reviewed = false;
                          }),
                        ),
                      KeyedSubtree(
                        key: _dateAnchor,
                        child: TextField(
                          enabled: !_recognizing,
                          key: const Key('date'),
                          controller: _date,
                          decoration: InputDecoration(
                            labelText: s.dateLabel,
                            hintText: s.dateHint,
                            errorText:
                                _streamlined &&
                                    _draft != null &&
                                    validation.date.state !=
                                        ReceiptDateState.valid
                                ? s.dateNeedsReview
                                : null,
                            errorMaxLines: 3,
                          ),
                          onChanged: _edit,
                        ),
                      ),
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: _totalAnchor,
                        child: TextField(
                          enabled: !_recognizing,
                          key: const Key('total'),
                          controller: _total,
                          decoration: InputDecoration(
                            labelText: s.totalLabel,
                            hintText: '0,00',
                            errorText:
                                _streamlined &&
                                    _draft != null &&
                                    !validation.totalsValid
                                ? (!validation.rowsValid
                                      ? s.rowsIncomplete
                                      : validation.total == null
                                      ? s.totalMissing
                                      : s.totalsDifference(
                                          formatCents(
                                            validation.totals.difference!,
                                          ),
                                        ))
                                : null,
                            errorMaxLines: 3,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          onChanged: _edit,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (widget._initial != null)
                        Text(s.ocrCorrectionMappingRequired),
                      if (widget._initial != null &&
                          widget.store is CatalogService)
                        Text(s.productOcrCorrection),
                      Text(
                        s.rowsHeading,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (var i = 0; i < _rows.length; i++)
                        Card(
                          key: _rows[i].anchor,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget._initial != null)
                                  DropdownButtonFormField<String>(
                                    key: ValueKey('ocr-row-identity-$i'),
                                    initialValue: _rows[i].savedRowChoice,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: s.ocrCorrectionRow,
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'new',
                                        child: Text(s.ocrCorrectionNewRow),
                                      ),
                                      for (final item
                                          in widget
                                              ._initial!
                                              .document
                                              .snapshot
                                              .items)
                                        if (_rows[i].savedRowChoice ==
                                                item.id.value ||
                                            !_rows.any(
                                              (row) =>
                                                  row.savedRowChoice ==
                                                  item.id.value,
                                            ))
                                          DropdownMenuItem(
                                            value: item.id.value,
                                            child: Text(
                                              _savedRowLabel(item),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                    ],
                                    onChanged: (value) {
                                      _rows[i].savedRowChoice = value;
                                      _rows[i].product = null;
                                      _edit();
                                    },
                                  ),
                                TextField(
                                  enabled: !_recognizing,
                                  key: ValueKey('row-name-$i'),
                                  controller: _rows[i].name,
                                  decoration: InputDecoration(
                                    labelText: s.rowNameLabel,
                                    errorText:
                                        _streamlined &&
                                            _rows[i].name.text.trim().isEmpty
                                        ? s.rowsIncomplete
                                        : null,
                                    errorMaxLines: 3,
                                  ),
                                  onChanged: _edit,
                                ),
                                if (_rows[i].kind == LineKind.product &&
                                    widget.store is CatalogService)
                                  ReceiptProductSelector(
                                    key: ValueKey('ocr-product-$i'),
                                    service: widget.store! as CatalogService,
                                    storeId: _branchChoice == 'new'
                                        ? null
                                        : _selectedBranch?.id,
                                    receiptName: _rows[i].name.text,
                                    link: _rows[i].product,
                                    enabled: !_recognizing,
                                    onChanged: (link) {
                                      _rows[i].product = link;
                                      _rows[i].productName = _rows[i].name.text
                                          .trim();
                                      _edit();
                                    },
                                  ),
                                TextField(
                                  enabled: !_recognizing,
                                  key: ValueKey('row-amount-$i'),
                                  controller: _rows[i].amount,
                                  decoration: InputDecoration(
                                    labelText: s.rowAmountLabel,
                                    hintText: '0,00',
                                    errorText:
                                        _streamlined &&
                                            (parseCents(_rows[i].amount.text) ==
                                                    null ||
                                                (_rows[i].kind ==
                                                        LineKind.discount &&
                                                    parseCents(
                                                          _rows[i].amount.text,
                                                        )! >=
                                                        BigInt.zero))
                                        ? s.ocrRowFieldsInvalid
                                        : null,
                                    errorMaxLines: 3,
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  onChanged: _edit,
                                ),
                                ExpansionTile(
                                  key: ValueKey('quantity-panel-$i'),
                                  title: Text(s.quantityDetails),
                                  initiallyExpanded:
                                      _rows[i].quantity.text.isNotEmpty ||
                                      _rows[i].rate.text.isNotEmpty,
                                  children: [
                                    TextField(
                                      key: ValueKey('row-quantity-$i'),
                                      controller: _rows[i].quantity,
                                      decoration: InputDecoration(
                                        labelText: s.quantityLabel,
                                        errorText:
                                            _streamlined &&
                                                _rows[i].input.quantityState !=
                                                    QuantityReviewState
                                                        .absent &&
                                                _rows[i].input.quantityState !=
                                                    QuantityReviewState.matched
                                            ? s.quantityInvalidSummary
                                            : null,
                                        errorMaxLines: 3,
                                      ),
                                      onChanged: _edit,
                                    ),
                                    TextField(
                                      key: ValueKey('row-rate-$i'),
                                      controller: _rows[i].rate,
                                      decoration: InputDecoration(
                                        labelText: s.rateLabel,
                                      ),
                                      onChanged: _edit,
                                    ),
                                    DropdownButtonFormField<QuantityUnit>(
                                      key: ValueKey('row-unit-$i'),
                                      initialValue: _rows[i].unit,
                                      decoration: InputDecoration(
                                        labelText: s.unitLabel,
                                      ),
                                      items: [
                                        for (final unit in QuantityUnit.values)
                                          DropdownMenuItem(
                                            value: unit,
                                            child: Text(switch (unit) {
                                              QuantityUnit.unknown =>
                                                s.unitUnknown,
                                              QuantityUnit.piece => 'kpl',
                                              QuantityUnit.kg => 'kg',
                                              QuantityUnit.litre => 'l',
                                            }),
                                          ),
                                      ],
                                      onChanged: (unit) {
                                        if (unit != null) {
                                          _rows[i].unit = unit;
                                          _edit();
                                        }
                                      },
                                    ),
                                    Text(switch (_rows[i].input.quantityState) {
                                      QuantityReviewState.absent =>
                                        s.quantityAbsent,
                                      QuantityReviewState.invalid =>
                                        s.quantityInvalid,
                                      QuantityReviewState.matched =>
                                        s.quantityMatched,
                                      QuantityReviewState.mismatched =>
                                        s.quantityMismatch,
                                    }),
                                  ],
                                ),
                                if (_rowEvidence(_rows[i]).isNotEmpty)
                                  OutlinedButton(
                                    key: ValueKey('row-evidence-$i'),
                                    onPressed: () => _showEvidence(_rows[i]),
                                    child: Text(s.rowEvidence),
                                  ),
                                if (!_streamlined &&
                                    _draft != null &&
                                    widget.evidence != null)
                                  CheckboxListTile(
                                    key: ValueKey('row-image-compared-$i'),
                                    title: Text(s.rowImageCompared),
                                    value: _rows[i].imageCompared,
                                    onChanged: (value) => setState(() {
                                      _rows[i].imageCompared = value ?? false;
                                      _invalidatePageEvidence();
                                      _reviewed = false;
                                    }),
                                  ),
                                DropdownButtonFormField<LineKind>(
                                  initialValue: _rows[i].kind,
                                  decoration: InputDecoration(
                                    labelText: s.rowKindLabel,
                                  ),
                                  isExpanded: true,
                                  items: [
                                    for (final kind in kinds.entries)
                                      DropdownMenuItem(
                                        value: kind.key,
                                        child: Text(kind.value),
                                      ),
                                  ],
                                  onChanged: (kind) {
                                    if (kind != null) {
                                      final changed = _rows[i];
                                      changed.kind = kind;
                                      changed.depositParent = null;
                                      changed.standaloneDeposit = false;
                                      for (final row in _rows) {
                                        if (identical(
                                          row.depositParent,
                                          changed,
                                        )) {
                                          row.depositParent = null;
                                        }
                                      }
                                      _edit();
                                    }
                                  },
                                ),
                                if (widget.store != null &&
                                    _rows[i].kind == LineKind.adjustment)
                                  TextField(
                                    key: ValueKey('ocr-adjustment-reason-$i'),
                                    controller: _rows[i].reason,
                                    decoration: InputDecoration(
                                      labelText: s.adjustmentReason,
                                      errorText:
                                          _rows[i].reason.text.trim().isEmpty
                                          ? s.adjustmentReasonRequired
                                          : null,
                                      errorMaxLines: 3,
                                    ),
                                    onChanged: _edit,
                                  ),
                                if (widget.store != null &&
                                    _rows[i].kind == LineKind.deposit)
                                  DropdownButtonFormField<Object>(
                                    key: ValueKey(
                                      'ocr-deposit-$i-${_rows[i].depositParent}-${_rows[i].standaloneDeposit}',
                                    ),
                                    initialValue: _rows[i].standaloneDeposit
                                        ? 'standalone'
                                        : _rows.contains(
                                                _rows[i].depositParent,
                                              ) &&
                                              (_rows[i].depositParent
                                                          as _RowFields?)
                                                      ?.kind ==
                                                  LineKind.product
                                        ? _rows[i].depositParent
                                        : null,
                                    isExpanded: true,
                                    itemHeight: null,
                                    decoration: InputDecoration(
                                      labelText: s.manualRelationship,
                                      errorText:
                                          !_rows[i].standaloneDeposit &&
                                              _rows[i].depositParent == null
                                          ? s.ocrChooseDeposit
                                          : null,
                                      errorMaxLines: 3,
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'standalone',
                                        child: Text(s.standaloneDeposit),
                                      ),
                                      for (final product in _rows.where(
                                        (r) => r.kind == LineKind.product,
                                      ))
                                        DropdownMenuItem(
                                          value: product,
                                          child: Text(
                                            product.name.text,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      _rows[i].standaloneDeposit =
                                          value == 'standalone';
                                      _rows[i].depositParent =
                                          value == 'standalone' ? null : value;
                                      _edit();
                                    },
                                  ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    key: ValueKey('remove-row-$i'),
                                    onPressed: () {
                                      final removed = _rows.removeAt(i);
                                      for (final row in _rows) {
                                        if (identical(
                                          row.depositParent,
                                          removed,
                                        )) {
                                          row.depositParent = null;
                                        }
                                      }
                                      _addRemovedSourceReviews(removed);
                                      _edit();
                                      // Wait until its text fields have detached their listeners.
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => removed.dispose(),
                                          );
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(s.removeRow),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _rows.add(_RowFields());
                          _edit();
                        },
                        icon: const Icon(Icons.add),
                        label: Text(s.addRow),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.validationHeading,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        validation.branchValid
                            ? s.branchReady
                            : s.branchNeedsReview,
                      ),
                      Text(
                        validation.date.state == ReceiptDateState.valid
                            ? s.dateReady
                            : s.dateNeedsReview,
                      ),
                      if (validation.date.state == ReceiptDateState.ambiguous ||
                          validation.date.state ==
                              ReceiptDateState.nonexistent ||
                          validation.date.state ==
                              ReceiptDateState.unsupportedTimezone)
                        Text(s.timeNeedsReview),
                      Text(
                        !validation.rowsValid
                            ? s.rowsIncomplete
                            : validation.totalsValid
                            ? s.totalsMatch
                            : validation.total == null
                            ? s.totalMissing
                            : s.totalsDifference(
                                formatCents(validation.totals.difference!),
                              ),
                      ),
                      if (!validation.quantitiesValid)
                        Text(s.quantityInvalidSummary),
                      if (validation.positiveDiscount)
                        Text(s.discountSignWarning),
                      if (_streamlined && audit != null) ...[
                        Text(
                          audit.automaticReady && _mappingReady && _detailsReady
                              ? s.ocrAutomaticChecksPassed
                              : s.ocrResolveBeforeSaving,
                          key: const Key('ocr-automatic-status'),
                          style: TextStyle(
                            color:
                                audit.automaticReady &&
                                    _mappingReady &&
                                    _detailsReady
                                ? null
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        if (_selectedBranch == null)
                          TextButton(
                            key: const Key('ocr-branch-review-needed'),
                            onPressed: () => _showField(_branchAnchor),
                            child: Text(s.ocrChooseBranch),
                          ),
                        if (validation.date.state != ReceiptDateState.valid)
                          TextButton(
                            key: const Key('ocr-jump-date'),
                            onPressed: () => _showField(_dateAnchor),
                            child: Text(s.dateNeedsReview),
                          ),
                        if (!validation.totalsValid)
                          TextButton(
                            key: const Key('ocr-jump-total'),
                            onPressed: () => _showField(_totalAnchor),
                            child: Text(s.ocrCheckTotal),
                          ),
                        if (!_mappingReady)
                          Text(s.ocrCorrectionMappingRequired),
                        for (var i = 0; i < _rows.length; i++)
                          if (_rows[i].name.text.trim().isEmpty ||
                              parseCents(_rows[i].amount.text) == null ||
                              (_rows[i].input.quantityState !=
                                      QuantityReviewState.absent &&
                                  _rows[i].input.quantityState !=
                                      QuantityReviewState.matched) ||
                              (_rows[i].kind == LineKind.adjustment &&
                                  _rows[i].reason.text.trim().isEmpty) ||
                              (_rows[i].kind == LineKind.deposit &&
                                  !_rows[i].standaloneDeposit &&
                                  _rows[i].depositParent == null))
                            TextButton(
                              key: ValueKey('ocr-jump-row-$i'),
                              onPressed: () => _showField(_rows[i].anchor),
                              child: Text(
                                '${i + 1}. ${_rows[i].name.text}: ${s.ocrRowFieldsInvalid}',
                              ),
                            ),
                        for (final blocker in audit.blockers.where(
                          (b) => b != OcrEvidenceBlocker.receiptApproval,
                        ))
                          Text(
                            blocker == OcrEvidenceBlocker.rowReview
                                ? s.ocrRowFieldsInvalid
                                : evidenceBlockerLabel(s, blocker),
                            key: ValueKey('ocr-blocker-${blocker.name}'),
                          ),
                        if (_hasLayoutContext)
                          OutlinedButton(
                            key: const Key('review-page-evidence'),
                            onPressed: _saving ? null : _reviewPageEvidence,
                            child: Text(s.ocrGuidedReview),
                          ),
                        if (_guidedReviewCompleted)
                          Text(
                            s.ocrGuidedCompleted,
                            key: const Key('ocr-guided-completed'),
                          ),
                        Text(s.ocrAcceptNotice),
                      ],
                      if (!_streamlined) ...[
                        if (audit != null) ...[
                          Text(s.evidenceAuditTitle),
                          if (!audit.ready) ...[
                            Text(
                              s.ocrFinalReviewPending,
                              key: const Key('ocr-final-review-pending'),
                            ),
                            if (_branch.text.trim().isEmpty ||
                                !_branchConfirmed ||
                                (widget.store != null &&
                                    _selectedBranch == null))
                              Text(
                                s.ocrBranchReviewNeeded,
                                key: const Key('ocr-branch-review-needed'),
                              ),
                          ],
                          for (final blocker in audit.blockers)
                            Text(switch (blocker) {
                              OcrEvidenceBlocker.rowReview =>
                                s.ocrRowsReviewNeeded,
                              OcrEvidenceBlocker.pageReview =>
                                s.ocrPageReviewNeeded,
                              _ => evidenceBlockerLabel(s, blocker),
                            }, key: ValueKey('ocr-blocker-${blocker.name}')),
                          if (_hasLayoutContext)
                            OutlinedButton(
                              key: const Key('review-page-evidence'),
                              onPressed: _reviewPageEvidence,
                              child: Text(s.pageEvidenceTitle),
                            ),
                          if (_pageApproval?.validFor(_snapshot) ?? false)
                            Text(s.pageEvidenceReady),
                          if (audit.ready)
                            Text(
                              s.evidenceAuditReady,
                              key: const Key('evidence-audit-ready'),
                            ),
                        ],
                        CheckboxListTile(
                          key: const Key('review-confirmation'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.reviewConfirmation),
                          value: _reviewed,
                          onChanged: audit != null && !audit.ready
                              ? null
                              : (value) => setState(() {
                                  _reviewed = value ?? false;
                                }),
                        ),
                      ],
                      if (widget.store != null && _draft != null) ...[
                        if (_savePreparationFailed)
                          Text(
                            s.ocrSaveDetailsInvalid,
                            key: const Key('ocr-save-preparation-error'),
                          ),
                        FilledButton(
                          key: const Key('ocr-save'),
                          onPressed:
                              !_saving &&
                                  validation.complete &&
                                  _selectedBranch != null &&
                                  _mappingReady &&
                                  _detailsReady
                              ? _saveOcr
                              : null,
                          child: Text(
                            widget._initial == null
                                ? s.ocrAcceptAndSave
                                : s.saveCorrection,
                          ),
                        ),
                      ],
                      if (validation.complete && widget.store == null)
                        Text(
                          s.reviewComplete,
                          key: const Key('review-complete'),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingDialog extends StatefulWidget {
  const _FindingDialog({
    required this.finding,
    required this.image,
    required this.message,
    required this.initialNote,
    required this.allowed,
  });
  final ParseFinding finding;
  final ui.Image? image;
  final String message, initialNote;
  final bool allowed;
  @override
  State<_FindingDialog> createState() => _FindingDialogState();
}

class _FindingDialogState extends State<_FindingDialog> {
  late final _note = TextEditingController(text: widget.initialNote);
  bool _compared = false;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.message),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.image != null && widget.finding.words.isNotEmpty)
                SizedBox(
                  height: 220,
                  width: 600,
                  child: CustomPaint(
                    painter: ReceiptEvidencePainter(
                      widget.image!,
                      widget.finding.words,
                    ),
                  ),
                ),
              SelectableText(widget.finding.words.map((w) => w.text).join(' ')),
              Text(s.findingCompareHint),
              if (!widget.allowed) Text(s.findingPrerequisite),
              if (widget.image == null) Text(s.findingImageRequired),
              TextField(
                key: const Key('finding-note'),
                controller: _note,
                decoration: InputDecoration(labelText: s.findingNote),
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                key: const Key('finding-compared'),
                title: Text(s.findingCompared),
                value: _compared,
                onChanged: (value) => setState(() {
                  _compared = value ?? false;
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.closeEvidence),
        ),
        FilledButton(
          key: const Key('resolve-finding'),
          onPressed:
              widget.image != null &&
                  widget.allowed &&
                  _compared &&
                  _note.text.trim().isNotEmpty
              ? () => Navigator.pop(context, _note.text.trim())
              : null,
          child: Text(s.resolveFinding),
        ),
      ],
    );
  }
}
