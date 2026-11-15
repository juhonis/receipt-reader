import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_import.dart';
import 'receipt_ocr.dart';

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
  });

  void _showEvidence(_RowFields row) {
    final words = row.evidence;
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
                      painter: _EvidenceCrop(widget.evidence!.image, words),
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
      // row relationships are implemented. Manual review remains available.
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
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    Widget preview() => Column(
      children: [
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
                      if (widget.evidence != null && !wide)
                        SizedBox(height: 360, child: preview()),
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
                        Text(s.ocrIssuesPresent(draft.issues.length)),
                        for (final message
                            in draft.issues.map(issueText).toSet())
                          Text(message),
                        for (final note in draft.notes) Text(note),
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
                                if (_rows[i].evidence.isNotEmpty)
                                  OutlinedButton(
                                    key: ValueKey('row-evidence-$i'),
                                    onPressed: () => _showEvidence(_rows[i]),
                                    child: Text(s.rowEvidence),
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

class _EvidenceCrop extends CustomPainter {
  _EvidenceCrop(this.image, this.words);
  final ui.Image image;
  final List<OcrWord> words;
  @override
  void paint(Canvas canvas, Size size) {
    var left = words.first.box.left, top = words.first.box.top;
    var right = words.first.box.right, bottom = words.first.box.bottom;
    for (final word in words.skip(1)) {
      if (word.box.left < left) left = word.box.left;
      if (word.box.top < top) top = word.box.top;
      if (word.box.right > right) right = word.box.right;
      if (word.box.bottom > bottom) bottom = word.box.bottom;
    }
    final source = Rect.fromLTRB(
      (left - 12).clamp(0, image.width).toDouble(),
      (top - 12).clamp(0, image.height).toDouble(),
      (right + 12).clamp(0, image.width).toDouble(),
      (bottom + 12).clamp(0, image.height).toDouble(),
    );
    if (source.isEmpty) return;
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(image, source, destination, Paint());
  }

  @override
  bool shouldRepaint(_EvidenceCrop oldDelegate) =>
      image != oldDelegate.image || words != oldDelegate.words;
}
