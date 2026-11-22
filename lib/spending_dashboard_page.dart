import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'history_filter_dialog.dart';
import 'history_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'receipt_format.dart';
import 'spending_service.dart';

class SpendingDashboardPage extends StatefulWidget {
  const SpendingDashboardPage({
    super.key,
    required this.store,
    required this.service,
    this.clock = DateTime.now,
  });
  final LocalStore store;
  final SpendingDashboardService service;
  final DateTime Function() clock;
  @override
  State<SpendingDashboardPage> createState() => _SpendingDashboardPageState();
}

class _SpendingDashboardPageState extends State<SpendingDashboardPage>
    with WidgetsBindingObserver {
  SpendingPeriodUnit _unit = SpendingPeriodUnit.month;
  late StoredReceiptDate _anchor;
  bool _followToday = true;
  ReceiptBranch? _branch;
  late Future<SpendingDashboard> _result;

  StoredReceiptDate _today() {
    final day = helsinkiCalendarDate(widget.clock());
    return StoredReceiptDate.parse('${day.day}.${day.month}.${day.year}');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anchor = _today();
    _result = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<SpendingDashboard> _load() async {
    final today = _today();
    if (_followToday ||
        purchaseCalendarDay(_anchor) > purchaseCalendarDay(today)) {
      _anchor = today;
    }
    return widget.service.spendingDashboard(
      SpendingDashboardQuery(
        unit: _unit,
        anchor: _anchor,
        today: today,
        branchId: _branch?.id,
      ),
    );
  }

  void _reload() => setState(() {
    _result = _load();
    // Obsolete requests may fail before the next frame attaches FutureBuilder.
    // Keep the error on the future for the active view without an unhandled error.
    _result.ignore();
  });

  Future<void> _pickDate() async {
    final today = _today();
    final value = await showDatePicker(
      context: context,
      initialDate: DateTime(_anchor.year, _anchor.month, _anchor.day),
      firstDate: DateTime(1970),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (value == null || !mounted) return;
    _anchor = StoredReceiptDate.parse(
      '${value.day}.${value.month}.${value.year}',
    );
    _followToday = false;
    _reload();
  }

  Future<void> _pickBranch() async {
    final choice = await showDialog<({ReceiptBranch? branch})>(
      context: context,
      builder: (_) =>
          _DashboardBranchDialog(store: widget.store, selected: _branch),
    );
    if (choice == null || !mounted) return;
    _branch = choice.branch;
    _reload();
  }

  void _move(SpendingDashboard dashboard, int direction) {
    final start = purchaseCalendarDate(dashboard.query.selected.firstDay);
    var date = _unit == SpendingPeriodUnit.week
        ? DateTime.utc(start.year, start.month, start.day + direction * 7)
        : DateTime.utc(start.year, start.month + direction);
    if (date.isBefore(DateTime.utc(1970))) date = DateTime.utc(1970);
    _anchor = StoredReceiptDate.parse('${date.day}.${date.month}.${date.year}');
    _followToday = false;
    _reload();
  }

  Future<void> _receipts(SpendingPeriod period) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HistoryPage(
          store: widget.store,
          initialSelection: HistoryFilterSelection(
            HistoryFilter(
              branchId: _branch?.id,
              fromDate: purchaseCalendarDate(period.firstDay),
              throughDate: purchaseCalendarDate(period.lastDay),
            ),
            _branch?.name,
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.dashboardTitle),
        actions: [
          IconButton(
            key: const Key('dashboard-refresh'),
            tooltip: s.refreshHistory,
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('dashboard-week'),
                      label: Text(s.dashboardWeekly),
                      selected: _unit == SpendingPeriodUnit.week,
                      onSelected: (_) {
                        _unit = SpendingPeriodUnit.week;
                        _reload();
                      },
                    ),
                    ChoiceChip(
                      key: const Key('dashboard-month'),
                      label: Text(s.dashboardMonthly),
                      selected: _unit == SpendingPeriodUnit.month,
                      onSelected: (_) {
                        _unit = SpendingPeriodUnit.month;
                        _reload();
                      },
                    ),
                    TextButton.icon(
                      key: const Key('dashboard-branch'),
                      onPressed: _pickBranch,
                      icon: const Icon(Icons.store_outlined),
                      label: Text(_branch?.name ?? s.historyAllBranches),
                    ),
                    TextButton.icon(
                      key: const Key('dashboard-date'),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(s.dashboardChoosePeriod),
                    ),
                    TextButton(
                      key: const Key('dashboard-today'),
                      onPressed: () {
                        _followToday = true;
                        _reload();
                      },
                      child: Text(s.dashboardCurrent),
                    ),
                  ],
                ),
                FutureBuilder<SpendingDashboard>(
                  future: _result,
                  key: ObjectKey(_result),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const LinearProgressIndicator(),
                            Text(s.dashboardLoading),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(
                        children: [
                          Text(s.spendingFailed),
                          TextButton(
                            key: const Key('dashboard-retry'),
                            onPressed: _reload,
                            child: Text(s.retryAction),
                          ),
                        ],
                      );
                    }
                    final data = snapshot.requireData;
                    final period = data.query.selected;
                    final first = purchaseCalendarDate(period.firstDay);
                    final earliest = _unit == SpendingPeriodUnit.week
                        ? period.firstDay == 0
                        : first.year == 1970 && first.month == 1;
                    final canNext =
                        period.lastDay < purchaseCalendarDay(data.query.today);
                    final totals = data.selected;
                    final average = averageReceiptCents(totals);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            IconButton(
                              key: const Key('dashboard-previous'),
                              tooltip: s.dashboardPrevious,
                              onPressed: earliest
                                  ? null
                                  : () => _move(data, -1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text(
                              _range(period),
                              key: const Key('dashboard-range'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            IconButton(
                              key: const Key('dashboard-next'),
                              tooltip: s.dashboardNext,
                              onPressed: canNext ? () => _move(data, 1) : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                            if (period.inProgress)
                              Chip(label: Text(s.dashboardInProgress)),
                          ],
                        ),
                        if (period.inProgress) Text(s.dashboardPartialNotice),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth >= 800
                                ? (constraints.maxWidth - 24) / 3
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _metric(
                                  s.dashboardNet,
                                  '${formatCents(totals.totalCents)} €',
                                  'dashboard-total',
                                  width,
                                ),
                                _metric(
                                  s.spendingCount,
                                  '${totals.receiptCount}',
                                  'dashboard-count',
                                  width,
                                ),
                                _metric(
                                  s.dashboardAverage,
                                  average == null
                                      ? '—'
                                      : '${formatCents(average)} €',
                                  'dashboard-average',
                                  width,
                                ),
                              ],
                            );
                          },
                        ),
                        if (totals.receiptCount == 0) Text(s.spendingEmpty),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const Key('dashboard-receipts'),
                            onPressed: () => _receipts(period),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: Text(s.dashboardReceipts),
                          ),
                        ),
                        const Divider(),
                        Text(
                          s.dashboardTrend,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(s.dashboardChartNotice),
                        const SizedBox(height: 12),
                        _SpendingChart(data: data, onPeriod: _receipts),
                        const Divider(),
                        Text(
                          s.dashboardComparison,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (data.query.comparisonPrevious == null)
                          Text(s.dashboardNoComparison)
                        else ...[
                          Text(
                            s.dashboardComparisonDates(
                              _range(data.query.comparisonCurrent!),
                              _range(data.query.comparisonPrevious!),
                            ),
                          ),
                          Text(
                            period.inProgress
                                ? s.dashboardMatchedDays
                                : s.dashboardFullPeriods,
                          ),
                          Text(
                            '${s.dashboardComparisonCurrent}: ${formatCents(data.comparisonCurrent.totalCents)} € · ${s.spendingCount}: ${data.comparisonCurrent.receiptCount}',
                          ),
                          Text(
                            '${s.dashboardComparisonPrevious}: ${formatCents(data.comparisonPrevious.totalCents)} € · ${s.spendingCount}: ${data.comparisonPrevious.receiptCount}',
                          ),
                          if (data.comparisonCurrent.receiptCount > 0 &&
                              data.comparisonPrevious.receiptCount > 0) ...[
                            Text(
                              '${s.dashboardChange}: ${_signedMoney(data.changeCents)} €',
                              key: const Key('dashboard-change'),
                            ),
                            Text(
                              data.changeTenthsPercent == null
                                  ? s.dashboardNoPercentage
                                  : '${s.dashboardChangePercent}: ${_percentage(data.changeTenthsPercent!)}',
                              key: const Key('dashboard-percent'),
                            ),
                          ] else
                            Text(s.dashboardNoComparison),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                key: const Key(
                                  'dashboard-current-comparison-receipts',
                                ),
                                onPressed: () =>
                                    _receipts(data.query.comparisonCurrent!),
                                child: Text(s.dashboardCurrentReceipts),
                              ),
                              TextButton(
                                key: const Key(
                                  'dashboard-previous-comparison-receipts',
                                ),
                                onPressed: () =>
                                    _receipts(data.query.comparisonPrevious!),
                                child: Text(s.dashboardPreviousReceipts),
                              ),
                            ],
                          ),
                        ],
                        const Divider(),
                        ExpansionTile(
                          key: const Key('dashboard-period-details'),
                          title: Text(s.dashboardExactPeriods),
                          children: [
                            for (final bucket in data.periods.reversed)
                              ListTile(
                                key: ValueKey(
                                  'dashboard-period-${bucket.period.firstDay}',
                                ),
                                title: Text(_range(bucket.period)),
                                subtitle: Text(
                                  '${formatCents(bucket.totals.totalCents)} € · ${s.spendingCount}: ${bucket.totals.receiptCount}${bucket.period.inProgress ? ' · ${s.dashboardInProgress}' : ''}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _receipts(bucket.period),
                              ),
                          ],
                        ),
                        const Divider(),
                        Text(s.dashboardAverageNotice),
                        Text(s.spendingScope),
                        Text(
                          '${s.spendingNegative}: ${totals.negativeReceipts}',
                        ),
                        Text(
                          '${s.spendingAdjusted}: ${totals.adjustedReceipts}',
                        ),
                        Text(
                          '${s.spendingUnlinked}: ${totals.unlinkedReceipts}',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, String key, double width) =>
      SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(
                  value,
                  key: Key(key),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
      );
}

