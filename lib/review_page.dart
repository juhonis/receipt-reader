import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_import.dart';
import 'receipt_ocr.dart';
import 'receipt_evidence_painter.dart';
import 'relationship_dialog.dart';
import 'row_evidence_dialog.dart';
import 'layout_review_dialog.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.draft, this.evidence, this.recognizer});
  final Future<OcrPage> Function(ReceiptEvidence)? recognizer;
  final ReceiptDraft? draft;
  final ReceiptEvidence? evidence;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _RowFields {
  final name = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final rate = TextEditingController();
  QuantityUnit unit = QuantityUnit.unknown;
  bool imageCompared = false;
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
  }
}

class _ReviewPageState extends State<ReviewPage> {
  final _branch = TextEditingController();
  final _date = TextEditingController();
  final _total = TextEditingController();
  final _rows = [_RowFields()];
  bool _branchConfirmed = false;
  bool _reviewed = false;
  final _handledNames = <int>{};
  final _resolvedFindings = <int>{};
  final _findingNotes = <int, String>{};
  final _relationships = <int, RelationshipDecision>{};
  final _rowDecisions = <int, RowEvidenceDecision>{};
  List<ParseFinding> _findings = [];

  bool get _hasLayoutContext {
    final data = _draft?.parseContext;
    final image = widget.evidence?.image;
    return data != null &&
        image != null &&
        data.page.width == image.width &&
        data.page.height == image.height;
  }

  void _resetRowComparisons() {
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
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReviewPage(draft: fresh, evidence: evidence),
        ),
      );
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
            decision.kind == RowEvidenceKind.description) &&
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
      final page = await (widget.recognizer ?? recognizeReceipt)(
        widget.evidence!,
      );
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
    if (widget.draft != null) {
      _rows.single.dispose();
      _rows.clear();
      _seed(widget.draft!);
    }
  }

  void _seed(ReceiptDraft draft) {
    _draft = draft;
    _findings = reviewFindingsForDraft(draft);
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
  }

  @override
  void dispose() {
    widget.evidence?.dispose();
    _branch.dispose();
    _date.dispose();
    _total.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _edit([String? _]) => setState(() {
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
    final validation = ReviewValidation(
      branch: _branch.text,
      dateText: _date.text,
      totalText: _total.text,
      branchConfirmed: _branchConfirmed,
      reviewed: _reviewed,
      // OCR completion stays gated until evidence-based issue resolution and
      // all issue types and evidence coverage are implemented.
      hasUnresolvedParserIssues: _draft != null || _ocr != null,
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
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(s.reviewNotice),
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
                            value: _itemTop.clamp(0, .99),
                            min: 0,
                            max: .99,
                            onChanged: (v) => setState(() {
                              _itemTop = v;
                            }),
                          ),
                          Text(s.ocrPriceLeft),
                          Slider(
                            value: _priceLeft.clamp(.01, .99),
                            min: .01,
                            max: .99,
                            onChanged: (v) => setState(() {
                              _priceLeft = v;
                            }),
                          ),
                          OutlinedButton(
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
                          s.ocrDraftNotice,
                          key: const Key('ocr-draft-blocked'),
                        ),
                        Text(
                          s.ocrIssuesPresent(
                            _findings.length - _resolvedFindings.length,
                          ),
                        ),
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
                      TextField(
                        enabled: !_recognizing,
                        key: const Key('branch'),
                        controller: _branch,
                        decoration: InputDecoration(labelText: s.branchLabel),
                        onChanged: (_) {
                          _branchConfirmed = false;
                          _edit();
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.branchConfirmation),
                        value: _branchConfirmed,
                        onChanged: (value) => setState(() {
                          _branchConfirmed = value ?? false;
                          _edited = true;
                          _reviewed = false;
                        }),
                      ),
                      TextField(
                        enabled: !_recognizing,
                        key: const Key('date'),
                        controller: _date,
                        decoration: InputDecoration(
                          labelText: s.dateLabel,
                          hintText: s.dateHint,
                        ),
                        onChanged: _edit,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        enabled: !_recognizing,
                        key: const Key('total'),
                        controller: _total,
                        decoration: InputDecoration(
                          labelText: s.totalLabel,
                          hintText: '0,00',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: _edit,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        s.rowsHeading,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (var i = 0; i < _rows.length; i++)
                        Card(
                          key: ObjectKey(_rows[i]),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  enabled: !_recognizing,
                                  key: ValueKey('row-name-$i'),
                                  controller: _rows[i].name,
                                  decoration: InputDecoration(
                                    labelText: s.rowNameLabel,
                                  ),
                                  onChanged: _edit,
                                ),
                                TextField(
                                  enabled: !_recognizing,
                                  key: ValueKey('row-amount-$i'),
                                  controller: _rows[i].amount,
                                  decoration: InputDecoration(
                                    labelText: s.rowAmountLabel,
                                    hintText: '0,00',
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
                                if (_draft != null && widget.evidence != null)
                                  CheckboxListTile(
                                    key: ValueKey('row-image-compared-$i'),
                                    title: Text(s.rowImageCompared),
                                    value: _rows[i].imageCompared,
                                    onChanged: (value) => setState(() {
                                      _rows[i].imageCompared = value ?? false;
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
                                      _rows[i].kind = kind;
                                      _edit();
                                    }
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    key: ValueKey('remove-row-$i'),
                                    onPressed: () {
                                      final removed = _rows.removeAt(i);
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
                      CheckboxListTile(
                        key: const Key('review-confirmation'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.reviewConfirmation),
                        value: _reviewed,
                        onChanged: (value) => setState(() {
                          _reviewed = value ?? false;
                        }),
                      ),
                      if (validation.complete)
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
