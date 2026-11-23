import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

import 'l10n/generated/app_localizations.dart';

/// Complete selected-range branch nets. The donut's denominator is explicitly
/// positive branch nets, never the overall signed total or gross purchases.
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
    final positive = data.branches
        .where((b) => b.totals.totalCents > BigInt.zero)
        .toList();
    final palette = <Color>[
      colors.primary,
      Colors.blue.shade700,
      Colors.amber.shade800,
      Colors.deepPurple.shade500,
      Colors.green.shade700,
      Colors.cyan.shade700,
      Colors.brown.shade500,
      Colors.indigo.shade400,
    ];
    final slices = <_StoreSlice>[
      for (var i = 0; i < math.min(8, positive.length); i++)
        _StoreSlice(positive[i].branch.name, [positive[i]], palette[i]),
      if (positive.length > 8)
        _StoreSlice(
          s.storeOthers,
          positive.sublist(8),
          colors.outline,
          grouped: true,
        ),
    ];
    void open(_StoreSlice slice) {
      if (!slice.grouped) {
        onBranch(slice.branches.single.branch);
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s.storeOthers),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final branch in slice.branches)
                    ListTile(
                      key: ValueKey('store-other-${branch.branch.id.value}'),
                      title: Text(branch.branch.name),
                      subtitle: Text(
                        '${formatCents(branch.totals.totalCents)} € · ${_share(branch.totals.totalCents, data.positiveBranchNet)}',
                      ),
                      onTap: () {
                        Navigator.pop(dialogContext);
                        onBranch(branch.branch);
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(s.catalogClose),
            ),
          ],
        ),
      );
    }

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
          if (data.branches.length == 1) Text(s.storeSingle),
          const SizedBox(height: 12),
          Text(
            s.storeSharesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(s.storeSharesNotice),
          if (data.positiveBranchNet == BigInt.zero)
            Text(s.storeNoPositive, key: const Key('store-no-positive'))
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final ring = Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: 216,
                      height: 216,
                      child: _StoreRing(
                        slices: slices,
                        total: data.positiveBranchNet,
                        onSlice: open,
                      ),
                    ),
                  ),
                );
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${s.storePositiveNet}: ${formatCents(data.positiveBranchNet)} €',
                      key: const Key('store-positive-total'),
                    ),
                    for (final slice in slices)
                      TextButton(
                        key: Key(
                          !slice.grouped
                              ? 'store-share-${slice.branches.single.branch.id.value}'
                              : 'store-share-others',
                        ),
                        onPressed: () => open(slice),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              color: slice.color,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${slice.name}: ${formatCents(slice.cents)} € · ${_share(slice.cents, data.positiveBranchNet)}',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                return constraints.maxWidth >= 650
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ring,
                          const SizedBox(width: 16),
                          Expanded(child: legend),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [ring, legend],
                      );
              },
            ),
          Text(
            '${s.storeNegativeNet}: ${formatCents(data.negativeBranchNet)} €',
            key: const Key('store-negative-total'),
          ),
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

String _share(BigInt cents, BigInt denominator) {
  final tenths = roundSpendingRatio(cents * BigInt.from(1000), denominator);
  if (tenths == BigInt.zero && cents > BigInt.zero) return '<0,1 %';
  final text = tenths.toString().padLeft(2, '0');
  return '${text.substring(0, text.length - 1)},${text.substring(text.length - 1)} %';
}

double _fraction(BigInt value, BigInt total) => total == BigInt.zero
    ? 0
    : ((value * BigInt.from(1000000000)) ~/ total).toInt() / 1000000000;

class _StoreSlice {
  _StoreSlice(this.name, this.branches, this.color, {this.grouped = false});
  final String name;
  final List<BranchSpending> branches;
  final Color color;
  final bool grouped;
  BigInt get cents =>
      branches.fold(BigInt.zero, (sum, b) => sum + b.totals.totalCents);
}

class _StoreRing extends StatelessWidget {
  const _StoreRing({
    required this.slices,
    required this.total,
    required this.onSlice,
  });
  final List<_StoreSlice> slices;
  final BigInt total;
  final void Function(_StoreSlice) onSlice;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = constraints.maxWidth;
      return GestureDetector(
        key: const Key('store-share-ring'),
        onTapUp: (details) {
          final offset = details.localPosition - Offset(side / 2, side / 2);
          final radius = side / 2 - 18;
          if ((offset.distance - radius).abs() > 17) return;
          final angle =
              (math.atan2(offset.dy, offset.dx) + math.pi / 2 + 2 * math.pi) %
              (2 * math.pi);
          var end = 0.0;
          for (var i = 0; i < slices.length; i++) {
            end += _fraction(slices[i].cents, total) * 2 * math.pi;
            if (angle < end || i == slices.length - 1) {
              onSlice(slices[i]);
              break;
            }
          }
        },
        child: CustomPaint(
          painter: _StoreRingPainter(slices, total),
          child: Center(
            child: SizedBox(
              width: side - 88,
              child: Text(
                '${formatCents(total)} €',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _StoreRingPainter extends CustomPainter {
  const _StoreRingPainter(this.slices, this.total);
  final List<_StoreSlice> slices;
  final BigInt total;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 18,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = i == slices.length - 1
          ? math.pi * 1.5 - start
          : _fraction(slices[i].cents, total) * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = slices[i].color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 32,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StoreRingPainter old) =>
      old.slices != slices || old.total != total;
}

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
