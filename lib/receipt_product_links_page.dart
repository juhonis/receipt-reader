import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart' show LineKind, formatCents;
import 'package:receipt_storage/receipt_storage.dart';

import 'app_version.dart';
import 'catalog_service.dart';
import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'product_picker.dart';
import 'receipt_format.dart';

/// A receipt-scoped draft; final approval covers only explicit link changes.
class ReceiptProductLinksPage extends StatefulWidget {
  const ReceiptProductLinksPage({
    super.key,
    required this.store,
    required this.catalog,
    required this.receipt,
  });
  final LocalStore store;
  final CatalogService catalog;
  final StoredReceipt receipt;
  @override
  State<ReceiptProductLinksPage> createState() =>
      _ReceiptProductLinksPageState();
}

class _ReceiptProductLinksPageState extends State<ReceiptProductLinksPage> {
  final _selections = <DurableId, ReceiptProductLink?>{};
  ReviewedReceipt? _pending;
  bool _saving = false, _failed = false, _stale = false;

  bool _changed(ReceiptItemSnapshot row) {
    if (!_selections.containsKey(row.id)) return false;
    final before = row.product, after = _selections[row.id];
    return before?.id != after?.id ||
        before?.revision != after?.revision ||
        before?.storeId != after?.storeId;
  }

  Future<void> _save() async {
    if (_saving) return;
    _pending ??= ReviewedReceipt.productLinks(
      confirmation:
          ProductLinkReviewChecks(
            base: widget.receipt.document,
            expectedHead: widget.receipt.revision,
            selections: _selections,
            mutationId: DurableId.generate(),
          ).confirm(
            reviewedAtMs: BigInt.from(
              DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
            appVersion: receiptAppVersion,
          ),
    );
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      if (_pending!.document.review.source == 'ocr') {
        await widget.store.saveOcr(_pending!);
      } else {
        await widget.store.saveManual(_pending!);
      }
      if (mounted) Navigator.pop(context, true);
    } on StorageFailure catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _stale = const [
            'staleReceipt',
            'receiptDeleted',
            'staleProduct',
            'staleBranch',
            'crossStoreProduct',
            'missingProduct',
          ].contains(error.code);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final snapshot = widget.receipt.document.snapshot;
    final locked = _pending != null;
    return PopScope(
      canPop: !locked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.productLinksTitle),
          automaticallyImplyLeading: !locked,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(snapshot.branch.name),
                  Text(receiptDateText(snapshot.date)),
                  Text('${formatCents(snapshot.totalCents)} €'),
                  Text(s.productLinksNotice),
                  for (var i = 0; i < snapshot.items.length; i++)
                    if (snapshot.items[i].kind == LineKind.product)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.manualRowNumber(i + 1)),
                              Text(snapshot.items[i].name),
                              Text('${formatCents(snapshot.items[i].cents)} €'),
                              if (_changed(snapshot.items[i]))
                                Text(s.productLinksChanged),
                              ReceiptProductSelector(
                                key: ValueKey('saved-product-$i'),
                                service: widget.catalog,
                                storeId: snapshot.branch.id,
                                receiptName: snapshot.items[i].name,
                                enabled: !locked,
                                link:
                                    _selections.containsKey(
                                      snapshot.items[i].id,
                                    )
                                    ? _selections[snapshot.items[i].id]
                                    : snapshot.items[i].product,
                                onChanged: (link) {
                                  if (!locked) {
                                    setState(
                                      () => _selections[snapshot.items[i].id] =
                                          link,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_failed)
                    Text(_stale ? s.productLinksStale : s.productLinksFailed),
                  if (locked && !_stale) Text(s.productLinksPending),
                  if (!_stale)
                    FilledButton(
                      key: const Key('save-product-links'),
                      onPressed:
                          !_saving && (locked || snapshot.items.any(_changed))
                          ? _save
                          : null,
                      child: Text(_failed ? s.retrySave : s.productLinksSave),
                    ),
                  if (!locked)
                    TextButton(
                      key: const Key('cancel-product-links'),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.cancelAction),
                    ),
                  if (_failed)
                    TextButton(
                      key: const Key('close-product-links'),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(s.closeToHistory),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
