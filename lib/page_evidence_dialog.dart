import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_evidence_painter.dart';

class PageEvidenceDialog extends StatefulWidget {
  const PageEvidenceDialog({
    super.key,
    required this.image,
    required this.snapshot,
    this.guided = false,
    this.initiallyCompleted = false,
  });
  final ui.Image image;
  final OcrReviewSnapshot snapshot;
  final bool guided, initiallyCompleted;
  @override
  State<PageEvidenceDialog> createState() => _PageEvidenceDialogState();
}

class _PageEvidenceDialogState extends State<PageEvidenceDialog> {
  final _note = TextEditingController();
  bool _header = false, _footer = false, _layout = false, _complete = false;
  @override
  void initState() {
    super.initState();
    if (widget.guided && widget.initiallyCompleted) {
      _header = _footer = _layout = _complete = true;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final data = widget.snapshot.draft.parseContext!;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.guided ? s.ocrGuidedReview : s.pageEvidenceTitle),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 320,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 8,
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: ReceiptLayoutPainter(
                      widget.image,
                      data.page,
                      data.itemTop,
                      data.priceColumnLeft,
                      const [],
                      false,
                    ),
                  ),
                ),
              ),
            ),
            Text(widget.snapshot.branch),
            Text(widget.snapshot.date),
            Text(widget.snapshot.total),
            for (final row in widget.snapshot.rows)
              Text('${row.input.name}: ${row.input.amount}'),
            Text(widget.guided ? s.ocrGuidedHint : s.pageEvidenceHint),
            if (!widget.guided && !canApprovePageEvidence(widget.snapshot))
              Text(s.pageEvidenceNeedsRows),
            CheckboxListTile(
              key: const Key('page-header'),
              title: Text(s.pageHeaderCompared),
              value: _header,
              onChanged: (v) => setState(() {
                _header = v ?? false;
              }),
            ),
            CheckboxListTile(
              key: const Key('page-footer'),
              title: Text(s.pageFooterCompared),
              value: _footer,
              onChanged: (v) => setState(() {
                _footer = v ?? false;
              }),
            ),
            CheckboxListTile(
              key: const Key('page-layout'),
              title: Text(s.pageLayoutCompared),
              value: _layout,
              onChanged: (v) => setState(() {
                _layout = v ?? false;
              }),
            ),
            CheckboxListTile(
              key: const Key('page-complete-image'),
              title: Text(s.pageImageComplete),
              value: _complete,
              onChanged: (v) => setState(() {
                _complete = v ?? false;
              }),
            ),
            if (!widget.guided)
              TextField(
                key: const Key('page-evidence-note'),
                controller: _note,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: s.findingNote,
                  helperText: s.pageEvidenceNoteHelp,
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
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
          key: const Key('approve-page-evidence'),
          onPressed:
              (widget.guided || canApprovePageEvidence(widget.snapshot)) &&
                  _header &&
                  _footer &&
                  _layout &&
                  _complete
              ? () => Navigator.pop(
                  context,
                  widget.guided
                      ? true
                      : PageEvidenceApproval(
                          widget.snapshot,
                          _note.text.trim(),
                          headerCompared: _header,
                          footerCompared: _footer,
                          layoutCompared: _layout,
                          imageComplete: _complete,
                        ),
                )
              : null,
          child: Text(widget.guided ? s.ocrGuidedDone : s.pageEvidenceConfirm),
        ),
      ],
    );
  }
}

class GeometryEvidenceDialog extends StatefulWidget {
  const GeometryEvidenceDialog({
    super.key,
    required this.image,
    required this.contextData,
    required this.finding,
    required this.allowed,
    required this.blockers,
    this.initialNote = '',
  });
  final ui.Image image;
  final ReceiptParseContext contextData;
  final ParseFinding finding;
  final bool allowed;
  final Set<OcrEvidenceBlocker> blockers;
  final String initialNote;
  @override
  State<GeometryEvidenceDialog> createState() => _GeometryEvidenceDialogState();
}

class _GeometryEvidenceDialogState extends State<GeometryEvidenceDialog> {
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
    final data = widget.contextData;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(s.geometryEvidenceTitle),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 320,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 8,
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: ReceiptLayoutPainter(
                      widget.image,
                      data.page,
                      data.itemTop,
                      data.priceColumnLeft,
                      widget.finding.words,
                      true,
                    ),
                  ),
                ),
              ),
            ),
            SelectableText(widget.finding.words.map((w) => w.text).join(' ')),
            Text(s.geometryEvidenceHint),
            if (!widget.allowed) Text(s.geometryNeedsEvidence),
            for (final blocker in widget.blockers)
              if (blocker != OcrEvidenceBlocker.openFindings &&
                  blocker != OcrEvidenceBlocker.receiptApproval)
                Text(evidenceBlockerLabel(s, blocker)),
            TextField(
              key: const Key('geometry-evidence-note'),
              controller: _note,
              maxLines: 3,
              decoration: InputDecoration(labelText: s.findingNote),
              onChanged: (_) => setState(() {}),
            ),
            CheckboxListTile(
              key: const Key('geometry-evidence-compared'),
              title: Text(s.geometryCompared),
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
          key: const Key('confirm-geometry-evidence'),
          onPressed: widget.allowed && _compared
              ? () => Navigator.pop(context, _note.text.trim())
              : null,
          child: Text(s.resolveFinding),
        ),
      ],
    );
  }
}

String evidenceBlockerLabel(AppLocalizations s, OcrEvidenceBlocker blocker) =>
    switch (blocker) {
      OcrEvidenceBlocker.sourceContext => s.auditSourceContext,
      OcrEvidenceBlocker.rowReview => s.pageEvidenceNeedsRows,
      OcrEvidenceBlocker.pageReview => s.auditPageReview,
      OcrEvidenceBlocker.receiptApproval => s.ocrAcceptNotice,
      OcrEvidenceBlocker.originalRows => s.auditOriginalRows,
      OcrEvidenceBlocker.originalQuantities => s.auditOriginalQuantities,
      OcrEvidenceBlocker.openFindings => s.auditOpenFindings,
      OcrEvidenceBlocker.omissions => s.auditOmissions,
      OcrEvidenceBlocker.discountRelationships => s.auditDiscountRelationships,
      OcrEvidenceBlocker.quantityRelationships => s.relationshipOccupied,
    };
