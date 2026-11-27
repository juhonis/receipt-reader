import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';

import 'catalog_service.dart';
import 'l10n/generated/app_localizations.dart';
import 'product_picker.dart';
import 'product_suggestions.dart';

class ProductSuggestionChoice {
  const ProductSuggestionChoice.name(String this.name) : link = null;
  const ProductSuggestionChoice.link(ReceiptProductLink this.link)
    : name = null;
  final String? name;
  final ReceiptProductLink? link;
}

class ProductSuggestionDialog extends StatefulWidget {
  const ProductSuggestionDialog({
    super.key,
    required this.service,
    required this.branchId,
    required this.receiptName,
  });
  final CatalogService service;
  final DurableId branchId;
  final String receiptName;
  @override
  State<ProductSuggestionDialog> createState() =>
      _ProductSuggestionDialogState();
}

class _ProductSuggestionDialogState extends State<ProductSuggestionDialog> {
  late Future<ProductSuggestions> _load = _read();
  bool _busy = false, _changed = false, _failed = false;
  Future<ProductSuggestions> _read() => loadProductSuggestions(
    widget.service,
    widget.branchId,
    widget.receiptName,
  )..ignore();

  Future<void> _choose(
    ProductNameSuggestion suggestion, {
    required bool nameOnly,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _changed = false;
    });
    try {
      final original = suggestion.product;
      final current = await widget.service.readProduct(
        original.document.product.id,
      );
      if (!mounted) return;
      if (current == null ||
          current.revision != original.revision ||
          current.document.product.storeId != widget.branchId) {
        setState(() {
          _changed = true;
          _load = _read();
        });
        return;
      }
      Navigator.pop(
        context,
        nameOnly
            ? ProductSuggestionChoice.name(
                current.document.product.canonicalName,
              )
            : ProductSuggestionChoice.link(current.link),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.productSuggestionsTitle),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.receiptName),
            Text(s.productSuggestionsHelp),
            if (_changed) Text(s.productSuggestionsChanged),
            if (_failed) Text(s.catalogLoadFailed),
            FutureBuilder(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(s.catalogLoadFailed),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _load = _read();
                              }),
                        child: Text(s.catalogReload),
                      ),
                    ],
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final result = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.items.isEmpty) Text(s.productSuggestionsEmpty),
                    for (final suggestion in result.items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(productLabel(suggestion.product)),
                              Text(switch (suggestion.reason) {
                                ProductSuggestionReason.alias =>
                                  s.productSuggestionAlias,
                                ProductSuggestionReason.exactName =>
                                  s.productSuggestionExact,
                                ProductSuggestionReason.similarName =>
                                  s.productSuggestionSpelling,
                              }),
                              Text(
                                suggestion.product.document.product.category ??
                                    s.categoryUncategorized,
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    key: ValueKey(
                                      'suggest-name-${suggestion.product.document.product.id.value}',
                                    ),
                                    onPressed:
                                        _busy ||
                                            suggestion
                                                    .product
                                                    .document
                                                    .product
                                                    .canonicalName ==
                                                widget.receiptName
                                        ? null
                                        : () => _choose(
                                            suggestion,
                                            nameOnly: true,
                                          ),
                                    child: Text(s.productSuggestionUseName),
                                  ),
                                  TextButton(
                                    key: ValueKey(
                                      'suggest-link-${suggestion.product.document.product.id.value}',
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _choose(
                                            suggestion,
                                            nameOnly: false,
                                          ),
                                    child: Text(s.productSuggestionLink),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (result.limited) Text(s.productSuggestionsMore),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.cancelAction),
        ),
      ],
    );
  }
}
