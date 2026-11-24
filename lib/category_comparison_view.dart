import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;

import 'category_labels.dart';
import 'dashboard_help.dart';
import 'l10n/generated/app_localizations.dart';
import 'receipt_format.dart';

class CategoryComparisonView extends StatelessWidget {
  const CategoryComparisonView({
    super.key,
    required this.data,
    required this.onCategory,
  });
  final SpendingDashboard data;
  final void Function(ReceiptCategory, SpendingPeriod) onCategory;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final changes = data.categoryChanges;
    // Reserve the same label width for every bar so equal amounts have equal
    // lengths even when their printed amounts have different digit counts.
    final amountWidth = changes.fold<double>(0, (width, g) {
      for (final amount in [g.current.totalCents, g.previous.totalCents]) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${formatCents(amount)} €',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (painter.width + 2 > width) width = painter.width + 2;
        painter.dispose();
      }
      return width;
    });
    final biggest = changes
        .where((g) => g.changeCents != BigInt.zero)
        .take(5)
        .toList();
    final remaining = changes.where((g) => !biggest.contains(g)).toList();
    final max = changes.fold(BigInt.one, (value, g) {
      for (final cents in [g.current.totalCents, g.previous.totalCents]) {
        if (cents.abs() > value) value = cents.abs();
      }
      return value;
    });
    final signed = changes.any(
      (g) =>
          g.current.totalCents.isNegative || g.previous.totalCents.isNegative,
    );
    String range(SpendingPeriod p) =>
        '${receiptDateText(purchaseCalendarDate(p.firstDay))}–${receiptDateText(purchaseCalendarDate(p.lastDay))}';
    Widget row(CategorySpendingChange g) => _ComparisonRow(
      change: g,
      amountWidth: amountWidth,
      max: max,
      signed: signed,
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(categoryLabel(s, g.category)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in [
                (
                  s.dashboardCurrentShort,
                  data.query.comparisonCurrent!,
                  g.current,
                ),
                (
                  s.dashboardPreviousShort,
                  data.query.comparisonPrevious!,
                  g.previous,
                ),
              ])
                ListTile(
                  key: ValueKey(
                    'category-comparison-open-${entry.$2.firstDay}',
                  ),
                  title: Text(
                    '${entry.$1}: ${formatCents(entry.$3.totalCents)} €',
                  ),
                  subtitle: Text(range(entry.$2)),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: entry.$3.receiptCount > 0,
                  onTap: () {
                    Navigator.pop(dialogContext);
                    onCategory(g.category, entry.$2);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(s.catalogClose),
            ),
          ],
        ),
      ),
    );
    return Card(
      key: const Key('category-comparison'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.dashboardBiggestChanges,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DashboardInfoButton(
                  key: const Key('category-comparison-info'),
                  title: s.dashboardCategoryComparison,
                  paragraphs: [
                    s.dashboardCategoryComparisonHelp,
                    if (data.query.comparisonCurrent != null)
                      '${s.dashboardCurrentShort}: ${range(data.query.comparisonCurrent!)}',
                    if (data.query.comparisonPrevious != null)
                      '${s.dashboardPreviousShort}: ${range(data.query.comparisonPrevious!)}',
                  ],
                ),
              ],
            ),
            if (!data.comparisonAvailable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  s.dashboardCategoryComparisonMissing,
                  key: const Key('category-comparison-missing'),
                ),
              )
            else ...[
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Legend(s.dashboardCurrentShort, colors.primary),
                  _Legend(s.dashboardPreviousShort, colors.secondary),
                ],
              ),
              if (biggest.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(s.dashboardNoChanges),
                ),
              for (final g in biggest) row(g),
              if (remaining.isNotEmpty)
                ExpansionTile(
                  key: const Key('category-comparison-all'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(s.dashboardAllCategories),
                  children: [for (final g in remaining) row(g)],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 8, color: color),
      const SizedBox(width: 6),
      Flexible(child: Text(label)),
    ],
  );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.change,
    required this.amountWidth,
    required this.max,
    required this.signed,
    required this.onTap,
  });
  final CategorySpendingChange change;
  final BigInt max;
  final double amountWidth;
  final bool signed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final delta = change.changeCents;
    final percent = change.changeTenthsPercent;
    String percentage(BigInt value) {
      final digits = value.abs().toString().padLeft(2, '0');
      return '${value.isNegative
          ? '−'
          : value > BigInt.zero
          ? '+'
          : ''}${digits.substring(0, digits.length - 1)},${digits.substring(digits.length - 1)} %';
    }

    Widget bar(BigInt cents, Color color, String label) {
      final fraction =
          (cents.abs() * BigInt.from(1000000) ~/ max).toDouble() / 1000000;
      final line = Align(
        alignment: cents.isNegative
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: Container(height: 9, color: color),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: '$label: ${formatCents(cents)} €',
                  child: SizedBox(
                    height: 12,
                    child: signed
                        ? Row(
                            children: [
                              Expanded(
                                child: cents.isNegative
                                    ? line
                                    : const SizedBox(),
                              ),
                              Container(width: 1, color: colors.outlineVariant),
                              Expanded(
                                child: !cents.isNegative
                                    ? line
                                    : const SizedBox(),
                              ),
                            ],
                          )
                        : line,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: amountWidth.clamp(0.0, constraints.maxWidth * .45),
                child: Text(
                  '${formatCents(cents)} €',
                  semanticsLabel: '$label: ${formatCents(cents)} €',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      key: ValueKey(
        'category-change-${change.category.kind.name}-${change.category.name ?? ''}',
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text(
                  categoryLabel(s, change.category),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${delta > BigInt.zero ? '+' : ''}${formatCents(delta)} €${percent == null ? '' : ' · ${percentage(percent)}'}',
                  key: ValueKey(
                    'category-delta-${change.category.kind.name}-${change.category.name ?? ''}',
                  ),
                  style: TextStyle(
                    color: delta > BigInt.zero
                        ? colors.error
                        : colors.onSurface,
                  ),
                ),
              ],
            ),
            bar(
              change.current.totalCents,
              colors.primary,
              s.dashboardCurrentShort,
            ),
            bar(
              change.previous.totalCents,
              colors.secondary,
              s.dashboardPreviousShort,
            ),
          ],
        ),
      ),
    );
  }
}
