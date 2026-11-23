import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;

import 'l10n/generated/app_localizations.dart';
import 'receipt_format.dart';

/// Full-range signed product subtotals; independent of quantity/price coverage.
class ProductSpendingTrendView extends StatelessWidget {
  const ProductSpendingTrendView({
    super.key,
    required this.summary,
    this.onRange,
  });
  final PurchaseSummary summary;
  final ValueChanged<PurchaseDateRange>? onRange;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final buckets = summary.spendingBuckets;
    if (buckets.isEmpty) return const SizedBox();
    String day(int value) => receiptDateText(purchaseCalendarDate(value));
    return Column(
      key: const Key('purchase-spending-trend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          s.purchaseSpendingTrend,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(s.purchaseSpendingPolicy),
        ExcludeSemantics(
          child: SizedBox(
            height: 140,
            child: CustomPaint(
              key: const Key('purchase-spending-chart'),
              painter: _SpendingPainter(
                buckets,
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.error,
                Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ),
        Text('${day(buckets.first.firstDay)} → ${day(buckets.last.lastDay)}'),
        ExpansionTile(
          key: const Key('purchase-spending-details'),
          title: Text(s.purchaseSpendingDetails),
          children: [
            for (final bucket in buckets)
              TextButton(
                key: ValueKey('purchase-spending-range-${bucket.firstDay}'),
                onPressed: bucket.count == 0 || onRange == null
                    ? null
                    : () => onRange!(
                        PurchaseDateRange(
                          fromDate: purchaseCalendarDate(bucket.firstDay),
                          throughDate: purchaseCalendarDate(bucket.lastDay),
                        ),
                      ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${day(bucket.firstDay)}–${day(bucket.lastDay)}: ${formatCents(bucket.effectiveCents)} €\n'
                    '${bucket.count == 0 ? s.purchasePeriodEmpty : '${s.purchasePeriodRows}: ${bucket.count}, ${s.purchasePeriodReturns}: ${bucket.returnRows}'}',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpendingPainter extends CustomPainter {
  _SpendingPainter(this.buckets, this.positive, this.negative, this.axis);
  final List<PurchaseSpendingBucket> buckets;
  final Color positive, negative, axis;
  @override
  void paint(Canvas canvas, Size size) {
    var maximum = BigInt.zero;
    for (final b in buckets) {
      if (b.effectiveCents.abs() > maximum) maximum = b.effectiveCents.abs();
    }
    final baseline = size.height / 2;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()..color = axis,
    );
    final step = size.width / buckets.length;
    for (var i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      if (b.count == 0) continue;
      final scaled = maximum == BigInt.zero
          ? 0.0
          : (b.effectiveCents.abs() * BigInt.from(1000000) ~/ maximum)
                    .toDouble() /
                1000000;
      final height = (baseline - 6) * scaled;
      final x = (i + .5) * step;
      final paint = Paint()
        ..color = b.effectiveCents.isNegative ? negative : positive;
      if (b.effectiveCents == BigInt.zero) {
        canvas.drawLine(
          Offset(x - step * .3, baseline - 2),
          Offset(x + step * .3, baseline - 2),
          paint..strokeWidth = 3,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(
            x - step * .3,
            b.effectiveCents.isNegative ? baseline : baseline - height,
            step * .6,
            height,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpendingPainter old) =>
      old.buckets != buckets ||
      old.positive != positive ||
      old.negative != negative ||
      old.axis != axis;
}
