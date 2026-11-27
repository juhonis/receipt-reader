import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_evidence_painter.dart';

/// Presentation groups only. Original findings and source identities still go
/// through the live audit individually; no parser warning is silently discarded.
class FindingReviewGroup {
  FindingReviewGroup(Iterable<int> indices, this.finding)
    : indices = List.unmodifiable(indices);
  final List<int> indices;
  final ParseFinding finding;
}

List<FindingReviewGroup> groupReviewFindings(
  List<ParseFinding> findings,
  OcrPage? page,
) {
  final groups = <List<int>>[];
  double baseline(OcrWord w) => page?.baselineY(w) ?? w.box.centerY;
  for (var i = 0; i < findings.length; i++) {
    final finding = findings[i];
    List<int>? group;
    if (isUnparsedItemFinding(finding) && finding.words.isNotEmpty) {
      for (final candidate in groups) {
        final anchor = findings[candidate.first];
        if (!isUnparsedItemFinding(anchor) || anchor.words.isEmpty) continue;
        final first = anchor.words.first;
        if ([...finding.words, ...anchor.words].every(
          (w) =>
              (baseline(w) - baseline(first)).abs() <=
              (w.box.height < first.box.height
                      ? w.box.height
                      : first.box.height) *
                  .45,
        )) {
          group = candidate;
          break;
        }
      }
    }
    if (group == null) {
      groups.add([i]);
    } else {
      group.add(i);
    }
  }
  final result = [
    for (final group in groups)
      FindingReviewGroup(
        group,
        group.length == 1
            ? findings[group.first]
            : ParseFinding(
                ParseIssue.unclassifiedRow,
                scope: FindingScope.item,
                words: ({for (final i in group) ...findings[i].words}.toList()
                  ..sort((a, b) => a.box.left.compareTo(b.box.left))),
              ),
      ),
  ];
  // Geometry can be accepted after source/financial problems are resolved.
  return List.unmodifiable([
    ...result.where((g) => !isGeometryFinding(g.finding)),
    ...result.where((g) => isGeometryFinding(g.finding)),
  ]);
}

class FindingReviewPanel extends StatelessWidget {
  const FindingReviewPanel({
    super.key,
    required this.group,
    required this.position,
    required this.total,
    required this.completed,
    required this.done,
    required this.message,
    required this.note,
    required this.onNoteChanged,
    required this.onReview,
    required this.onPrevious,
    required this.onNext,
    required this.onFinish,
    this.image,
    this.onAccept,
    this.onDismiss,
    this.onClassify,
  });
  final FindingReviewGroup group;
  final int position, total, completed;
  final bool done;
  final String message, note;
  final ui.Image? image;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onReview, onPrevious, onNext, onFinish;
  final VoidCallback? onAccept, onDismiss;
  final ValueChanged<RowEvidenceKind>? onClassify;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.problemProgress(completed, total),
              key: const Key('problem-progress'),
            ),
            LinearProgressIndicator(value: total == 0 ? 1 : completed / total),
            Text(s.problemPosition(position + 1, total)),
            Row(
              children: [
                Icon(done ? Icons.check_circle : Icons.pending_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(done ? s.problemDone : s.problemPending)),
              ],
            ),
            Text(message),
            if (image != null && group.finding.words.isNotEmpty)
              SizedBox(
                height: 180,
                child: InteractiveViewer(
                  maxScale: 8,
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: ReceiptEvidencePainter(
                        image!,
                        group.finding.words,
                      ),
                    ),
                  ),
                ),
              ),
            if (isGeometryFinding(group.finding)) Text(s.problemGeometryHint),
            if (!isGeometryFinding(group.finding) &&
                group.finding.words.isNotEmpty)
              SelectableText(group.finding.words.map((w) => w.text).join(' ')),
            if (completed == total)
              TextButton(
                key: const Key('problem-finish'),
                onPressed: onFinish,
                child: Text(s.problemFinish),
              ),
            if (!done) ...[
              if (onDismiss != null)
                FilledButton(
                  key: const Key('problem-dismiss'),
                  onPressed: onDismiss,
                  child: Text(s.problemDismiss),
                ),
              if (onAccept != null)
                FilledButton(
                  key: const Key('problem-accept'),
                  onPressed: onAccept,
                  child: Text(s.problemAccept),
                ),
              if (onClassify != null)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final kind in [
                      RowEvidenceKind.explanatoryText,
                      RowEvidenceKind.headerMetadata,
                      RowEvidenceKind.paymentOrTax,
                    ])
                      ActionChip(
                        key: ValueKey('problem-category-${kind.name}'),
                        label: Text(switch (kind) {
                          RowEvidenceKind.explanatoryText =>
                            s.unparsedExplanatory,
                          RowEvidenceKind.headerMetadata => s.unparsedMetadata,
                          _ => s.unparsedPayment,
                        }),
                        onPressed: () => onClassify!(kind),
                      ),
                  ],
                ),
            ],
            TextButton(
              key: ValueKey('finding-${group.indices.first}'),
              onPressed: onReview,
              child: Text(done ? s.problemReopen : s.problemDetails),
            ),
            ExpansionTile(
              title: Text(s.problemOptionalComment),
              children: [
                TextFormField(
                  key: const Key('problem-note'),
                  initialValue: note,
                  onChanged: onNoteChanged,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.findingNote),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  key: const Key('problem-previous'),
                  onPressed: position == 0 ? null : onPrevious,
                  child: Text(s.problemPrevious),
                ),
                TextButton(
                  key: const Key('problem-next'),
                  onPressed: total <= 1 ? null : onNext,
                  child: Text(s.problemNext),
                ),
              ],
            ),
            Text(s.problemNavigationHint),
          ],
        ),
      ),
    );
  }
}
