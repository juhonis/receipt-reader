import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';

import 'catalog_service.dart';
import 'local_store.dart';
import 'purchase_history_service.dart';
import 'purchase_history_page.dart';
import 'receipt_format.dart';
import 'spending_service.dart';
import 'product_spending_view.dart';
import 'l10n/generated/app_localizations.dart';

bool canOpenRankedProduct(LocalStore store) =>
    store is CatalogService && store is PurchaseHistoryService;

/// A fresh product read supplies navigation metadata; the selected receipt scope
/// always comes from the displayed ranking, never the currently edited controls.
Future<bool> openRankedProduct(
  BuildContext context,
  LocalStore store,
  ProductSpending product,
  SpendingPeriod period, {
  required bool Function() isCurrent,
}) async {
  if (!canOpenRankedProduct(store)) return false;
  try {
    final record = await (store as CatalogService).readProduct(
      product.productId,
    );
    if (!context.mounted ||
        !isCurrent() ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    if (record == null ||
        record.document.product.id != product.productId ||
        record.document.product.storeId != product.branch.id) {
      throw StateError('missingProduct');
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseHistoryPage(
          store: store,
          service: store as PurchaseHistoryService,
          product: record,
          branchName: product.branch.name,
          initialRange: PurchaseDateRange(
            fromDate: purchaseCalendarDate(period.firstDay),
            throughDate: purchaseCalendarDate(period.lastDay),
          ),
        ),
      ),
    );
    return true;
  } catch (_) {
    if (context.mounted &&
        isCurrent() &&
        ModalRoute.of(context)?.isCurrent != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.productRankingOpenFailed),
        ),
      );
    }
    return false;
  }
}

class ProductRankingsPage extends StatefulWidget {
  const ProductRankingsPage({
    super.key,
    required this.store,
    required this.service,
    required this.initialData,
    this.branchName,
  });
  final LocalStore store;
  final SpendingDashboardService service;
  final SpendingDashboard initialData;
  final String? branchName;
  @override
  State<ProductRankingsPage> createState() => _ProductRankingsPageState();
}

class _ProductRankingsPageState extends State<ProductRankingsPage> {
  late Future<SpendingDashboard> _result = Future.value(widget.initialData);
  int _offset = 0;
  bool _opening = false;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _offset = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _result = widget.service.spendingDashboard(widget.initialData.query)
      ..ignore();
  });
  void _page(int offset) => setState(() {
    _offset = offset;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  });
  Future<void> _open(ProductSpending product, SpendingDashboard data) async {
    if (_opening) return;
    final request = _result;
    setState(() => _opening = true);
    final opened = await openRankedProduct(
      context,
      widget.store,
      product,
      data.query.selected,
      isCurrent: () => mounted && _result == request,
    );
    if (mounted) {
      setState(() => _opening = false);
      if (opened) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final period = widget.initialData.query.selected;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.productRankingListTitle),
        actions: [
          IconButton(
            key: const Key('product-rankings-refresh'),
            tooltip: s.refreshHistory,
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: FutureBuilder<SpendingDashboard>(
              future: _result,
              key: ObjectKey(_result),
              builder: (context, snapshot) {
                final data = snapshot.data, summary = data?.products;
                final groups = summary?.groups ?? const <ProductSpending>[];
                final page = groups.skip(_offset).take(30).toList();
                final maximum = summary == null
                    ? BigInt.zero
                    : productRankingMaximum(summary);
                return ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(widget.branchName ?? s.historyAllBranches),
                    Text(
                      '${receiptDateText(purchaseCalendarDate(period.firstDay))}–${receiptDateText(purchaseCalendarDate(period.lastDay))}',
                      key: const Key('product-rankings-range'),
                    ),
                    Text(s.productRankingScope),
                    if (snapshot.hasError)
                      TextButton(
                        key: const Key('product-rankings-retry'),
                        onPressed: _reload,
                        child: Text(s.spendingFailed),
                      )
                    else if (data == null)
                      const LinearProgressIndicator()
                    else ...[
                      ProductRankingCoverage(summary: summary!),
                      if (summary.limitExceeded)
                        Text(s.productRankingLimit)
                      else if (groups.isEmpty)
                        Text(s.productRankingEmpty)
                      else ...[
                        Text(
                          '${s.productRankingRows}: ${_offset + 1}–${_offset + page.length} / ${groups.length}',
                          key: const Key('product-rankings-page'),
                        ),
                        for (var i = 0; i < page.length; i++)
                          ProductRankingRow(
                            group: page[i],
                            rank: _offset + i + 1,
                            maximum: maximum,
                            prefix: 'ranked-product',
                            onProduct:
                                !_opening && canOpenRankedProduct(widget.store)
                                ? (product) => _open(product, data)
                                : null,
                          ),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              key: const Key('product-rankings-previous'),
                              onPressed: _offset == 0
                                  ? null
                                  : () => _page(math.max(0, _offset - 30)),
                              child: Text(s.catalogPrevious),
                            ),
                            TextButton(
                              key: const Key('product-rankings-next'),
                              onPressed: _offset + page.length >= groups.length
                                  ? null
                                  : () => _page(_offset + 30),
                              child: Text(s.catalogNext),
                            ),
                          ],
                        ),
                      ],
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
}
