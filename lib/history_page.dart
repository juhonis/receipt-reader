import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'catalog_service.dart';
import 'product_picker.dart';
import 'history_filter_dialog.dart';
import 'manual_receipt_page.dart';
import 'receipt_format.dart';
import 'receipt_import.dart';
import 'ocr_correction_page.dart';
import 'receipt_deletion_dialog.dart';
import 'category_labels.dart';
import 'receipt_product_links_page.dart';
import 'text_search_field.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.store,
    this.imagePicker = pickReceiptImage,
    this.cameraCapture = captureReceiptImage,
    this.initialSelection,
  });
  final LocalStore store;
  final Future<ReceiptEvidence?> Function() imagePicker;
  final Future<ReceiptEvidence?> Function() cameraCapture;
  final HistoryFilterSelection? initialSelection;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _pageSize = 30;
  final _receipts = <StoredReceipt>[];
  bool _loading = false, _failed = false, _more = true;
  HistoryFilterSelection? _selection;
  int _generation = 0;
  int _searchReset = 0;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading && !refresh) return;
    final generation = refresh ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _failed = false;
      if (refresh) {
        _receipts.clear();
        _more = true;
      }
    });
    try {
      final page = await widget.store.history(
        limit: _pageSize,
        offset: _receipts.length,
        filter: _selection?.filter,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _receipts.addAll(page);
          _more = page.length == _pageSize;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _search(String query) {
    final filter = (_selection?.filter ?? HistoryFilter()).withQuery(query);
    _selection = filter.isEmpty
        ? null
        : HistoryFilterSelection(filter, _selection?.branchName);
    _load(refresh: true);
  }

  Future<void> _filters() async {
    final selection = await showDialog<HistoryFilterSelection>(
      context: context,
      builder: (_) =>
          HistoryFilterDialog(store: widget.store, selection: _selection),
    );
    if (!mounted || selection == null) return;
    _selection = selection.filter.isEmpty ? null : selection;
    await _load(refresh: true);
  }

  String _filterSummary(AppLocalizations s) {
    final filter = _selection!.filter;
    return [
      if (filter.category != null)
        '${s.productCategory}: ${categoryLabel(s, filter.category!)}',
      if (filter.branchId != null)
        '${s.branchLabel}: ${_selection!.branchName}',
      if (filter.fromDate != null)
        '${s.historyFromDate}: ${receiptDateText(filter.fromDate!)}',
      if (filter.throughDate != null)
        '${s.historyThroughDate}: ${receiptDateText(filter.throughDate!)}',
      if (filter.minTotalCents != null)
        '${s.historyMinAmount}: ${formatCents(filter.minTotalCents!)} €',
      if (filter.maxTotalCents != null)
        '${s.historyMaxAmount}: ${formatCents(filter.maxTotalCents!)} €',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final filterSummary = _selection == null ? '' : _filterSummary(s);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.historyTitle),
        actions: [
          IconButton(
            key: const Key('history-refresh'),
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
            tooltip: s.refreshHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(s.historyNotice),
                TextSearchField(
                  key: ValueKey(_searchReset),
                  fieldKey: 'history-search',
                  value: _selection?.filter.query ?? '',
                  label: s.receiptSearch,
                  hint: s.receiptSearchHint,
                  onChanged: _search,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('history-filters'),
                      onPressed: _loading ? null : _filters,
                      icon: const Icon(Icons.filter_list),
                      label: Text(s.historyFilters),
                    ),
                    if (_selection != null)
                      TextButton(
                        key: const Key('history-reset'),
                        onPressed: _loading
                            ? null
                            : () {
                                _selection = null;
                                _searchReset++;
                                _load(refresh: true);
                              },
                        child: Text(s.historyResetFilters),
                      ),
                  ],
                ),
                if (filterSummary.isNotEmpty)
                  Text(filterSummary, key: const Key('history-filter-summary')),
                if (_selection?.filter.category != null)
                  Text(s.categoryHistoryNotice),
                if (!_loading && !_failed && _receipts.isEmpty)
                  Text(
                    _selection == null ? s.historyEmpty : s.historyNoMatches,
                  ),
                for (final receipt in _receipts)
                  ListTile(
                    key: ValueKey(
                      'history-${receipt.document.snapshot.id.value}',
                    ),
                    title: Text(receipt.document.snapshot.branch.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(receiptDateText(receipt.document.snapshot.date)),
                        Text(
                          '${formatCents(receipt.document.snapshot.totalCents)} €',
                        ),
                        if ((_selection?.filter.query.trim() ?? '').isNotEmpty)
                          Text(
                            receipt.document.snapshot.items
                                .map((item) => item.name)
                                .take(3)
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (_) => ReceiptDetailPage(
                            receipt: receipt,
                            store: widget.store,
                            imagePicker: widget.imagePicker,
                            cameraCapture: widget.cameraCapture,
                          ),
                        ),
                      );
                      if (mounted) {
                        await _load(refresh: true);
                      }
                    },
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (_failed) Text(s.historyFailed),
                if (!_loading && (_more || _failed))
                  TextButton(
                    key: const Key('history-more'),
                    onPressed: _load,
                    child: Text(_failed ? s.retryAction : s.moreHistory),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReceiptDetailPage extends StatelessWidget {
  const ReceiptDetailPage({
    super.key,
    required this.receipt,
    required this.store,
    this.imagePicker = pickReceiptImage,
    this.cameraCapture = captureReceiptImage,
  });
  final StoredReceipt receipt;
  final LocalStore store;
  final Future<ReceiptEvidence?> Function() imagePicker;
  final Future<ReceiptEvidence?> Function() cameraCapture;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final snapshot = receipt.document.snapshot;
    final kinds = {
      LineKind.product: s.productKind,
      LineKind.discount: s.discountKind,
      LineKind.deposit: s.depositKind,
      LineKind.adjustment: s.adjustmentKind,
    };
    return Scaffold(
      appBar: AppBar(title: Text(s.savedReceiptTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  snapshot.branch.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(receiptDateText(snapshot.date)),
                Text('${formatCents(snapshot.totalCents)} €'),
                Text(
                  receipt.document.review.source == 'ocr'
                      ? s.savedOcrNotice
                      : s.savedManualNotice,
                ),
                if (store is CatalogService &&
                    snapshot.items.any((r) => r.kind == LineKind.product))
                  OutlinedButton.icon(
                    key: const Key('edit-product-links'),
                    onPressed: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (_) => ReceiptProductLinksPage(
                            store: store,
                            catalog: store as CatalogService,
                            receipt: receipt,
                          ),
                        ),
                      );
                      if (context.mounted && changed == true) {
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.link),
                    label: Text(s.productLinksTitle),
                  ),
                if (receipt.document.review.source == 'manual')
                  OutlinedButton.icon(
                    key: const Key('edit-manual-receipt'),
                    onPressed: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (_) => ManualReceiptPage.correction(
                            store: store,
                            receipt: receipt,
                          ),
                        ),
                      );
                      // A pending command may have committed. Always return to
                      // fresh history after save or explicit uncertain exit.
                      if (context.mounted && changed == true) {
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(s.correctManualReceipt),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('edit-ocr-receipt'),
                    onPressed: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (_) => OcrCorrectionPage(
                            store: store,
                            receipt: receipt,
                            imagePicker: imagePicker,
                            cameraCapture: cameraCapture,
                          ),
                        ),
                      );
                      if (context.mounted && changed == true) {
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(s.correctOcrReceipt),
                  ),
                OutlinedButton.icon(
                  key: const Key('delete-receipt'),
                  onPressed: () async {
                    final changed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          ReceiptDeletionDialog(receipt: receipt, store: store),
                    );
                    if (context.mounted && changed == true) {
                      Navigator.pop(context, true);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(s.deleteReceiptAction),
                ),
                for (var i = 0; i < snapshot.items.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.manualRowNumber(i + 1)),
                          Text(snapshot.items[i].name),
                          if (snapshot.items[i].kind == LineKind.product &&
                              store is CatalogService)
                            if (snapshot.items[i].product == null)
                              Text(s.productUnlinked)
                            else
                              ProductLinkLabel(
                                service: store as CatalogService,
                                link: snapshot.items[i].product!,
                                editable: true,
                              ),
                          Text(kinds[snapshot.items[i].kind]!),
                          Text('${formatCents(snapshot.items[i].cents)} €'),
                          if (snapshot.items[i].quantityValue != null)
                            Text(
                              '${formatFixed(snapshot.items[i].quantityValue!, snapshot.items[i].quantityScale!)} '
                              '${switch (snapshot.items[i].quantityUnit!) {
                                QuantityUnit.piece => 'kpl',
                                QuantityUnit.kg => 'kg',
                                QuantityUnit.litre => 'l',
                                QuantityUnit.unknown => s.unitUnknown,
                              }} € ${formatFixed(snapshot.items[i].rateMicros!, 6)} €',
                            ),
                          if (snapshot.items[i].parentItemId case final parent?)
                            Text(
                              s.parentProduct(
                                snapshot.items.indexWhere(
                                      (r) => r.id == parent,
                                    ) +
                                    1,
                                snapshot.items
                                    .firstWhere((r) => r.id == parent)
                                    .name,
                              ),
                            )
                          else if (snapshot.items[i].discountScope ==
                              DiscountScope.receipt)
                            Text(s.receiptDiscount)
                          else if (snapshot.items[i].kind == LineKind.deposit)
                            Text(s.standaloneDeposit),
                          if (snapshot.items[i].adjustmentReason
                              case final reason?)
                            Text('${s.adjustmentReason}: $reason'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
