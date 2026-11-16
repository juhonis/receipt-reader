import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_evidence_painter.dart';

class LayoutReviewDialog extends StatefulWidget {
  const LayoutReviewDialog({
    super.key,
    required this.contextData,
    required this.image,
    this.highlights = const [],
  });
  final ReceiptParseContext contextData;
  final ui.Image image;
  final List<OcrWord> highlights;
  @override
  State<LayoutReviewDialog> createState() => _LayoutReviewDialogState();
}

class _LayoutReviewDialogState extends State<LayoutReviewDialog> {
  late double _top =
      (widget.contextData.itemTop / widget.contextData.page.height).clamp(
        0,
        .99,
      );
  late double _left =
      (widget.contextData.priceColumnLeft / widget.contextData.page.width)
          .clamp(.01, .99);
  bool _showWords = true;
  ReceiptDraft? _candidate;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final page = widget.contextData.page;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(s.layoutReviewTitle),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.layoutReviewHint),
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * .42).clamp(160, 420),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 8,
                child: SizedBox.expand(
                  child: CustomPaint(
                    key: const Key('layout-overlay'),
                    painter: ReceiptLayoutPainter(
                      widget.image,
                      page,
                      _top * page.height,
                      _left * page.width,
                      widget.highlights,
                      _showWords,
                    ),
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              title: Text(s.layoutWordBoxes),
              value: _showWords,
              onChanged: (value) => setState(() {
                _showWords = value ?? false;
              }),
            ),
            Text(s.ocrItemTop),
            Slider(
              key: const Key('repair-item-top'),
              value: _top,
              min: 0,
              max: .99,
              onChanged: (value) => setState(() {
                _top = value;
                _candidate = null;
              }),
            ),
            Text(s.ocrPriceLeft),
            Slider(
              key: const Key('repair-price-left'),
              value: _left,
              min: .01,
              max: .99,
              onChanged: (value) => setState(() {
                _left = value;
                _candidate = null;
              }),
            ),
            OutlinedButton(
              key: const Key('preview-layout'),
              onPressed: () => setState(() {
                _candidate = parseReceipt(
                  page,
                  itemTop: _top * page.height,
                  priceColumnLeft: _left * page.width,
                );
              }),
              child: Text(s.layoutPreview),
            ),
            if (_candidate case final candidate?) ...[
              Text(
                s.layoutPreviewSummary(
                  candidate.rows.length,
                  candidate.findings.length,
                  candidate.evidenceCoverage!.unassignedWords.length,
                ),
              ),
              if (candidate.printedTotal != null)
                Text(
                  s.layoutPreviewTotal(formatCents(candidate.printedTotal!)),
                ),
              for (final row in candidate.rows)
                Text('${row.name}: ${formatCents(row.cents)}'),
              Text(s.layoutFreshReviewHint),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.closeEvidence),
        ),
        FilledButton(
          key: const Key('open-layout-review'),
          onPressed: _candidate == null
              ? null
              : () => Navigator.pop(context, _candidate),
          child: Text(s.layoutOpenFresh),
        ),
      ],
    );
  }
}
