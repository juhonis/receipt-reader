import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';

String receiptDateText(StoredReceiptDate date) {
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${date.day}.${date.month}.${date.year}';
  return date.hour == null
      ? day
      : '$day ${two(date.hour!)}:${two(date.minute!)}'
            '${date.second == null ? '' : ':${two(date.second!)}'}';
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});
  final LocalStore store;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _pageSize = 30;
  final _receipts = <StoredReceipt>[];
  bool _loading = false, _failed = false, _more = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
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
      );
      if (mounted) {
        setState(() {
          _receipts.addAll(page);
          _more = page.length == _pageSize;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
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
                if (!_loading && !_failed && _receipts.isEmpty)
                  Text(s.historyEmpty),
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
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ReceiptDetailPage(receipt: receipt),
                      ),
                    ),
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
  const ReceiptDetailPage({super.key, required this.receipt});
  final StoredReceipt receipt;

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
                for (var i = 0; i < snapshot.items.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.manualRowNumber(i + 1)),
                          Text(snapshot.items[i].name),
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
