import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';

class HistoryFilterSelection {
  const HistoryFilterSelection(this.filter, this.branchName);
  final HistoryFilter filter;
  final String? branchName;
}

class HistoryFilterDialog extends StatefulWidget {
  const HistoryFilterDialog({
    super.key,
    required this.store,
    this.selection,
    this.amountBounds = true,
    this.title,
    this.notice,
  });
  final bool amountBounds;
  final String? title, notice;
  final LocalStore store;
  final HistoryFilterSelection? selection;

  @override
  State<HistoryFilterDialog> createState() => _HistoryFilterDialogState();
}

class _HistoryFilterDialogState extends State<HistoryFilterDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _from, _through, _min, _max;
  late String _branch;
  List<ReceiptBranch>? _branches;
  bool _branchFailed = false;
  String? _rangeError;

  String _day(StoredReceiptDate? date) =>
      date == null ? '' : '${date.day}.${date.month}.${date.year}';

  @override
  void initState() {
    super.initState();
    final filter = widget.selection?.filter;
    _branch = filter?.branchId?.value ?? '*';
    _from = TextEditingController(text: _day(filter?.fromDate));
    _through = TextEditingController(text: _day(filter?.throughDate));
    _min = TextEditingController(
      text: filter?.minTotalCents == null
          ? ''
          : formatCents(filter!.minTotalCents!),
    );
    _max = TextEditingController(
      text: filter?.maxTotalCents == null
          ? ''
          : formatCents(filter!.maxTotalCents!),
    );
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _branchFailed = false);
    try {
      final branches = await widget.store.branches();
      if (mounted) setState(() => _branches = branches);
    } catch (_) {
      if (mounted) setState(() => _branchFailed = true);
    }
  }

  @override
  void dispose() {
    for (final controller in [_from, _through, _min, _max]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validateDay(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final date = StoredReceiptDate.parse(value);
      if (date.hour == null) return null;
    } on ReceiptDataException {
      // Only a localized field error is displayed.
    }
    return AppLocalizations.of(context)!.historyDateInvalid;
  }

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final amount = parseCents(value);
    if (amount != null &&
        amount >= sqliteInt64Min &&
        amount <= sqliteInt64Max) {
      return null;
    }
    return AppLocalizations.of(context)!.historyAmountInvalid;
  }

  void _apply() {
    setState(() => _rangeError = null);
    if (!_form.currentState!.validate()) return;
    final from = _from.text.trim().isEmpty
        ? null
        : StoredReceiptDate.parse(_from.text);
    final through = _through.text.trim().isEmpty
        ? null
        : StoredReceiptDate.parse(_through.text);
    final min = widget.amountBounds ? parseCents(_min.text) : null;
    final max = widget.amountBounds ? parseCents(_max.text) : null;
    final s = AppLocalizations.of(context)!;
    int day(StoredReceiptDate date) =>
        date.year * 10000 + date.month * 100 + date.day;
    if (from != null && through != null && day(from) > day(through)) {
      setState(() => _rangeError = s.historyDateRangeInvalid);
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _rangeError = s.historyAmountRangeInvalid);
      return;
    }
    Navigator.pop(
      context,
      HistoryFilterSelection(
        HistoryFilter(
          branchId: _branch == '*' ? null : DurableId.parse(_branch),
          fromDate: from,
          throughDate: through,
          minTotalCents: min,
          maxTotalCents: max,
          category: widget.selection?.filter.category,
          query: widget.selection?.filter.query ?? '',
        ),
        _branch == '*'
            ? null
            : _branches!
                      .where((b) => b.id.value == _branch)
                      .firstOrNull
                      ?.name ??
                  widget.selection?.branchName ??
                  s.historyUnavailableBranch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title ?? s.historyFilters),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.notice ?? s.historyFilterNotice),
              if (_branches == null && !_branchFailed)
                const LinearProgressIndicator(),
              if (_branchFailed) ...[
                Text(s.branchLoadFailed),
                TextButton(
                  key: const Key('history-branches-retry'),
                  onPressed: _loadBranches,
                  child: Text(s.retryAction),
                ),
              ],
              if (_branches != null)
                DropdownButtonFormField<String>(
                  key: const Key('history-filter-branch'),
                  initialValue: _branch,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: InputDecoration(labelText: s.branchLabel),
                  items: [
                    DropdownMenuItem(
                      value: '*',
                      child: Text(s.historyAllBranches),
                    ),
                    for (final branch in _branches!)
                      DropdownMenuItem(
                        value: branch.id.value,
                        child: Text(
                          branch.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_branch != '*' &&
                        !_branches!.any((b) => b.id.value == _branch))
                      DropdownMenuItem(
                        value: _branch,
                        child: Text(
                          widget.selection?.branchName ??
                              s.historyUnavailableBranch,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _branch = value!),
                ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('history-filter-from'),
                controller: _from,
                decoration: InputDecoration(
                  labelText: s.historyFromDate,
                  hintText: 'pp.kk.vvvv',
                ),
                keyboardType: TextInputType.datetime,
                validator: _validateDay,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('history-filter-through'),
                controller: _through,
                decoration: InputDecoration(
                  labelText: s.historyThroughDate,
                  hintText: 'pp.kk.vvvv',
                ),
                keyboardType: TextInputType.datetime,
                validator: _validateDay,
              ),
              const SizedBox(height: 12),
              if (widget.amountBounds) ...[
                TextFormField(
                  key: const Key('history-filter-min'),
                  controller: _min,
                  decoration: InputDecoration(
                    labelText: s.historyMinAmount,
                    hintText: '0,00',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('history-filter-max'),
                  controller: _max,
                  decoration: InputDecoration(
                    labelText: s.historyMaxAmount,
                    hintText: '0,00',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: _validateAmount,
                ),
              ],
              if (_rangeError != null)
                Text(_rangeError!, key: const Key('history-filter-error')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('history-filter-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancelAction),
        ),
        FilledButton(
          key: const Key('history-filter-apply'),
          onPressed: _branches == null ? null : _apply,
          child: Text(s.historyApplyFilters),
        ),
      ],
    );
  }
}
