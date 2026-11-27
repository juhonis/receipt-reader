import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_evidence_painter.dart';

class RelationshipTarget {
  const RelationshipTarget(this.id, this.input, this.position);
  final Object id;
  final ReviewRowInput input;
  final int position;
}

/// Temporary review state. Target identity survives edits and changes of position.
class RelationshipDecision {
  const RelationshipDecision(
    this.kind,
    this.target,
    this.note, {
    this.quantity = '',
    this.rate = '',
    this.unit = QuantityUnit.unknown,
  });
  final ReviewRelationshipKind kind;
  final Object? target;
  final String note, quantity, rate;
  final QuantityUnit unit;
}

class RelationshipDialog extends StatefulWidget {
  const RelationshipDialog({
    super.key,
    required this.finding,
    required this.image,
    required this.targets,
    required this.source,
    required this.occupiedQuantityTargets,
    this.previousTargetInput,
    this.initial,
    this.quick = false,
  });
  final ParseFinding finding;
  final ui.Image? image;
  final List<RelationshipTarget> targets;
  final ReviewRowInput? source;
  final Set<Object> occupiedQuantityTargets;
  final ReviewRowInput? previousTargetInput;
  final RelationshipDecision? initial;
  final bool quick;
  @override
  State<RelationshipDialog> createState() => _RelationshipDialogState();
}

class _RelationshipDialogState extends State<RelationshipDialog> {
  final _quantity = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  QuantityUnit _unit = QuantityUnit.unknown;
  ReviewRelationshipKind? _kind;
  RelationshipTarget? _target;
  bool _compared = false, _replace = false;

  bool get _isQuantity =>
      widget.finding.issue == ParseIssue.quantityWithoutProduct;
  bool get _isPosted =>
      widget.finding.discountKind == DiscountFindingKind.postedDiscount;

