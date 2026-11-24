import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show formatCents;

import 'dashboard_help.dart';
import 'l10n/generated/app_localizations.dart';

enum SpendingBreakdownMode { product, branch }

class SpendingBreakdownView extends StatelessWidget {
  const SpendingBreakdownView({
    super.key,
    required this.data,
    required this.mode,
    required this.onMode,
    this.onProduct,
    required this.onBranch,
    this.onAllProducts,
  });
  final SpendingDashboard data;
  final SpendingBreakdownMode mode;
  final ValueChanged<SpendingBreakdownMode> onMode;
  final ValueChanged<ProductSpending>? onProduct;
  final ValueChanged<ReceiptBranch> onBranch;
  final VoidCallback? onAllProducts;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final byProduct = mode == SpendingBreakdownMode.product;
    final entries = <_Entry>[];
    var negative = BigInt.zero;
    if (byProduct) {
      final names = <(DurableId, String), int>{};
      for (final p in data.products.groups) {
        final key = (p.branch.id, p.name);
        names[key] = (names[key] ?? 0) + 1;
      }
      for (final p in data.products.groups) {
        if (p.totalCents < BigInt.zero) negative += p.totalCents;
        if (p.totalCents <= BigInt.zero) continue;
        entries.add(
          _Entry(
            'breakdown-product-${p.productId.value}',
            '${p.name}${names[(p.branch.id, p.name)]! > 1 ? ' · ${p.productId.value.substring(0, 8)}' : ''}',
            p.branch.name,
            p.totalCents,
            onProduct == null ? null : () => onProduct!(p),
          ),
        );
      }
    } else {
      negative = data.negativeBranchNet;
      for (final b in data.branches) {
        if (b.totals.totalCents <= BigInt.zero) continue;
        entries.add(
          _Entry(
            'store-share-${b.branch.id.value}',
            b.branch.name,
            b.branch.address,
            b.totals.totalCents,
            () => onBranch(b.branch),
          ),
        );
      }
    }
    final total = entries.fold(BigInt.zero, (sum, e) => sum + e.cents);
    final limit = byProduct ? 5 : 8;
    final palette = [
      colors.primary,
      Colors.blue.shade700,
      Colors.amber.shade800,
      Colors.deepPurple.shade500,
      Colors.green.shade700,
      Colors.cyan.shade700,
      Colors.brown.shade500,
      Colors.indigo.shade400,
    ];
    final slices = [
      for (var i = 0; i < math.min(limit, entries.length); i++)
        _Slice(entries[i].name, [entries[i]], palette[i], entries[i].key),
      if (entries.length > limit)
        _Slice(
          s.storeOthers,
          entries.sublist(limit),
          colors.outline,
          byProduct ? 'breakdown-product-others' : 'store-share-others',
          grouped: true,
        ),
    ];
    void open(_Slice slice) {
      if (!slice.grouped) {
        slice.entries.single.open?.call();
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(s.storeOthers),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in slice.entries)
                    ListTile(
                      key: ValueKey(
                        byProduct
                            ? entry.key.replaceFirst(
                                'breakdown-product-',
                                'breakdown-other-product-',
                              )
                            : entry.key.replaceFirst(
                                'store-share-',
                                'store-other-',
                              ),
                      ),
                      title: Text(entry.name),
                      subtitle: Text(
                        '${entry.subtitle == null ? '' : '${entry.subtitle} · '}${formatCents(entry.cents)} € · ${_share(entry.cents, total)}',
                      ),
                      onTap: entry.open == null
                          ? null
                          : () {
                              Navigator.pop(dialogContext);
                              entry.open!();
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

    final caption = byProduct
        ? s.dashboardProductShares
        : s.dashboardBranchShares;
    final limited = byProduct && data.products.limitExceeded;
    return Card(
      key: const Key('dashboard-breakdown'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.dashboardBreakdown,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DashboardInfoButton(
                  key: const Key('dashboard-breakdown-info'),
                  title: s.dashboardBreakdown,
                  paragraphs: [
                    byProduct
                        ? s.dashboardProductShareHelp
                        : s.dashboardBranchShareHelp,
                    if (byProduct)
                      '${s.productRankingCoverage}: ${data.products.linkedRows} / ${data.products.productRows}',
                    if (byProduct)
                      '${s.productRankingLinked}: ${formatCents(data.products.linkedCents)} €',
                    if (byProduct)
                      '${s.productRankingUnlinked}: ${formatCents(data.products.unlinkedCents)} €',
                    if (byProduct) s.productRankingAttribution,
                    if (byProduct)
                      '${s.categoryDeposits}: ${formatCents(data.products.depositCents)} €',
                    if (byProduct)
                      '${s.categoryReceiptDiscounts}: ${formatCents(data.products.receiptDiscountCents)} €',
                    if (byProduct)
                      '${s.categoryAdjustments}: ${formatCents(data.products.adjustmentCents)} €',
                  ],
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final value in SpendingBreakdownMode.values)
                  ChoiceChip(
                    key: ValueKey('breakdown-${value.name}'),
                    selected: mode == value,
                    onSelected: (_) => onMode(value),
                    label: Text(
                      value == SpendingBreakdownMode.product
                          ? s.dashboardByProduct
                          : s.dashboardByBranch,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (limited)
              Text(
                s.productRankingLimit,
                key: const Key('product-ranking-limit'),
              )
            else if (total == BigInt.zero)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  !byProduct && data.branches.isEmpty
                      ? s.storeEmpty
                      : s.dashboardSharesNoPositive,
                  key: Key(
                    byProduct ? 'product-no-positive' : 'store-no-positive',
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final ring = Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: _ShareRing(
                        slices,
                        total,
                        open,
                        key: Key(
                          byProduct ? 'product-share-ring' : 'store-share-ring',
                        ),
                      ),
                    ),
                  );
                  final legend = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final slice in slices)
                        TextButton(
                          key: ValueKey(slice.key),
                          onPressed:
                              slice.grouped || slice.entries.single.open != null
                              ? () => open(slice)
                              : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  right: 8,
                                ),
                                child: ColoredBox(
                                  color: slice.color,
                                  child: const SizedBox(width: 10, height: 10),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${slice.name}: ${formatCents(slice.cents)} € · ${_share(slice.cents, total)}',
                                    ),
                                    if (!slice.grouped &&
                                        slice.entries.single.subtitle != null)
                                      Text(
                                        slice.entries.single.subtitle!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                  return constraints.maxWidth >= 620
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(width: 224, child: ring),
                            const SizedBox(width: 12),
                            Expanded(child: legend),
                          ],
                        )
                      : Column(children: [ring, legend]);
                },
              ),
            if (!limited && total > BigInt.zero)
              Text(
                '$caption: ${formatCents(total)} €',
                key: Key(
                  byProduct ? 'product-positive-total' : 'store-positive-total',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (negative < BigInt.zero)
              Text(
                '${byProduct ? s.dashboardNegativeShares : s.storeNegativeNet}: ${formatCents(negative)} €',
                key: Key(
                  byProduct ? 'product-negative-total' : 'store-negative-total',
                ),
                style: TextStyle(color: colors.error),
              ),
            if (byProduct && data.products.unlinkedCents != BigInt.zero)
              Text(
                '${s.dashboardUnlinkedShort}: ${formatCents(data.products.unlinkedCents)} €',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (byProduct && !limited && data.products.groups.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('product-ranking-all'),
                  onPressed: onAllProducts,
                  child: Text(s.productRankingAll),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Entry {
  _Entry(this.key, this.name, this.subtitle, this.cents, this.open);
  final String key, name;
  final String? subtitle;
  final BigInt cents;
  final VoidCallback? open;
}

class _Slice {
  _Slice(this.name, this.entries, this.color, this.key, {this.grouped = false});
  final String name, key;
  final List<_Entry> entries;
  final Color color;
  final bool grouped;
  BigInt get cents => entries.fold(BigInt.zero, (sum, e) => sum + e.cents);
}

double _fraction(BigInt value, BigInt total) =>
    (value * BigInt.from(1000000000) ~/ total).toDouble() / 1000000000;
String _share(BigInt value, BigInt total) {
  final tenths = roundSpendingRatio(value * BigInt.from(1000), total);
  if (tenths == BigInt.zero && value > BigInt.zero) return '<0,1 %';
  final text = tenths.toString().padLeft(2, '0');
  return '${text.substring(0, text.length - 1)},${text.substring(text.length - 1)} %';
}

class _ShareRing extends StatelessWidget {
  const _ShareRing(this.slices, this.total, this.open, {super.key});
  final List<_Slice> slices;
  final BigInt total;
  final ValueChanged<_Slice> open;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => GestureDetector(
      onTapUp: (details) {
        final p =
            details.localPosition -
            Offset(size.maxWidth / 2, size.maxWidth / 2);
        if ((p.distance - (size.maxWidth / 2 - 16)).abs() > 16) return;
        final angle =
            (math.atan2(p.dy, p.dx) + math.pi / 2 + 2 * math.pi) %
            (2 * math.pi);
        var end = 0.0;
        for (var i = 0; i < slices.length; i++) {
          end += _fraction(slices[i].cents, total) * 2 * math.pi;
          if (angle < end || i == slices.length - 1) {
            open(slices[i]);
            break;
          }
        }
      },
      child: CustomPaint(
        painter: _RingPainter(slices, total),
        child: Center(
          child: SizedBox(
            width: size.maxWidth - 76,
            child: Text(
              '${formatCents(total)} €',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.slices, this.total);
  final List<_Slice> slices;
  final BigInt total;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 16,
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
          ..strokeWidth = 28,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.slices != slices || old.total != total;
}
