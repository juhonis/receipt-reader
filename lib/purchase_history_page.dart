import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'history_page.dart';
import 'local_store.dart';
import 'product_picker.dart';
import 'purchase_history_service.dart';
import 'receipt_format.dart';
import 'l10n/generated/app_localizations.dart';

String _unit(QuantityUnit unit) => switch (unit) {
  QuantityUnit.piece => 'kpl',
  QuantityUnit.kg => 'kg',
  QuantityUnit.litre => 'l',
  QuantityUnit.unknown => '?',
};
String _revision(RevisionId revision) =>
    '${revision.origin.value} / ${revision.sequence}';

class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({
    super.key,
    required this.store,
    required this.service,
    required this.product,
    required this.branchName,
  });
  final LocalStore store;
  final PurchaseHistoryService service;
  final StoredProduct product;
  final String branchName;
  @override
  State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage> {
  int _offset = 0;
  late Future<List<StoredProductPurchase>> _items = _load();
  Future<List<StoredProductPurchase>> _load() => widget.service.purchases(
    widget.product.document.product.storeId,
    widget.product.document.product.id,
    offset: _offset,
  );
  void _reload() => setState(() {
    _items = _load();
  });
  Future<void> _open(StoredProductPurchase item) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReceiptDetailPage(receipt: item.receipt, store: widget.store),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.purchaseHistory),
        actions: [
          IconButton(
            key: const Key('purchases-refresh'),
            onPressed: _reload,
            tooltip: s.refreshHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: FutureBuilder<List<StoredProductPurchase>>(
              key: ObjectKey(_items),
              future: _items,
              builder: (context, result) {
                final items = result.data;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.branchName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${s.purchaseCurrentProduct}: ${productLabel(widget.product)}',
                    ),
                    const SizedBox(height: 12),
                    Text(s.purchasePolicy),
                    if (result.hasError)
                      TextButton(
                        key: const Key('purchases-retry'),
                        onPressed: _reload,
                        child: Text(s.purchaseLoadFailed),
                      )
                    else if (items == null)
                      const LinearProgressIndicator()
                    else ...[
                      if (items.isEmpty) Text(s.purchaseEmpty),
                      if (items.isNotEmpty) ...[
                        Text(
                          '${s.purchaseRows}: ${_offset + 1}–${_offset + items.length}',
                        ),
                        Text(s.purchasePageScope),
                        Text(s.purchasePiecePolicy),
                        ..._charts(context, items),
                      ],
                      for (final item in items) _observation(context, item),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            key: const Key('purchases-previous'),
                            onPressed: _offset == 0
                                ? null
                                : () {
                                    _offset -= 30;
                                    _reload();
                                  },
                            child: Text(s.catalogPrevious),
                          ),
                          TextButton(
                            key: const Key('purchases-next'),
                            onPressed: items.length < 30
                                ? null
                                : () {
                                    _offset += 30;
                                    _reload();
                                  },
                            child: Text(s.catalogNext),
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

  List<Widget> _charts(
    BuildContext context,
    List<StoredProductPurchase> items,
  ) {
    final s = AppLocalizations.of(context)!;
    final groups = <(QuantityUnit, RevisionId?), List<ProductPurchase>>{};
    for (final item in items.reversed) {
      final group = item.purchase.comparisonGroup;
      if (group != null) groups.putIfAbsent(group, () => []).add(item.purchase);
    }
    return [
      for (final entry in groups.entries)
        Builder(
          builder: (context) {
            final observations = entry.value;
            final prices = observations
                .map((p) => p.effectiveUnitPrice!)
                .toList();
            final sorted = [...prices]..sort();
            final unit = _unit(entry.key.$1);
            final label = '${s.purchaseUnitPrice} (€/$unit)';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    if (entry.key.$2 case final revision?)
                      Text('${s.purchaseVersion}: ${_revision(revision)}'),
                    Text('${s.purchaseChartCount}: ${prices.length}'),
                    Text(
                      '${s.purchaseRange}: ${sorted.first.euros}–${sorted.last.euros} €/$unit',
                    ),
                    if (observations.any(
                      (p) => p.receiptDiscountCents != BigInt.zero,
                    ))
                      Text(s.purchaseReceiptDiscount),
                    if (observations.any((p) => p.hasReceiptAdjustment))
                      Text(s.purchaseAdjustment),
                    if (prices.length == 1)
                      Text(s.purchaseChartSingle)
                    else ...[
                      ExcludeSemantics(
                        child: SizedBox(
                          height: 120,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _PricePainter(
                              prices,
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '${receiptDateText(observations.first.date)} → ${receiptDateText(observations.last.date)}',
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }

  Widget _observation(BuildContext context, StoredProductPurchase item) {
    final s = AppLocalizations.of(context)!;
    final p = item.purchase, row = p.row;
    final price = p.effectiveUnitPrice;
    return Card(
      key: ValueKey('purchase-row-${row.id.value}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              receiptDateText(p.date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(row.name),
            if (row.rawName != null) Text(row.rawName!),
            Text('${s.purchaseRaw}: ${formatCents(row.cents)} €'),
            Text(
              '${s.purchaseDiscount}: ${formatCents(p.itemDiscountCents)} €',
            ),
            Text('${s.purchaseDeposit}: ${formatCents(p.depositCents)} €'),
            Text('${s.purchaseEffective}: ${formatCents(p.effectiveCents)} €'),
            if (row.quantityValue != null) ...[
              Text(
                '${s.purchaseQuantity}: ${formatFixed(row.quantityValue!, row.quantityScale!)} ${_unit(row.quantityUnit!)}',
              ),
              Text(
                '${s.purchasePrintedRate}: ${formatFixed(row.rateMicros!, 6)} €/${_unit(row.quantityUnit!)}',
              ),
            ],
            if (price != null)
              Text(
                '${s.purchaseUnitPrice}: ${price.euros} €/${_unit(row.quantityUnit!)}',
              )
            else
              Text(
                p.isReturn
                    ? s.purchaseReturn
                    : row.quantityValue == null
                    ? s.purchaseNoQuantity
                    : s.purchaseNegative,
              ),
            if (p.receiptDiscountCents != BigInt.zero)
              Text(s.purchaseReceiptDiscount),
            if (p.hasReceiptAdjustment) Text(s.purchaseAdjustment),
            Text('${s.purchaseVersion}: ${_revision(row.product!.revision)}'),
            TextButton(
              onPressed: () => _open(item),
              child: Text(s.purchaseOpenReceipt),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricePainter extends CustomPainter {
  _PricePainter(this.prices, this.color);
  final List<UnitPrice> prices;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final sorted = [...prices]..sort();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < prices.length; i++) {
      final x = 6 + (size.width - 12) * i / (prices.length - 1);
      final y =
          6 +
          (size.height - 12) *
              (1 - prices[i].positionBetween(sorted.first, sorted.last));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PricePainter oldDelegate) =>
      oldDelegate.prices != prices || oldDelegate.color != color;
}
