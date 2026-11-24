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
import 'dashboard_range_dialog.dart';
import 'store_spending_view.dart';
import 'category_spending_view.dart';
import 'category_comparison_view.dart';
import 'product_spending_view.dart';
import 'product_rankings_page.dart';
import 'spending_breakdown_view.dart';
import 'dashboard_summary_card.dart';
import 'dashboard_help.dart';

class SpendingDashboardPage extends StatefulWidget {
  const SpendingDashboardPage({
    super.key,
    required this.store,
    required this.service,
    this.clock = DateTime.now,
    this.embedded = false,
    this.active = true,
  });
  final LocalStore store;
  final SpendingDashboardService service;
  final DateTime Function() clock;
  final bool embedded, active;
  @override
  State<SpendingDashboardPage> createState() => _SpendingDashboardPageState();
}

class _SpendingDashboardPageState extends State<SpendingDashboardPage>
    with WidgetsBindingObserver {
  SpendingPeriodUnit _unit = SpendingPeriodUnit.month;
  late StoredReceiptDate _anchor;
  bool _followToday = true;
  bool _openingProduct = false;
  ReceiptBranch? _branch;
  StoredReceiptDate? _customFrom, _customThrough;
  late Future<SpendingDashboard> _result;
  late SpendingDashboardQuery _query;
  bool _compareCategories = false;
  SpendingBreakdownMode _breakdown = SpendingBreakdownMode.product;

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
  void didUpdateWidget(covariant SpendingDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _reload();
  }

  Future<SpendingDashboard> _load() async {
    final today = _today();
    if (_followToday ||
        purchaseCalendarDay(_anchor) > purchaseCalendarDay(today)) {
      _anchor = today;
    }
    _query = SpendingDashboardQuery(
      unit: _unit,
      anchor: _anchor,
      today: today,
      branchId: _branch?.id,
      customFrom: _customFrom,
      customThrough: _customThrough,
    );
    return widget.service.spendingDashboard(_query);
  }

  void _reload() => setState(() {
    _result = _load();
    // Obsolete requests may fail before the next frame attaches FutureBuilder.
    // Keep the error on the future for the active view without an unhandled error.
    _result.ignore();
  });

  Future<void> _pickDate() async {
    if (_unit == SpendingPeriodUnit.custom) {
      await _pickRange();
      return;
    }
    final today = _today();
    final value = await showDatePicker(
      context: context,
      initialDate: DateTime(_anchor.year, _anchor.month, _anchor.day),
      firstDate: DateTime(1970),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDatePickerMode: _unit == SpendingPeriodUnit.year
          ? DatePickerMode.year
          : DatePickerMode.day,
    );
    if (value == null || !mounted) return;
    _anchor = StoredReceiptDate.parse(
      '${value.day}.${value.month}.${value.year}',
    );
    _followToday = false;
    _reload();
  }

  Future<void> _pickRange() async {
    final today = _today();
    final range = await showDialog<PurchaseDateRange>(
      context: context,
      builder: (_) => DashboardRangeDialog(
        first:
            _customFrom ??
            StoredReceiptDate.parse('1.${today.month}.${today.year}'),
        last: _customThrough ?? today,
        today: today,
      ),
    );
    if (!mounted || range == null) return;
    _customFrom = range.fromDate;
    _customThrough = range.throughDate;
    _anchor = range.fromDate!;
    _unit = SpendingPeriodUnit.custom;
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

  void _move(SpendingDashboardQuery dashboard, int direction) {
    final start = purchaseCalendarDate(dashboard.selected.firstDay);
    var date = _unit == SpendingPeriodUnit.week
        ? DateTime.utc(start.year, start.month, start.day + direction * 7)
        : _unit == SpendingPeriodUnit.year
        ? DateTime.utc(start.year + direction)
        : DateTime.utc(start.year, start.month + direction);
    if (date.isBefore(DateTime.utc(1970))) date = DateTime.utc(1970);
    _anchor = StoredReceiptDate.parse('${date.day}.${date.month}.${date.year}');
    _followToday = false;
    _reload();
  }

  Future<void> _receipts(
    SpendingPeriod period, {
    ReceiptBranch? forBranch,
    ReceiptCategory? category,
  }) async {
    final selectedBranch = forBranch ?? _branch;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HistoryPage(
          store: widget.store,
          initialSelection: HistoryFilterSelection(
            HistoryFilter(
              branchId: selectedBranch?.id,
              category: category,
              fromDate: purchaseCalendarDate(period.firstDay),
              throughDate: purchaseCalendarDate(period.lastDay),
            ),
            selectedBranch?.name,
          ),
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _product(ProductSpending product, SpendingDashboard data) async {
    if (_openingProduct) return;
    final request = _result;
    setState(() => _openingProduct = true);
    final opened = await openRankedProduct(
      context,
      widget.store,
      product,
      data.query.selected,
      isCurrent: () => mounted && widget.active && _result == request,
    );
    if (mounted) {
      setState(() => _openingProduct = false);
      if (opened) _reload();
    }
  }

  Future<void> _allProducts(SpendingDashboard data) async {
    if (_openingProduct) return;
    setState(() => _openingProduct = true);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductRankingsPage(
          store: widget.store,
          service: widget.service,
          initialData: data,
          branchName: _branch?.name,
        ),
      ),
    );
    if (mounted) {
      setState(() => _openingProduct = false);
      _reload();
    }
  }

  Widget _periodControls(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final period = _query.selected;
    final first = purchaseCalendarDate(period.firstDay);
    final earliest = _unit == SpendingPeriodUnit.week
        ? period.firstDay == 0
        : _unit == SpendingPeriodUnit.year
        ? first.year == 1970
        : first.year == 1970 && first.month == 1;
    final next = period.lastDay < purchaseCalendarDay(_query.today);
    final branch = Row(
      children: [
        Expanded(
          child: TextButton.icon(
            key: const Key('dashboard-branch'),
            onPressed: _pickBranch,
            icon: const Icon(Icons.store_outlined, size: 18),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            label: Tooltip(
              message: _branch?.name ?? s.historyAllBranches,
              child: Text(
                _branch?.name ?? s.historyAllBranches,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('dashboard-today'),
          tooltip: s.dashboardCurrent,
          icon: const Icon(Icons.today_outlined, size: 20),
          onPressed: () {
            if (_unit == SpendingPeriodUnit.custom) {
              _unit = SpendingPeriodUnit.month;
            }
            _followToday = true;
            _reload();
          },
        ),
        if (widget.embedded)
          IconButton(
            key: const Key('dashboard-refresh'),
            tooltip: s.refreshHistory,
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 20),
          ),
      ],
    );
    final dates = Row(
      children: [
        if (_unit != SpendingPeriodUnit.custom)
          IconButton(
            key: const Key('dashboard-previous'),
            tooltip: s.dashboardPrevious,
            onPressed: earliest ? null : () => _move(_query, -1),
            icon: const Icon(Icons.chevron_left),
          ),
        Expanded(
          child: TextButton(
            key: const Key('dashboard-date'),
            onPressed: _pickDate,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _range(period),
                    key: const Key('dashboard-range'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (period.inProgress)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: s.dashboardPartialNotice,
                      child: const Icon(Icons.timelapse, size: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_unit != SpendingPeriodUnit.custom)
          IconButton(
            key: const Key('dashboard-next'),
            tooltip: s.dashboardNext,
            onPressed: next ? () => _move(_query, 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, size) => size.maxWidth >= 700
          ? Row(
              children: [
                SizedBox(width: 320, child: branch),
                Expanded(child: dates),
              ],
            )
          : Column(children: [branch, dates]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final unit in SpendingPeriodUnit.values)
                      ChoiceChip(
                        key: Key('dashboard-${unit.name}'),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        label: Text(switch (unit) {
                          SpendingPeriodUnit.week => s.dashboardWeekly,
                          SpendingPeriodUnit.month => s.dashboardMonthly,
                          SpendingPeriodUnit.year => s.dashboardYearly,
                          SpendingPeriodUnit.custom => s.dashboardCustom,
                        }),
                        selected: _unit == unit,
                        onSelected: (_) {
                          if (unit == SpendingPeriodUnit.custom) {
                            _pickRange();
                          } else {
                            _unit = unit;
                            _reload();
                          }
                        },
                      ),
                  ],
                ),
                _periodControls(context),
                FutureBuilder<SpendingDashboard>(
                  future: _result,
                  key: ObjectKey(_result),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
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
                          Text(
                            snapshot.error is StorageFailure &&
                                    (snapshot.error! as StorageFailure).code ==
                                        'spendingGroupLimit'
                                ? s.spendingLimit
                                : snapshot.error is StorageFailure &&
                                      (snapshot.error! as StorageFailure)
                                              .code ==
                                          'categoryGroupLimit'
                                ? s.categoryLimit
                                : s.spendingFailed,
                          ),
                          TextButton(
                            key: const Key('dashboard-retry'),
                            onPressed: _reload,
                            child: Text(s.retryAction),
                          ),
                        ],
                      );
                    }
                    final data = snapshot.requireData,
                        period = data.query.selected,
                        totals = data.selected;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DashboardSummaryCard(
                          data: data,
                          onReceipts: () => _receipts(period),
                          onCurrentComparison: () =>
                              _receipts(data.query.comparisonCurrent!),
                          onPreviousComparison: () =>
                              _receipts(data.query.comparisonPrevious!),
                        ),
                        SpendingBreakdownView(
                          data: data,
                          mode: _breakdown,
                          onMode: (value) => setState(() => _breakdown = value),
                          onProduct:
                              !_openingProduct &&
                                  canOpenRankedProduct(widget.store)
                              ? (product) => _product(product, data)
                              : null,
                          onCategory: (category) =>
                              _receipts(period, category: category),
                          onBranch: (branch) =>
                              _receipts(period, forBranch: branch),
                          onAllProducts: _openingProduct
                              ? null
                              : () => _allProducts(data),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              key: const Key('dashboard-chart-trend'),
                              selected: !_compareCategories,
                              onSelected: (_) =>
                                  setState(() => _compareCategories = false),
                              label: Text(s.dashboardTrend),
                            ),
                            ChoiceChip(
                              key: const Key('dashboard-chart-categories'),
                              selected: _compareCategories,
                              onSelected: (_) =>
                                  setState(() => _compareCategories = true),
                              label: Text(s.dashboardCategoryComparison),
                            ),
                            if (!_compareCategories)
                              DashboardInfoButton(
                                key: const Key('dashboard-trend-info'),
                                title: s.dashboardTrend,
                                paragraphs: [s.dashboardChartNotice],
                              ),
                          ],
                        ),
                        if (_compareCategories)
                          CategoryComparisonView(
                            data: data,
                            onCategory: (category, comparison) =>
                                _receipts(comparison, category: category),
                          )
                        else ...[
                          _SpendingChart(data: data, onPeriod: _receipts),
                          const SizedBox(height: 12),
                          CategorySpendingView(
                            summary: data.categories,
                            onCategory: (category) =>
                                _receipts(period, category: category),
                            compact: true,
                          ),
                        ],
                        const SizedBox(height: 8),
                        ExpansionTile(
                          key: const Key('dashboard-store-details'),
                          title: Text(s.dashboardStoreDetails),
                          children: [
                            StoreSpendingView(
                              data: data,
                              onBranch: (branch) =>
                                  _receipts(period, forBranch: branch),
                            ),
                          ],
                        ),
                        ExpansionTile(
                          key: const Key('dashboard-product-details'),
                          title: Text(s.dashboardProductDetails),
                          children: [
                            ProductSpendingView(
                              summary: data.products,
                              showAllLink: false,
                              onProduct:
                                  !_openingProduct &&
                                      canOpenRankedProduct(widget.store)
                                  ? (product) => _product(product, data)
                                  : null,
                            ),
                          ],
                        ),
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
                        ExpansionTile(
                          key: const Key('dashboard-coverage-details'),
                          title: Text(s.dashboardMoreDetails),
                          children: [
                            ListTile(
                              title: Text(
                                '${s.spendingNegative}: ${totals.negativeReceipts}',
                              ),
                            ),
                            ListTile(
                              title: Text(
                                '${s.spendingAdjusted}: ${totals.adjustedReceipts}',
                              ),
                            ),
                            ListTile(
                              title: Text(
                                '${s.spendingUnlinked}: ${totals.unlinkedReceipts}',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                '${s.dashboardAverageNotice}\n\n${s.spendingScope}',
                              ),
                            ),
                          ],
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
}

String _range(SpendingPeriod period) =>
    '${receiptDateText(purchaseCalendarDate(period.firstDay))}–${receiptDateText(purchaseCalendarDate(period.lastDay))}';

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
          width: math.max(data.periods.length * 72.0, constraints.maxWidth),
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
                                    data.query.chartScale ==
                                            SpendingChartScale.month
                                        ? '${day.month}.${day.year}'
                                        : data.query.chartScale ==
                                              SpendingChartScale.interval
                                        ? _range(bucket.period)
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
