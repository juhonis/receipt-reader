import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show QuantityUnit;
import 'package:receipt_storage/receipt_storage.dart';

import 'catalog_editor.dart';
import 'catalog_service.dart';
import 'dashboard_help.dart';
import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'product_comparison_service.dart';
import 'product_picker.dart';
import 'purchase_history_page.dart';
import 'purchase_history_service.dart';
import 'purchase_range_dialog.dart';
import 'receipt_format.dart';

String comparisonUnit(QuantityUnit unit) => switch (unit) {
  QuantityUnit.kg => 'kg',
  QuantityUnit.litre => 'l',
  QuantityUnit.piece => 'kpl',
  QuantityUnit.unknown => '?',
};
String _day(int day) => receiptDateText(purchaseCalendarDate(day));

class ProductComparisonPage extends StatefulWidget {
  const ProductComparisonPage({
    super.key,
    required this.store,
    required this.service,
    required this.catalog,
    required this.productId,
    this.initialRange,
  });
  final LocalStore store;
  final ProductComparisonService service;
  final CatalogService catalog;
  final DurableId productId;
  final PurchaseDateRange? initialRange;
  @override
  State<ProductComparisonPage> createState() => _ProductComparisonPageState();
}

class _ProductComparisonPageState extends State<ProductComparisonPage> {
  late PurchaseDateRange _range = widget.initialRange ?? PurchaseDateRange();
  late Future<ProductComparisonResult> _result = _load();
  final _scroll = ScrollController();
  Future<ProductComparisonResult> _load() =>
      widget.service.productComparison(widget.productId, range: _range)
        ..ignore();
  void _reload() => setState(() {
    _result = _load();
  });
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _dates() async {
    final choice = await showDialog<PurchaseDateRange>(
      context: context,
      builder: (_) => PurchaseRangeDialog(range: _range),
    );
    if (!mounted || choice == null) return;
    _range = choice;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _reload();
  }

