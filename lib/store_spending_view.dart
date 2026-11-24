import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';

/// Exact selected-range branch figures and signed bars below the primary pie.
class StoreSpendingView extends StatelessWidget {
  const StoreSpendingView({
    super.key,
    required this.data,
    required this.onBranch,
  });
  final SpendingDashboard data;
  final void Function(ReceiptBranch) onBranch;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    var maxPositive = BigInt.zero, maxNegative = BigInt.zero;
    for (final branch in data.branches) {
      final cents = branch.totals.totalCents;
      if (cents > maxPositive) maxPositive = cents;
      if (-cents > maxNegative) maxNegative = -cents;
    }
    return Column(
      key: const Key('dashboard-stores'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.storeComparisonTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(s.storeScope),
        if (data.branches.isEmpty)
          Text(s.storeEmpty)
        else ...[
          const SizedBox(height: 16),
          Text(s.storeNetTitle, style: Theme.of(context).textTheme.titleMedium),
          Text(s.storeBarNotice),
          for (final branch in data.branches)
            Card(
              child: InkWell(
                key: ValueKey('store-bar-${branch.branch.id.value}'),
                onTap: () => onBranch(branch.branch),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        children: [
                          Text(
                            branch.branch.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('${formatCents(branch.totals.totalCents)} €'),
                        ],
                      ),
                      if (branch.branch.address != null)
                        Text(branch.branch.address!),
                      Text(
                        '${s.spendingCount}: ${branch.totals.receiptCount} · ${s.dashboardAverage}: ${formatCents(averageReceiptCents(branch.totals)!)} €',
                      ),
                      if (branch.totals.negativeReceipts != 0)
                        Text(
                          '${s.spendingNegative}: ${branch.totals.negativeReceipts}',
                        ),
                      const SizedBox(height: 8),
                      ExcludeSemantics(
                        child: SizedBox(
                          height: 22,
                          child: CustomPaint(
                            painter: _StoreBarPainter(
                              cents: branch.totals.totalCents,
                              positive: maxPositive,
                              negative: maxNegative,
                              positiveColor: colors.primary,
                              negativeColor: colors.error,
                              track: colors.surfaceContainerHighest,
                              axis: colors.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

double _fraction(BigInt value, BigInt total) => total == BigInt.zero
    ? 0
    : ((value * BigInt.from(1000000000)) ~/ total).toInt() / 1000000000;

class _StoreBarPainter extends CustomPainter {
  const _StoreBarPainter({
    required this.cents,
    required this.positive,
    required this.negative,
    required this.positiveColor,
    required this.negativeColor,
    required this.track,
    required this.axis,
  });
  final BigInt cents, positive, negative;
  final Color positiveColor, negativeColor, track, axis;
  @override
  void paint(Canvas canvas, Size size) {
    final span = positive + negative;
    final zero = _fraction(negative, span) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = track,
    );
    final end =
        zero +
        (cents.isNegative ? -1 : 1) * _fraction(cents.abs(), span) * size.width;
    if (cents != BigInt.zero) {
      canvas.drawRect(
        Rect.fromLTRB(
          math.min(zero, end),
          3,
          math.max(zero, end),
          size.height - 3,
        ),
        Paint()..color = cents.isNegative ? negativeColor : positiveColor,
      );
    }
    final x = zero.clamp(.5, size.width - .5);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _StoreBarPainter old) =>
      old.cents != cents ||
      old.positive != positive ||
      old.negative != negative ||
      old.positiveColor != positiveColor ||
      old.negativeColor != negativeColor ||
      old.track != track ||
      old.axis != axis;
}
