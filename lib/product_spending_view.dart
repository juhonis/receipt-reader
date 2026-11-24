import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;

import 'l10n/generated/app_localizations.dart';

BigInt productRankingMaximum(ProductSpendingSummary summary) =>
    summary.groups.fold(
      BigInt.zero,
      (value, group) =>
          group.totalCents.abs() > value ? group.totalCents.abs() : value,
    );

class ProductSpendingView extends StatelessWidget {
  const ProductSpendingView({
    super.key,
    required this.summary,
    this.onProduct,
    this.onAll,
    this.showAllLink = true,
  });
  final ProductSpendingSummary summary;
  final ValueChanged<ProductSpending>? onProduct;
  final VoidCallback? onAll;
  final bool showAllLink;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final shown = summary.groups.take(10).toList();
    final others = summary.groups.skip(10).toList();
    final maximum = productRankingMaximum(summary);
    return Column(
      key: const Key('dashboard-products'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.productRankingTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(s.productRankingScope),
        ProductRankingCoverage(summary: summary),
        if (summary.limitExceeded)
          Text(s.productRankingLimit, key: const Key('product-ranking-limit'))
        else if (summary.groups.isEmpty)
          Text(s.productRankingEmpty)
        else ...[
          for (var i = 0; i < shown.length; i++)
            ProductRankingRow(
              group: shown[i],
              rank: i + 1,
              maximum: maximum,
              prefix: 'dashboard-product',
              onProduct: onProduct,
            ),
          if (others.isNotEmpty)
            Text(
              '${s.productRankingOthers} (${others.length}): '
              '${formatCents(others.fold(BigInt.zero, (sum, p) => sum + p.totalCents))} €',
              key: const Key('product-ranking-others'),
            ),
          if (showAllLink)
            TextButton(
              key: const Key('product-ranking-all'),
              onPressed: onAll,
              child: Text(s.productRankingAll),
            ),
        ],
      ],
    );
  }
}

class ProductRankingCoverage extends StatelessWidget {
  const ProductRankingCoverage({super.key, required this.summary});
  final ProductSpendingSummary summary;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s.productRankingCoverage}: ${summary.linkedRows} / ${summary.productRows}',
        ),
        Text(
          '${s.productRankingLinked}: ${formatCents(summary.linkedCents)} €',
          key: const Key('product-ranking-linked-total'),
        ),
        Text(
          '${s.productRankingUnlinked}: ${formatCents(summary.unlinkedCents)} €',
        ),
        Text(s.productRankingAttribution),
        if (summary.depositCents != BigInt.zero)
          Text('${s.categoryDeposits}: ${formatCents(summary.depositCents)} €'),
        if (summary.receiptDiscountCents != BigInt.zero)
          Text(
            '${s.categoryReceiptDiscounts}: ${formatCents(summary.receiptDiscountCents)} €',
          ),
        if (summary.adjustmentCents != BigInt.zero)
          Text(
            '${s.categoryAdjustments}: ${formatCents(summary.adjustmentCents)} €',
          ),
      ],
    );
  }
}

class ProductRankingRow extends StatelessWidget {
  const ProductRankingRow({
    super.key,
    required this.group,
    required this.rank,
    required this.maximum,
    required this.prefix,
    this.onProduct,
  });
  final ProductSpending group;
  final int rank;
  final BigInt maximum;
  final String prefix;
  final ValueChanged<ProductSpending>? onProduct;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: TextButton(
        key: ValueKey('$prefix-${group.productId.value}'),
        onPressed: onProduct == null ? null : () => onProduct!(group),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$rank. ${group.name} · ${group.productId.value.substring(0, 8)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(group.branch.name),
              if (group.branch.address != null) Text(group.branch.address!),
              Text(
                '${formatCents(group.totalCents)} €',
                style: TextStyle(
                  color: group.totalCents.isNegative ? colors.error : null,
                ),
              ),
              Text(
                '${s.productRankingCounts}: ${group.rowCount} / ${group.receiptCount} / ${group.returnRows}',
              ),
              if (group.returnRows > 0)
                Text(
                  '${s.productRankingReturnNet}: ${formatCents(group.returnCents)} €',
                ),
              ExcludeSemantics(
                child: SizedBox(
                  height: 16,
                  child: LayoutBuilder(
                    builder: (context, size) {
                      final fraction = maximum == BigInt.zero
                          ? 0.0
                          : (group.totalCents.abs() *
                                        BigInt.from(1000000) ~/
                                        maximum)
                                    .toDouble() /
                                1000000;
                      final width = size.maxWidth * fraction / 2,
                          zero = size.maxWidth / 2;
                      return Stack(
                        children: [
                          Positioned(
                            left: zero,
                            top: 0,
                            bottom: 0,
                            width: 1,
                            child: ColoredBox(color: colors.outline),
                          ),
                          if (group.totalCents != BigInt.zero)
                            Positioned(
                              left: group.totalCents.isNegative
                                  ? zero - width
                                  : zero,
                              width: width,
                              top: 2,
                              bottom: 2,
                              child: ColoredBox(
                                color: group.totalCents.isNegative
                                    ? colors.error
                                    : colors.primary,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