  Future<void> _edit(ProductComparisonResult data) async {
    try {
      final branches = await widget.catalog.branches();
      if (!mounted) return;
      final branch = branches.firstWhere(
        (b) => b.id == data.anchor.document.product.storeId,
      );
      await showDialog<CatalogEditResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CatalogEditor(
          service: widget.catalog,
          branch: branch,
          aliasMode: false,
          product: data.anchor,
        ),
      );
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.catalogLoadFailed),
          ),
        );
      }
    }
  }

  Future<void> _members(
    ProductComparisonResult data,
    ReceiptBranch branch,
  ) async {
    final members = data.members
        .where((m) => m.branch.id == branch.id)
        .toList();
    final selected = await showDialog<ComparisonMember>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(branch.name),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in members)
                ListTile(
                  key: ValueKey(
                    'comparison-member-${m.product.document.product.id.value}',
                  ),
                  title: Text(productLabel(m.product)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(c, m),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(context)!.catalogClose),
          ),
        ],
      ),
    );
    if (!mounted ||
        selected == null ||
        widget.store is! PurchaseHistoryService) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseHistoryPage(
          store: widget.store,
          service: widget.store as PurchaseHistoryService,
          product: selected.product,
          branchName: selected.branch.name,
          initialRange: _range,
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
        title: Text(s.comparisonTitle),
        actions: [
          IconButton(
            key: const Key('comparison-refresh'),
            onPressed: _reload,
            tooltip: s.refreshHistory,
            icon: const Icon(Icons.refresh),
          ),
          DashboardInfoButton(
            key: const Key('comparison-help'),
            title: s.comparisonTitle,
            paragraphs: [
              s.comparisonPolicy,
              s.comparisonPackagePolicy,
              s.comparisonObservationPolicy,
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: FutureBuilder<ProductComparisonResult>(
              key: ObjectKey(_result),
              future: _result,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      key: const Key('comparison-retry'),
                      onPressed: _reload,
                      child: Text(
                        snapshot.error is StorageFailure &&
                                (snapshot.error! as StorageFailure).code ==
                                    'comparisonGroupLimit'
                            ? s.comparisonLimit
                            : s.purchaseLoadFailed,
                      ),
                    ),
                  );
                }
                final data = snapshot.requireData, summary = data.summary;
                return ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      data.anchor.document.product.comparisonKey ??
                          s.comparisonNoGroup,
                      key: const Key('comparison-group'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          key: const Key('comparison-edit'),
                          onPressed: () => _edit(data),
                          icon: const Icon(Icons.edit),
                          label: Text(s.comparisonEdit),
                        ),
                        TextButton.icon(
                          key: const Key('comparison-range'),
                          onPressed: _dates,
                          icon: const Icon(Icons.date_range),
                          label: Text(s.purchaseDateRange),
                        ),
                        if (!_range.isEmpty)
                          TextButton(
                            key: const Key('comparison-reset-range'),
                            onPressed: () {
                              _range = PurchaseDateRange();
                              _reload();
                            },
                            child: Text(s.historyResetFilters),
                          ),
                      ],
                    ),
                    if (summary.firstDay != null)
                      Text(
                        '${_day(summary.firstDay!)}–${_day(summary.lastDay!)}',
                      ),
                    if (data.anchor.document.product.comparisonKey == null)
                      Text(s.comparisonKeyHint)
                    else ...[
                      if (summary.series.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(s.purchaseNoComparable),
                        ),
                      for (final unit in [
                        QuantityUnit.kg,
                        QuantityUnit.litre,
                        QuantityUnit.piece,
                      ])
                        if (summary.series.any((g) => g.unit == unit))
                          ComparisonUnitView(
                            key: ValueKey('comparison-unit-${unit.name}'),
                            series: summary.series
                                .where((g) => g.unit == unit)
                                .toList(),
                            first: summary.firstDay!,
                            last: summary.lastDay!,
                            onBranch: (b) => _members(data, b),
                          ),
                      ExpansionTile(
                        key: const Key('comparison-coverage'),
                        title: Text(
                          '${s.purchaseComparableRows}: ${summary.comparableRows} / ${summary.totalRows}',
                        ),
                        children: [
                          ListTile(
                            title: Text(
                              '${s.purchaseReturnRows}: ${summary.returnRows}',
                            ),
                          ),
                          ListTile(
                            title: Text(
                              '${s.purchaseMissingRows}: ${summary.missingQuantityRows}',
                            ),
                          ),
                          ListTile(
                            title: Text(
                              '${s.comparisonMissingPackage}: ${summary.missingPackageRows}',
                            ),
                          ),
                          ListTile(
                            title: Text(
                              '${s.purchaseNegativeRows}: ${summary.negativeRows}',
                            ),
                          ),
                          if (summary.receiptDiscountRows > 0)
                            ListTile(title: Text(s.purchaseReceiptDiscount)),
                          if (summary.adjustmentRows > 0)
                            ListTile(title: Text(s.purchaseAdjustment)),
                        ],
                      ),
                      ExpansionTile(
                        title: Text(
                          '${s.comparisonProducts}: ${data.members.length}',
                        ),
                        children: [
                          for (final m in data.members)
                            ListTile(
                              title: Text(productLabel(m.product)),
                              subtitle: Text(m.branch.name),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class ComparisonUnitView extends StatefulWidget {
  const ComparisonUnitView({
    super.key,
    required this.series,
    required this.first,
    required this.last,
    required this.onBranch,
  });
  final List<ProductComparisonSeries> series;
  final int first, last;
  final ValueChanged<ReceiptBranch> onBranch;
  @override
  State<ComparisonUnitView> createState() => _ComparisonUnitViewState();
}

class _ComparisonUnitViewState extends State<ComparisonUnitView> {
  int? _selected;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!,
        colors = Theme.of(context).colorScheme;
    final series = widget.series;
    final unit = comparisonUnit(series.first.unit);
    final count = math.min(24, widget.last - widget.first + 1);
    int boundary(int i) =>
        widget.first +
        (i * (widget.last - widget.first + 1) + count - 1) ~/ count;
    final palette = [
      colors.primary,
      Colors.deepPurple.shade600,
      Colors.blue.shade700,
      Colors.orange.shade800,
      Colors.green.shade700,
      Colors.brown.shade600,
    ];
    final high = series.last.weightedMean;
    final zero = UnitPrice.fromLine(BigInt.zero, BigInt.one, 0);
    var lowTrend = series.first.buckets.first.weightedMean,
        highTrend = lowTrend;
    for (final g in series) {
      for (final b in g.buckets) {
        if (b.weightedMean.compareTo(lowTrend) < 0) lowTrend = b.weightedMean;
        if (b.weightedMean.compareTo(highTrend) > 0) highTrend = b.weightedMean;
      }
    }
    final latest = series
        .expand((g) => g.buckets)
        .map((b) => b.firstDay)
        .reduce(math.max);
    final selected =
        _selected ??
        (latest - widget.first) * count ~/ (widget.last - widget.first + 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${s.comparisonWeightedPrices} · €/$unit',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < series.length; i++)
              InkWell(
                key: ValueKey(
                  'comparison-store-${series[i].branch.id.value}-${series[i].unit.name}',
                ),
                onTap: () => widget.onBranch(series[i].branch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          Text(series[i].branch.name),
                          Text('${series[i].weightedMean.euros} €/$unit'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: high.numerator == BigInt.zero
                              ? 0
                              : series[i].weightedMean
                                    .positionBetween(zero, high)
                                    .clamp(0.0, 1.0),
                          child: Container(
                            height: 8,
                            color: palette[i % palette.length],
                          ),
                        ),
                      ),
                      Text(
                        '${s.purchaseComparableRows}: ${series[i].count} · ${series[i].minimum.euros}–${series[i].maximum.euros} €/$unit',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              s.comparisonTrend,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${s.comparisonScale}: ${lowTrend.euros}–${highTrend.euros} €/$unit',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              height: 160,
              child: LayoutBuilder(
                builder: (context, size) => GestureDetector(
                  key: ValueKey('comparison-trend-${series.first.unit.name}'),
                  onTapUp: (details) => setState(
                    () => _selected =
                        (details.localPosition.dx / size.maxWidth * count)
                            .floor()
                            .clamp(0, count - 1),
                  ),
                  child: CustomPaint(
                    painter: _ComparisonTrendPainter(
                      series,
                      palette,
                      widget.first,
                      widget.last,
                      lowTrend,
                      highTrend,
                      selected,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [Text(_day(widget.first)), Text(_day(widget.last))],
            ),
            Row(
              children: [
                IconButton(
                  key: ValueKey(
                    'comparison-trend-prev-${series.first.unit.name}',
                  ),
                  tooltip: s.dashboardPreviousShort,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: selected == 0
                      ? null
                      : () => setState(() => _selected = selected - 1),
                ),
                Expanded(
                  child: Text(
                    '${_day(boundary(selected))}–${_day(boundary(selected + 1) - 1)}',
                    textAlign: TextAlign.center,
                    key: ValueKey(
                      'comparison-trend-selection-${series.first.unit.name}',
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey(
                    'comparison-trend-next-${series.first.unit.name}',
                  ),
                  tooltip: s.comparisonNextInterval,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: selected == count - 1
                      ? null
                      : () => setState(() => _selected = selected + 1),
                ),
              ],
            ),
            for (var i = 0; i < series.length; i++)
              Builder(
                builder: (context) {
                  final matches = series[i].buckets.where(
                    (b) => b.firstDay == boundary(selected),
                  );
                  return Text(
                    '${series[i].branch.name}: ${matches.isEmpty ? '—' : '${matches.single.weightedMean.euros} €/$unit'}',
                    style: TextStyle(color: palette[i % palette.length]),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonTrendPainter extends CustomPainter {
  _ComparisonTrendPainter(
    this.series,
    this.palette,
    this.first,
    this.last,
    this.low,
    this.high,
    this.selected,
  );
  final List<ProductComparisonSeries> series;
  final List<Color> palette;
  final int first, last, selected;
  final UnitPrice low, high;
  @override
  void paint(Canvas canvas, Size size) {
    final count = math.min(24, last - first + 1), span = last - first + 1;
    double x(int index) => size.width * (index + .5) / count;
    canvas.drawLine(
      Offset(x(selected), 0),
      Offset(x(selected), size.height),
      Paint()..color = Colors.grey.withValues(alpha: .3),
    );
    for (var i = 0; i < series.length; i++) {
      Offset? previous;
      int? previousIndex;
      final paint = Paint()
        ..color = palette[i % palette.length]
        ..strokeWidth = 2;
      for (final b in series[i].buckets) {
        final index = (b.firstDay - first) * count ~/ span;
        final point = Offset(
          x(index),
          size.height -
              10 -
              b.weightedMean.positionBetween(low, high) * (size.height - 20),
        );
        if (previous != null && previousIndex == index - 1) {
          canvas.drawLine(previous, point, paint);
        }
        canvas.drawCircle(point, 4, paint);
        previous = point;
        previousIndex = index;
      }
    }
  }

  @override
  bool shouldRepaint(_ComparisonTrendPainter old) => true;
}
