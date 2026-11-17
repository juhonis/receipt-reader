import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';
import 'receipt_format.dart';

String _unit(QuantityUnit unit) => switch (unit) {
  QuantityUnit.piece => 'kpl',
  QuantityUnit.kg => 'kg',
  QuantityUnit.litre => 'l',
  QuantityUnit.unknown => '?',
};
String _day(int day) => receiptDateText(purchaseCalendarDate(day));

class PurchaseSummaryView extends StatelessWidget {
  const PurchaseSummaryView({super.key, required this.summary});
  final PurchaseSummary summary;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.purchaseSummaryTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(s.purchaseRangeScope),
        if (summary.firstDay != null)
          Text('${_day(summary.firstDay!)} – ${_day(summary.lastDay!)}'),
        Text('${s.purchaseTotalRows}: ${summary.totalRows}'),
        Text('${s.purchaseComparableRows}: ${summary.comparableRows}'),
        Text('${s.purchaseReturnRows}: ${summary.returnRows}'),
        Text('${s.purchaseMissingRows}: ${summary.missingQuantityRows}'),
        Text('${s.purchaseNegativeRows}: ${summary.negativeEffectiveRows}'),
        Text('${s.purchaseDiscountRows}: ${summary.receiptDiscountRows}'),
        Text('${s.purchaseAdjustmentRows}: ${summary.adjustmentRows}'),
        Text('${s.purchaseRawTotal}: ${formatCents(summary.rawCents)} €'),
        Text(
          '${s.purchaseEffectiveTotal}: ${formatCents(summary.effectiveCents)} €',
        ),
        if (summary.receiptDiscountRows > 0) Text(s.purchaseReceiptDiscount),
        if (summary.adjustmentRows > 0) Text(s.purchaseAdjustment),
        if (summary.totalRows > 0 && summary.comparableRows == 0)
          Text(s.purchaseNoComparable),
        if (summary.groups.isNotEmpty) Text(s.purchasePiecePolicy),
        for (final group in summary.groups) _group(context, group),
      ],
    );
  }

  Widget _group(BuildContext context, PurchasePriceGroup group) {
    final s = AppLocalizations.of(context)!;
    final unit = _unit(group.unit);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${s.purchaseUnitPrice} (€/$unit)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (group.productRevision case final revision?)
              Text(
                '${s.purchaseVersion}: ${revision.origin.value} / ${revision.sequence}',
              ),
            Text('${s.purchaseChartCount}: ${group.count}'),
            Text(
              '${s.purchaseRange}: ${group.minimum.euros}–${group.maximum.euros} €/$unit',
            ),
            if (group.receiptDiscountRows > 0) Text(s.purchaseReceiptDiscount),
            if (group.adjustmentRows > 0) Text(s.purchaseAdjustment),
            if (group.count == 1) Text(s.purchaseChartSingle),
            Text(s.purchaseBucketPolicy),
            ExcludeSemantics(
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: _RangePainter(
                    group,
                    summary.firstDay!,
                    summary.lastDay!,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            Text('${_day(summary.firstDay!)} → ${_day(summary.lastDay!)}'),
            ExpansionTile(
              key: ValueKey(
                'purchase-buckets-$unit-${group.productRevision?.origin.value}-${group.productRevision?.sequence}',
              ),
              title: Text(s.purchaseBucketDetails),
              children: [
                for (final bucket in group.buckets)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${_day(bucket.firstDay)}–${_day(bucket.lastDay)}: ${bucket.minimum.euros}–${bucket.maximum.euros} €/$unit (n=${bucket.count})',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical min/max bars. Gaps stay empty; no interpolation or inferred mean.
class _RangePainter extends CustomPainter {
  _RangePainter(this.group, this.firstDay, this.lastDay, this.color);
  final PurchasePriceGroup group;
  final int firstDay, lastDay;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    final span = lastDay - firstDay + 1;
    double y(UnitPrice price) =>
        6 +
        (size.height - 12) *
            (1 - price.positionBetween(group.minimum, group.maximum));
    for (final bucket in group.buckets) {
      final x =
          6 +
          (size.width - 12) *
              ((bucket.firstDay + bucket.lastDay) / 2 - firstDay + 0.5) /
              span;
      final low = y(bucket.minimum), high = y(bucket.maximum);
      canvas.drawLine(Offset(x, low), Offset(x, high), paint);
      canvas.drawLine(Offset(x - 4, low), Offset(x + 4, low), paint);
      canvas.drawLine(Offset(x - 4, high), Offset(x + 4, high), paint);
    }
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.group != group ||
      old.firstDay != firstDay ||
      old.lastDay != lastDay ||
      old.color != color;
}
