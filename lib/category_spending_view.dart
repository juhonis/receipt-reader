import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'category_labels.dart';
import 'dashboard_help.dart';
import 'l10n/generated/app_localizations.dart';

class CategorySpendingView extends StatelessWidget {
  const CategorySpendingView({
    super.key,
    required this.summary,
    required this.onCategory,
    this.compact = false,
  });
  final CategorySpendingSummary summary;
  final void Function(ReceiptCategory) onCategory;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    var maximum = BigInt.zero;
    for (final group in summary.groups) {
      if (group.totalCents.abs() > maximum) maximum = group.totalCents.abs();
    }
    return Column(
      key: const Key('dashboard-categories'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.categorySpendingTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (compact)
              DashboardInfoButton(
                key: const Key('dashboard-category-info'),
                title: s.categorySpendingTitle,
                paragraphs: [
                  s.categorySpendingNotice,
                  s.categoryUnclassifiedHint,
                ],
              ),
          ],
        ),
        if (!compact) Text(s.categorySpendingNotice),
        Text(
          s.categoryCoverage(
            summary.categorizedProductRows,
            summary.productRows,
          ),
          key: const Key('category-coverage'),
        ),
        if (!compact && summary.uncategorizedProductRows > 0)
          Text(s.categoryUnclassifiedHint),
        if (summary.groups.isEmpty) Text(s.spendingEmpty),
        for (final group in summary.groups)
          Card(
            child: InkWell(
              key: ValueKey(
                'category-group-${group.category.kind.name}-${group.category.name ?? ''}',
              ),
              onTap: () => onCategory(group.category),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      children: [
                        Text(
                          categoryLabel(s, group.category),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('${formatCents(group.totalCents)} €'),
                      ],
                    ),
                    if (!compact)
                      Text(
                        '${s.spendingCount}: ${group.receiptCount} · ${s.categoryRows}: ${group.rowCount}',
                      ),
                    const SizedBox(height: 8),
                    ExcludeSemantics(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final fraction = maximum == BigInt.zero
                              ? 0.0
                              : ((group.totalCents.abs() *
                                                BigInt.from(1000000)) ~/
                                            maximum)
                                        .toInt() /
                                    1000000;
                          final width = constraints.maxWidth * fraction / 2;
                          final zero = constraints.maxWidth / 2;
                          return SizedBox(
                            height: 16,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                                Positioned(
                                  left: group.totalCents.isNegative
                                      ? zero - width
                                      : zero,
                                  top: 2,
                                  bottom: 2,
                                  width: width,
                                  child: ColoredBox(
                                    color: group.totalCents.isNegative
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                Positioned(
                                  left: zero,
                                  top: 0,
                                  bottom: 0,
                                  width: 1,
                                  child: ColoredBox(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
