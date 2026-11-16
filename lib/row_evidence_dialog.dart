import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_evidence_painter.dart';
import 'relationship_dialog.dart' show RelationshipTarget;

class RowEvidenceDecision {
  const RowEvidenceDecision(
    this.kind,
    this.target,
    this.note, {
    this.newRow,
    this.createdTarget = false,
  });
  final RowEvidenceKind kind;
  final Object? target;
  final String note;
  final ReviewRowInput? newRow;
  final bool createdTarget;
}

class RowEvidenceDialog extends StatefulWidget {
  const RowEvidenceDialog({
    super.key,
    required this.finding,
    required this.image,
    required this.targets,
    this.initial,
  });
  final ParseFinding finding;
  final ui.Image? image;
  final List<RelationshipTarget> targets;
  final RowEvidenceDecision? initial;
  @override
  State<RowEvidenceDialog> createState() => _RowEvidenceDialogState();
}

class _RowEvidenceDialogState extends State<RowEvidenceDialog> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  RowEvidenceKind? _kind;
  RelationshipTarget? _target;
  LineKind _lineKind = LineKind.product;
  bool _create = false, _compared = false, _nonFinancial = false;

  bool get _needsTarget =>
      _kind == RowEvidenceKind.financialRow ||
      _kind == RowEvidenceKind.description;

  @override
  void initState() {
    super.initState();
    _kind = widget.initial?.kind;
    _note.text = widget.initial?.note ?? '';
    for (final target in widget.targets) {
      if (identical(target.id, widget.initial?.target) &&
          target.input.kind != LineKind.discount &&
          (_kind != RowEvidenceKind.description ||
              target.input.kind == LineKind.product)) {
        _target = target;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final newRow = ReviewRowInput(
      _name.text.trim(),
      _amount.text.trim(),
      _lineKind,
    );
    final input = _create ? newRow : _target?.input;
    final ownedRowExists =
        widget.initial?.createdTarget == true &&
        widget.targets.any((t) => identical(t.id, widget.initial!.target));
    final changingCreatedRow =
        ownedRowExists &&
        (_kind != RowEvidenceKind.financialRow ||
            _create ||
            !identical(_target?.id, widget.initial!.target));
    final valid =
        !changingCreatedRow &&
        _kind != null &&
        canResolveRowEvidence(
          widget.finding,
          _kind!,
          target: _needsTarget ? input : null,
        );
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(s.unparsedTitle),
      content: SizedBox(
        width: 600,
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
            Text(s.unparsedHint),
            DropdownButtonFormField<RowEvidenceKind>(
              key: const Key('row-evidence-kind'),
              initialValue: _kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.unparsedAction),
              items: [
                for (final kind in RowEvidenceKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(
                      rowEvidenceKindLabel(s, kind),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (kind) => setState(() {
                _kind = kind;
                _create = false;
                _target = null;
                _compared = false;
                _nonFinancial = false;
              }),
            ),
            if (_kind == RowEvidenceKind.financialRow)
              CheckboxListTile(
                key: const Key('row-evidence-create'),
                title: Text(s.unparsedCreate),
                value: _create,
                onChanged: (v) => setState(() {
                  _create = v ?? false;
                  _compared = false;
                }),
              ),
            if (_create && _kind == RowEvidenceKind.financialRow) ...[
              Text(s.unparsedCreateHint),
              TextField(
                key: const Key('row-evidence-name'),
                controller: _name,
                decoration: InputDecoration(labelText: s.rowNameLabel),
                onChanged: (_) => setState(() {
                  _compared = false;
                }),
              ),
              TextField(
                key: const Key('row-evidence-amount'),
                controller: _amount,
                decoration: InputDecoration(
                  labelText: s.rowAmountLabel,
                  hintText: '0,00',
                ),
                onChanged: (_) => setState(() {
                  _compared = false;
                }),
              ),
              DropdownButtonFormField<LineKind>(
                key: const Key('row-evidence-line-kind'),
                initialValue: _lineKind,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.rowKindLabel),
                items: [
                  DropdownMenuItem(
                    value: LineKind.product,
                    child: Text(s.productKind),
                  ),
                  DropdownMenuItem(
                    value: LineKind.deposit,
                    child: Text(s.depositKind),
                  ),
                  DropdownMenuItem(
                    value: LineKind.adjustment,
                    child: Text(s.adjustmentKind),
                  ),
                ],
                onChanged: (kind) => setState(() {
                  _lineKind = kind ?? LineKind.product;
                  _compared = false;
                }),
              ),
            ] else if (_needsTarget)
              DropdownButtonFormField<RelationshipTarget>(
                key: ValueKey('row-evidence-target-${_kind?.name}'),
                initialValue: _target,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.unparsedTarget),
                items: [
                  for (final target in widget.targets)
                    if (target.input.kind != LineKind.discount &&
                        (_kind != RowEvidenceKind.description ||
                            target.input.kind == LineKind.product))
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
                  _compared = false;
                }),
              ),
            if (_kind != null && !_needsTarget)
              CheckboxListTile(
                key: const Key('row-evidence-non-financial'),
                title: Text(s.unparsedNonFinancial),
                value: _nonFinancial,
                onChanged: (v) => setState(() {
                  _nonFinancial = v ?? false;
                }),
              ),
            if (!valid) Text(s.unparsedNeedsReview),
            if (changingCreatedRow) Text(s.unparsedCreatedRowGuard),
            if (widget.image == null) Text(s.findingImageRequired),
            TextField(
              key: const Key('row-evidence-note'),
              controller: _note,
              maxLines: 3,
              decoration: InputDecoration(labelText: s.findingNote),
              onChanged: (_) => setState(() {}),
            ),
            CheckboxListTile(
              key: const Key('row-evidence-compared'),
              title: Text(s.findingCompared),
              value: _compared,
              onChanged: (v) => setState(() {
                _compared = v ?? false;
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.closeEvidence),
        ),
        FilledButton(
          key: const Key('confirm-row-evidence'),
          onPressed:
              widget.image != null &&
                  valid &&
                  _compared &&
                  _note.text.trim().isNotEmpty &&
                  (_needsTarget || _nonFinancial)
              ? () => Navigator.pop(
                  context,
                  RowEvidenceDecision(
                    _kind!,
                    _needsTarget && !_create ? _target?.id : null,
                    _note.text.trim(),
                    newRow: _create ? newRow : null,
                  ),
                )
              : null,
          child: Text(s.unparsedConfirm),
        ),
      ],
    );
  }
}

String rowEvidenceKindLabel(AppLocalizations s, RowEvidenceKind kind) =>
    switch (kind) {
      RowEvidenceKind.financialRow => s.unparsedFinancial,
      RowEvidenceKind.description => s.unparsedDescription,
      RowEvidenceKind.headerMetadata => s.unparsedMetadata,
      RowEvidenceKind.paymentOrTax => s.unparsedPayment,
      RowEvidenceKind.explanatoryText => s.unparsedExplanatory,
    };