String _range(SpendingPeriod period) =>
    '${receiptDateText(purchaseCalendarDate(period.firstDay))}–${receiptDateText(purchaseCalendarDate(period.lastDay))}';
String _signedMoney(BigInt cents) =>
    '${cents > BigInt.zero ? '+' : ''}${formatCents(cents)}';
String _percentage(BigInt tenths) {
  final value = tenths.abs().toString().padLeft(2, '0');
  return '${tenths.isNegative
      ? '-'
      : tenths > BigInt.zero
      ? '+'
      : ''}${value.substring(0, value.length - 1)},${value.substring(value.length - 1)} %';
}

class _SpendingChart extends StatelessWidget {
  const _SpendingChart({required this.data, required this.onPeriod});
  final SpendingDashboard data;
  final void Function(SpendingPeriod) onPeriod;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    var positive = BigInt.zero, negative = BigInt.zero;
    for (final bucket in data.periods) {
      final cents = bucket.totals.totalCents;
      if (cents > positive) positive = cents;
      if (-cents > negative) negative = -cents;
    }
    final span = positive + negative;
    double fraction(BigInt n) => span == BigInt.zero
        ? 0
        : ((n * BigInt.from(1000000)) ~/ span).toInt() / 1000000;
    final above = span == BigInt.zero ? 140.0 : 160 * fraction(positive);
    final below = span == BigInt.zero ? 20.0 : 160 - above;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(720, constraints.maxWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final bucket in data.periods)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final cents = bucket.totals.totalCents;
                      final day = purchaseCalendarDate(bucket.period.firstDay);
                      final value =
                          '${_range(bucket.period)}: ${formatCents(cents)} € · ${s.spendingCount}: ${bucket.totals.receiptCount}';
                      return Semantics(
                        label: value,
                        button: true,
                        child: Tooltip(
                          message: value,
                          child: InkWell(
                            key: ValueKey(
                              'dashboard-bar-${bucket.period.firstDay}',
                            ),
                            onTap: () => onPeriod(bucket.period),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: above,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        width: 28,
                                        height: cents > BigInt.zero
                                            ? 160 * fraction(cents)
                                            : 0,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                  Container(height: 1, color: colors.outline),
                                  SizedBox(
                                    height: below,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        width: 28,
                                        height: cents < BigInt.zero
                                            ? 160 * fraction(-cents)
                                            : 0,
                                        color: colors.error,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    data.query.unit == SpendingPeriodUnit.month
                                        ? '${day.month}.${day.year}'
                                        : '${day.day}.${day.month}.',
                                  ),
                                  Text(
                                    bucket.totals.receiptCount == 0
                                        ? '—'
                                        : '${formatCents(cents)} €',
                                  ),
                                  if (bucket.period.inProgress)
                                    Icon(
                                      Icons.timelapse,
                                      size: 16,
                                      semanticLabel: s.dashboardInProgress,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardBranchDialog extends StatefulWidget {
  const _DashboardBranchDialog({required this.store, required this.selected});
  final LocalStore store;
  final ReceiptBranch? selected;
  @override
  State<_DashboardBranchDialog> createState() => _DashboardBranchDialogState();
}

class _DashboardBranchDialogState extends State<_DashboardBranchDialog> {
  late Future<List<ReceiptBranch>> _branches;
  @override
  void initState() {
    super.initState();
    _branches = widget.store.branches();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.branchLabel),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<ReceiptBranch>>(
          future: _branches,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  _branches = widget.store.branches()..ignore();
                }),
                child: Text(s.retryAction),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    key: const Key('dashboard-all-branches'),
                    title: Text(s.historyAllBranches),
                    selected: widget.selected == null,
                    onTap: () => Navigator.pop(context, (branch: null)),
                  ),
                  for (final branch in snapshot.requireData)
                    ListTile(
                      key: ValueKey('dashboard-branch-${branch.id.value}'),
                      title: Text(branch.name),
                      subtitle: branch.address == null
                          ? null
                          : Text(branch.address!),
                      selected: widget.selected?.id == branch.id,
                      onTap: () => Navigator.pop(context, (branch: branch)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancelAction),
        ),
      ],
    );
  }
}
