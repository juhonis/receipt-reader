import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.draft});
  final ReceiptDraft? draft;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _RowFields {
  final name = TextEditingController();
  final amount = TextEditingController();
  LineKind kind = LineKind.product;
  void dispose() {
    name.dispose();
    amount.dispose();
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
  late final List<_RowFields> _sourceRows;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _rows.single.dispose();
      _rows.clear();
      for (final row in draft.rows) {
        _rows.add(
          _RowFields()
            ..name.text = row.name
            ..amount.text = formatCents(row.cents)
            ..kind = row.kind,
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
    }
    _sourceRows = List.of(_rows);
  }

  @override
  void dispose() {
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
  });

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
      // quantity/rate editing are implemented. Manual review remains available.
      hasUnresolvedParserIssues: widget.draft != null,
      rows: [
        for (final row in _rows)
          ReviewRowInput(row.name.text, row.amount.text, row.kind),
      ],
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
    return Scaffold(
      appBar: AppBar(title: Text(s.reviewTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(s.reviewNotice),
                if (widget.draft case final draft?) ...[
                  const SizedBox(height: 16),
                  Text(s.ocrDraftNotice, key: const Key('ocr-draft-blocked')),
                  Text(s.ocrIssuesPresent(draft.issues.length)),
                  for (final message in draft.issues.map(issueText).toSet())
                    Text(message),
                  for (final note in draft.notes) Text(note),
                  for (var n = 0; n < draft.wrappedNames.length; n++)
                    if (!_handledNames.contains(n) &&
                        draft.wrappedNames[n].rowIndex >= 0 &&
                        draft.wrappedNames[n].rowIndex < _sourceRows.length &&
                        _rows.contains(
                          _sourceRows[draft.wrappedNames[n].rowIndex],
                        ))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                s.proposedName(
                                  draft.wrappedNames[n].proposedName,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  _sourceRows[draft.wrappedNames[n].rowIndex]
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
                  if (draft.rows.any(
                    (r) => r.quantity != null || r.rateMicros != null,
                  ))
                    Text(s.quantityReviewPending),
                ],
                const SizedBox(height: 16),
                TextField(
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
                    _reviewed = false;
                  }),
                ),
                TextField(
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
                            key: ValueKey('row-name-$i'),
                            controller: _rows[i].name,
                            decoration: InputDecoration(
                              labelText: s.rowNameLabel,
                            ),
                            onChanged: _edit,
                          ),
                          TextField(
                            key: ValueKey('row-amount-$i'),
                            controller: _rows[i].amount,
                            decoration: InputDecoration(
                              labelText: s.rowAmountLabel,
                              hintText: '0,00',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            onChanged: _edit,
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
                                WidgetsBinding.instance.addPostFrameCallback(
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
                  validation.branchValid ? s.branchReady : s.branchNeedsReview,
                ),
                Text(
                  validation.date.state == ReceiptDateState.valid
                      ? s.dateReady
                      : s.dateNeedsReview,
                ),
                if (validation.date.state == ReceiptDateState.ambiguous ||
                    validation.date.state == ReceiptDateState.nonexistent ||
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
                if (validation.positiveDiscount) Text(s.discountSignWarning),
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
                  Text(s.reviewComplete, key: const Key('review-complete')),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