  @override
  void initState() {
    super.initState();
    _kind = _isQuantity
        ? ReviewRelationshipKind.quantity
        : _isPosted
        ? null
        : ReviewRelationshipKind.explanatoryPrice;
    final initial = widget.initial;
    if (initial != null) {
      _kind = initial.kind;
      _note.text = initial.note;
      for (final target in widget.targets) {
        if (identical(target.id, initial.target)) _target = target;
      }
    }
    final candidate = widget.finding.quantityCandidate;
    _quantity.text =
        (_target != null ? _target!.input.quantity : initial?.quantity) ??
        (candidate == null
            ? ''
            : formatFixed(candidate.quantity.value, candidate.quantity.scale));
    _rate.text =
        (_target != null ? _target!.input.rate : initial?.rate) ??
        (candidate == null ? '' : formatFixed(candidate.rateMicros, 6));
    _unit =
        _target?.input.unit ??
        initial?.unit ??
        candidate?.quantity.unit ??
        QuantityUnit.unknown;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final needsTarget = _kind != ReviewRelationshipKind.receiptDiscount;
    final selectedInput = _target?.input;
    final proposed = selectedInput == null
        ? null
        : ReviewRowInput(
            selectedInput.name,
            selectedInput.amount,
            selectedInput.kind,
            quantity: _quantity.text,
            rate: _rate.text,
            unit: _unit,
          );
    final replacing =
        _isQuantity &&
        selectedInput != null &&
        selectedInput.quantityState != QuantityReviewState.absent;
    final occupied =
        _isQuantity &&
        _target != null &&
        widget.occupiedQuantityTargets.contains(_target!.id);
    final movingWithValues =
        _isQuantity &&
        widget.initial != null &&
        !identical(_target?.id, widget.initial!.target) &&
        widget.previousTargetInput != null &&
        widget.previousTargetInput!.quantityState != QuantityReviewState.absent;
    final valid =
        _kind != null &&
        !occupied &&
        !movingWithValues &&
        (!needsTarget || _target != null) &&
        canResolveRelationship(
          widget.finding,
          _kind!,
          source: widget.source,
          target: _isQuantity
              ? proposed
              : needsTarget
              ? selectedInput
              : null,
        );
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(_isQuantity ? s.linkQuantityTitle : s.linkDiscountTitle),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.image != null && widget.finding.words.isNotEmpty)
                SizedBox(
                  height: 220,
                  child: CustomPaint(
                    painter: ReceiptEvidencePainter(
                      widget.image!,
                      widget.finding.words,
                    ),
                  ),
                ),
              SelectableText(widget.finding.words.map((w) => w.text).join(' ')),
              if (widget.source case final source?)
                Text('${source.name}: ${source.amount}'),
              Text(
                _isQuantity
                    ? s.linkQuantityHint
                    : _isPosted
                    ? s.linkPostedDiscountHint
                    : s.linkExplanatoryHint,
              ),
              if (_isPosted)
                DropdownButtonFormField<ReviewRelationshipKind>(
                  key: const Key('relationship-kind'),
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: s.relationshipScope),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: ReviewRelationshipKind.productDiscount,
                      child: Text(s.relationshipProduct),
                    ),
                    DropdownMenuItem(
                      value: ReviewRelationshipKind.receiptDiscount,
                      child: Text(s.relationshipReceipt),
                    ),
                  ],
                  onChanged: (kind) => setState(() {
                    _kind = kind;
                    _target = null;
                    _compared = false;
                  }),
                ),
              if (needsTarget)
                DropdownButtonFormField<RelationshipTarget>(
                  key: ValueKey('relationship-target-${_kind?.name}'),
                  initialValue: _target,
                  decoration: InputDecoration(labelText: s.relationshipTarget),
                  isExpanded: true,
                  items: [
                    for (final target in widget.targets)
                      DropdownMenuItem(
                        value: target,
                        child: Text(
                          '${target.position}. ${target.input.name} (${target.input.amount})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (target) => setState(() {
                    _target = target;
                    _replace = false;
                    _compared = false;
                  }),
                ),
              if (_isQuantity) ...[
                TextField(
                  key: const Key('relationship-quantity'),
                  controller: _quantity,
                  decoration: InputDecoration(labelText: s.quantityLabel),
                  onChanged: (_) => setState(() {
                    _compared = false;
                  }),
                ),
                TextField(
                  key: const Key('relationship-rate'),
                  controller: _rate,
                  decoration: InputDecoration(labelText: s.rateLabel),
                  onChanged: (_) => setState(() {
                    _compared = false;
                  }),
                ),
                DropdownButtonFormField<QuantityUnit>(
                  key: const Key('relationship-unit'),
                  isExpanded: true,
                  initialValue: _unit,
                  decoration: InputDecoration(labelText: s.unitLabel),
                  items: [
                    for (final unit in QuantityUnit.values)
                      DropdownMenuItem(
                        value: unit,
                        child: Text(switch (unit) {
                          QuantityUnit.unknown => s.unitUnknown,
                          QuantityUnit.piece => 'kpl',
                          QuantityUnit.kg => 'kg',
                          QuantityUnit.litre => 'l',
                        }),
                      ),
                  ],
                  onChanged: (unit) => setState(() {
                    _unit = unit ?? QuantityUnit.unknown;
                    _compared = false;
                  }),
                ),
                if (proposed != null)
                  Text(switch (proposed.quantityState) {
                    QuantityReviewState.matched => s.quantityMatched,
                    QuantityReviewState.mismatched => s.quantityMismatch,
                    _ => s.quantityInvalid,
                  }),
                if (replacing) ...[
                  Text(
                    s.relationshipCurrentQuantity(
                      selectedInput.quantity,
                      selectedInput.rate,
                    ),
                  ),
                  CheckboxListTile(
                    key: const Key('relationship-replace'),
                    title: Text(s.relationshipReplace),
                    value: _replace,
                    onChanged: (v) => setState(() {
                      _replace = v ?? false;
                    }),
                  ),
                ],
                if (occupied) Text(s.relationshipOccupied),
                if (movingWithValues) Text(s.relationshipMoveBlocked),
              ],
              if (!valid) Text(s.relationshipNeedsReview),
              if (widget.image == null) Text(s.findingImageRequired),
              TextField(
                key: const Key('relationship-note'),
                controller: _note,
                decoration: InputDecoration(labelText: s.findingNote),
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              if (!widget.quick)
                CheckboxListTile(
                  key: const Key('relationship-compared'),
                  title: Text(s.findingCompared),
                  value: _compared,
                  onChanged: (v) => setState(() {
                    _compared = v ?? false;
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
          key: const Key('confirm-relationship'),
          onPressed:
              widget.image != null &&
                  valid &&
                  (!replacing || _replace) &&
                  (widget.quick || _compared)
              ? () => Navigator.pop(
                  context,
                  RelationshipDecision(
                    _kind!,
                    needsTarget ? _target?.id : null,
                    _note.text.trim(),
                    quantity: _quantity.text.trim(),
                    rate: _rate.text.trim(),
                    unit: _unit,
                  ),
                )
              : null,
          child: Text(s.confirmRelationship),
        ),
      ],
    );
  }
}
