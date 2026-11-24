import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;

import 'dashboard_help.dart';
import 'receipt_format.dart';
import 'l10n/generated/app_localizations.dart';

String _range(SpendingPeriod p) =>
    '${receiptDateText(purchaseCalendarDate(p.firstDay))}–${receiptDateText(purchaseCalendarDate(p.lastDay))}';
String _signed(BigInt value) =>
    '${value > BigInt.zero ? '+' : ''}${formatCents(value)}';
String _percent(BigInt value) {
  final text = value.abs().toString().padLeft(2, '0');
  return '${value.isNegative
      ? '-'
      : value > BigInt.zero
      ? '+'
      : ''}${text.substring(0, text.length - 1)},${text.substring(text.length - 1)} %';
}

class DashboardSummaryCard extends StatelessWidget {
  const DashboardSummaryCard({
    super.key,
    required this.data,
    required this.onReceipts,
    required this.onCurrentComparison,
    required this.onPreviousComparison,
  });
  final SpendingDashboard data;
  final VoidCallback onReceipts, onCurrentComparison, onPreviousComparison;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final previous = data.query.comparisonPrevious,
        current = data.query.comparisonCurrent;
    final comparable =
        previous != null &&
        data.comparisonCurrent.receiptCount > 0 &&
        data.comparisonPrevious.receiptCount > 0;
    final average = averageReceiptCents(data.selected);
    final colors = Theme.of(context).colorScheme;
    final changeColor = data.changeCents > BigInt.zero
        ? colors.error
        : colors.primary;
    void openComparison(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return Card(
      key: const Key('dashboard-summary'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.dashboardNet,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DashboardInfoButton(
                  key: const Key('dashboard-summary-info'),
                  title: s.dashboardComparison,
                  paragraphs: [
                    if (current != null && previous != null)
                      s.dashboardComparisonDates(
                        _range(current),
                        _range(previous),
                      ),
                    data.query.unit == SpendingPeriodUnit.custom
                        ? s.dashboardCustomComparison
                        : data.query.selected.inProgress
                        ? s.dashboardMatchedDays
                        : s.dashboardFullPeriods,
                    if (current != null)
                      '${s.dashboardComparisonCurrent}: ${formatCents(data.comparisonCurrent.totalCents)} € · ${s.spendingCount}: ${data.comparisonCurrent.receiptCount}',
                    if (previous != null)
                      '${s.dashboardComparisonPrevious}: ${formatCents(data.comparisonPrevious.totalCents)} € · ${s.spendingCount}: ${data.comparisonPrevious.receiptCount}',
                    if (!comparable) s.dashboardNoComparison,
                    if (data.changeTenthsPercent == null)
                      s.dashboardNoPercentage,
                    s.dashboardPartialNotice,
                    s.dashboardAverageNotice,
                    s.spendingScope,
                  ],
                  actions: [
                    if (current != null)
                      TextButton(
                        key: const Key('dashboard-current-comparison-receipts'),
                        onPressed: () => openComparison(onCurrentComparison),
                        child: Text(s.dashboardCurrentReceipts),
                      ),
                    if (previous != null)
                      TextButton(
                        key: const Key(
                          'dashboard-previous-comparison-receipts',
                        ),
                        onPressed: () => openComparison(onPreviousComparison),
                        child: Text(s.dashboardPreviousReceipts),
                      ),
                  ],
                ),
              ],
            ),
            Text(
              '${formatCents(data.selected.totalCents)} €',
              key: const Key('dashboard-total'),
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (comparable) ...[
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    data.changeCents > BigInt.zero
                        ? Icons.trending_up
                        : data.changeCents < BigInt.zero
                        ? Icons.trending_down
                        : Icons.trending_flat,
                    size: 18,
                    color: changeColor,
                  ),
                  Text(
                    '${_signed(data.changeCents)} €',
                    key: const Key('dashboard-change'),
                    style: TextStyle(
                      color: changeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (data.changeTenthsPercent case final percent?)
                    Text(
                      _percent(percent),
                      key: const Key('dashboard-percent'),
                      style: TextStyle(color: changeColor),
                    ),
                  Text(
                    s.dashboardVersusPrevious,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Text(
                '${s.dashboardPreviousShort}: ${formatCents(data.comparisonPrevious.totalCents)} €'
                '${data.query.selected.inProgress ? ' · ${s.dashboardMatchedShort}' : ''}',
                key: const Key('dashboard-previous-total'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Text(
                s.dashboardComparisonMissingShort,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('dashboard-receipts'),
                  onPressed: onReceipts,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${data.selected.receiptCount}',
                        key: const Key('dashboard-count'),
                      ),
                      Text(
                        ' ${data.selected.receiptCount == 1 ? s.dashboardReceiptSingle : s.dashboardReceiptPlural}',
                      ),
                    ],
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${s.dashboardAverageShort}: '),
                    Text(
                      average == null ? '—' : '${formatCents(average)} €',
                      key: const Key('dashboard-average'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
