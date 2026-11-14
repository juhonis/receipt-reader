import 'package:material_ui/material_ui.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});
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
