import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'spending_service.dart';
import 'history_filter_dialog.dart';
import 'receipt_format.dart';

class SpendingPage extends StatefulWidget {
  const SpendingPage({super.key, required this.store, required this.service});
  final LocalStore store;
  final SpendingService service;
  @override
  State<SpendingPage> createState() => _SpendingPageState();
}

class _SpendingPageState extends State<SpendingPage> {
  HistoryFilterSelection? _selection;
  late Future<SpendingSummary> _result;
  @override
  void initState() {
    super.initState();
    _result = _load();
  }

  Future<SpendingSummary> _load() =>
      widget.service.spendingSummary(filter: _selection?.filter);
  void _reload() {
    setState(() {
      _result = _load();
    });
  }

  Future<void> _filter() async {
    final s = AppLocalizations.of(context)!;
    final selection = await showDialog<HistoryFilterSelection>(
      context: context,
      builder: (_) => HistoryFilterDialog(
        store: widget.store,
        selection: _selection,
        amountBounds: false,
        title: s.spendingFilters,
        notice: s.spendingDateNotice,
      ),
    );
    if (!mounted || selection == null) return;
    _selection = selection.filter.isEmpty ? null : selection;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final filter = _selection?.filter;
    final range = [
      _selection?.branchName ?? s.historyAllBranches,
      filter?.fromDate == null
          ? s.purchaseStartOpen
          : receiptDateText(filter!.fromDate!),
      filter?.throughDate == null
          ? s.purchaseEndOpen
          : receiptDateText(filter!.throughDate!),
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Text(s.spendingTitle),
        actions: [
          IconButton(
            key: const Key('spending-refresh'),
            onPressed: _reload,
            tooltip: s.retryAction,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _selection == null ? s.spendingAll : range,
                    key: const Key('spending-selection'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _filter,
                        key: const Key('spending-filter'),
                        child: Text(s.spendingFilters),
                      ),
                      if (_selection != null)
                        TextButton(
                          key: const Key('spending-clear'),
                          onPressed: () {
                            _selection = null;
                            _reload();
                          },
                          child: Text(s.historyResetFilters),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<SpendingSummary>(
                key: ObjectKey(_result),
                future: _result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          snapshot.error is StorageFailure &&
                                  (snapshot.error! as StorageFailure).code ==
                                      'spendingGroupLimit'
                              ? s.spendingLimit
                              : s.spendingFailed,
                        ),
                        TextButton(
                          onPressed: _reload,
                          key: const Key('spending-retry'),
                          child: Text(s.retryAction),
                        ),
                      ],
                    );
                  }
                  final summary = snapshot.data!;
                  final entries = <Widget>[
                    Text(s.spendingScope),
                    const SizedBox(height: 16),
                    Text(
                      '${s.spendingNet}: ${formatCents(summary.totals.totalCents)} €',
                      key: const Key('spending-total'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    _totals(summary.totals),
                    if (summary.totals.receiptCount == 0) Text(s.spendingEmpty),
                    if (summary.branches.isNotEmpty) ...[
                      const Divider(),
                      Text(
                        s.spendingBranches,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(s.spendingBranchNotice),
                      for (final branch in summary.branches)
                        ExpansionTile(
                          key: ValueKey(
                            'spending-branch-${branch.branch.id.value}',
                          ),
                          title: Text(branch.branch.name),
                          subtitle: Text(
                            '${formatCents(branch.totals.totalCents)} € · ${s.spendingCount}: ${branch.totals.receiptCount}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: _totals(branch.totals),
                            ),
                          ],
                        ),
                    ],
                    if (summary.months.isNotEmpty) ...[
                      const Divider(),
                      Text(
                        s.spendingMonths,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(s.spendingMonthNotice),
                      for (final month in summary.months)
                        ExpansionTile(
                          key: ValueKey(
                            'spending-month-${month.year}-${month.month}',
                          ),
                          title: Text('${month.month}.${month.year}'),
                          subtitle: Text(
                            '${formatCents(month.totals.totalCents)} € · ${s.spendingCount}: ${month.totals.receiptCount}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: _totals(month.totals),
                            ),
                          ],
                        ),
                    ],
                  ];
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => entries[i],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totals(SpendingTotals totals) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${s.spendingCount}: ${totals.receiptCount}'),
        Text('${s.spendingNegative}: ${totals.negativeReceipts}'),
        Text('${s.spendingAdjusted}: ${totals.adjustedReceipts}'),
        Text('${s.spendingUnlinked}: ${totals.unlinkedReceipts}'),
      ],
    );
  }
}
