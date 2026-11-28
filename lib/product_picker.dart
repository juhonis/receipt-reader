import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'catalog_service.dart';
import 'catalog_editor.dart';
import 'l10n/generated/app_localizations.dart';
import 'text_search_field.dart';

String productLabel(StoredProduct product) {
  final p = product.document.product;
  final package = p.packageValue == null
      ? ''
      : ' · ${formatFixed(p.packageValue!, p.packageScale!)} ${switch (p.packageUnit!) {
          QuantityUnit.piece => 'kpl',
          QuantityUnit.kg => 'kg',
          QuantityUnit.litre => 'l',
          QuantityUnit.unknown => '',
        }}';
  // Independent equal-name products need a stable visible distinction.
  return '${p.canonicalName}$package · ${p.id.value.substring(0, 8)}';
}

final class ProductChoice {
  const ProductChoice(this.product);
  final StoredProduct? product;
}

Future<ProductChoice?> chooseProduct(
  BuildContext context,
  CatalogService service,
  DurableId storeId, {
  String? receiptName,
}) => showDialog<ProductChoice>(
  context: context,
  builder: (_) => _ProductPicker(
    service: service,
    storeId: storeId,
    receiptName: receiptName,
  ),
);

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({
    required this.service,
    required this.storeId,
    this.receiptName,
  });
  final CatalogService service;
  final DurableId storeId;
  final String? receiptName;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  int _offset = 0;
  String _query = '';
  StoredProduct? _recent;
  bool _editing = false;
  late Future<(List<StoredProduct>, ProductAliasMatch?, ReceiptBranch)> _load =
      _read()..ignore();
  Future<(List<StoredProduct>, ProductAliasMatch?, ReceiptBranch)>
  _read() async {
    final offset = _offset, query = _query;
    final branch = (await widget.service.branches()).firstWhere(
      (b) => b.id == widget.storeId,
    );
    final products = await widget.service.products(
      widget.storeId,
      offset: offset,
      query: query,
    );
    final match = widget.receiptName == null || query.trim().isNotEmpty
        ? null
        : await widget.service.matchAlias(widget.storeId, widget.receiptName!);
    return (products, match, branch);
  }

  Future<void> _edit(ReceiptBranch branch, [StoredProduct? product]) async {
    if (_editing) return;
    setState(() => _editing = true);
    try {
      final result = await showDialog<CatalogEditResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CatalogEditor(
          service: widget.service,
          branch: branch,
          aliasMode: false,
          product: product,
          initialName: widget.receiptName,
        ),
      );
      if (mounted) {
        setState(() {
          _recent = result?.product;
          _load = _read()..ignore();
        });
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    Widget tile(StoredProduct product, String key, ReceiptBranch branch) =>
        ListTile(
          key: ValueKey(key),
          title: Text(productLabel(product)),
          subtitle: Text(
            product.document.product.category ?? s.categoryUncategorized,
          ),
          onTap: _editing
              ? null
              : () => Navigator.pop(context, ProductChoice(product)),
          trailing: IconButton(
            key: ValueKey('edit-product-$key'),
            tooltip: s.productEditCategory,
            onPressed: _editing ? null : () => _edit(branch, product),
            icon: const Icon(Icons.edit_outlined),
          ),
        );
    return AlertDialog(
      title: Text(s.productChoose),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextSearchField(
              fieldKey: 'picker-search',
              value: _query,
              label: s.productSearch,
              hint: s.productSearchHint,
              enabled: !_editing,
              onChanged: (query) => setState(() {
                _query = query;
                _offset = 0;
                _load = _read()..ignore();
              }),
            ),
            FutureBuilder(
              key: ValueKey('$_query:$_offset'),
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(s.catalogLoadFailed),
                      TextButton(
                        onPressed: () => setState(() {
                          _load = _read()..ignore();
                        }),
                        child: Text(s.catalogReload),
                      ),
                    ],
                  );
                }
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final (products, match, branch) = snapshot.data!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.productPickerEditNotice),
                    TextButton.icon(
                      key: const Key('picker-create-product'),
                      onPressed: _editing ? null : () => _edit(branch),
                      icon: const Icon(Icons.add),
                      label: Text(s.catalogAddProduct),
                    ),
                    if (_recent != null && _query.trim().isEmpty) ...[
                      Text(s.productRecentlySaved),
                      tile(_recent!, 'product-recent', branch),
                      const Divider(),
                    ],
                    if (match != null &&
                        match.product.document.product.id !=
                            _recent?.document.product.id) ...[
                      Text(s.productSuggestion),
                      tile(match.product, 'product-suggestion', branch),
                      const Divider(),
                    ],
                    if (products.isEmpty &&
                        (_recent == null || _query.trim().isNotEmpty) &&
                        match == null)
                      Text(
                        _query.trim().isEmpty
                            ? s.catalogEmpty
                            : s.searchNoMatches,
                      ),
                    for (final product in products)
                      if (_query.trim().isNotEmpty ||
                          product.document.product.id !=
                              _recent?.document.product.id)
                        tile(
                          product,
                          'pick-product-${product.document.product.id.value}',
                          branch,
                        ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: _offset == 0
                              ? null
                              : () => setState(() {
                                  _offset -= 30;
                                  _load = _read()..ignore();
                                }),
                          child: Text(s.catalogPrevious),
                        ),
                        TextButton(
                          onPressed: products.length < 30
                              ? null
                              : () => setState(() {
                                  _offset += 30;
                                  _load = _read()..ignore();
                                }),
                          child: Text(s.catalogNext),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('unlink-product'),
          onPressed: () => Navigator.pop(context, const ProductChoice(null)),
          child: Text(s.productUnlink),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancelAction),
        ),
      ],
    );
  }
}

class ProductLinkLabel extends StatefulWidget {
  const ProductLinkLabel({
    super.key,
    required this.service,
    required this.link,
    this.editable = false,
  });
  final CatalogService service;
  final ReceiptProductLink link;
  final bool editable;
  @override
  State<ProductLinkLabel> createState() => _ProductLinkLabelState();
}

class _ProductLinkLabelState extends State<ProductLinkLabel> {
  bool _busy = false;
  String? _error;
  late Future<StoredProduct?> _product = widget.service.readProduct(
    widget.link.id,
  );

  Future<void> _edit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final product = await widget.service.readProduct(widget.link.id);
      final branch = (await widget.service.branches()).firstWhere(
        (b) => b.id == widget.link.storeId,
      );
      if (product == null || product.document.product.storeId != branch.id) {
        throw StateError('missingProduct');
      }
      if (!mounted) return;
      await showDialog<CatalogEditResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CatalogEditor(
          service: widget.service,
          branch: branch,
          aliasMode: false,
          product: product,
        ),
      );
    } catch (_) {
      if (mounted) _error = AppLocalizations.of(context)!.catalogLoadFailed;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _product = widget.service.readProduct(widget.link.id)..ignore();
        });
      }
    }
  }

  @override
  void didUpdateWidget(ProductLinkLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link || oldWidget.service != widget.service) {
      _product = widget.service.readProduct(widget.link.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return FutureBuilder(
      future: _product,
      builder: (context, result) {
        final product = result.data;
        if (product == null) return Text(s.productUnavailable);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.productSelected}: ${productLabel(product)}'),
            Text(
              '${s.productCategory}: ${product.document.product.category ?? s.categoryUncategorized}',
            ),
            if (product.revision != widget.link.revision)
              Text(s.productCurrentLabel),
            if (widget.editable)
              TextButton.icon(
                key: ValueKey('receipt-edit-product-${widget.link.id.value}'),
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(s.productEditCategory),
              ),
            if (_error != null) Text(_error!),
          ],
        );
      },
    );
  }
}

class ReceiptProductSelector extends StatelessWidget {
  const ReceiptProductSelector({
    super.key,
    required this.service,
    required this.storeId,
    required this.receiptName,
    required this.link,
    required this.onChanged,
    this.enabled = true,
  });
  final CatalogService service;
  final DurableId? storeId;
  final String receiptName;
  final ReceiptProductLink? link;
  final ValueChanged<ReceiptProductLink?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (link == null)
          Text(s.productUnlinked)
        else
          ProductLinkLabel(service: service, link: link!),
        if (storeId == null) Text(s.productBranchFirst),
        TextButton.icon(
          onPressed: !enabled || storeId == null
              ? null
              : () async {
                  final choice = await chooseProduct(
                    context,
                    service,
                    storeId!,
                    receiptName: receiptName,
                  );
                  if (context.mounted && choice != null) {
                    final current = context.widget as ReceiptProductSelector;
                    if (current.enabled &&
                        current.storeId == storeId &&
                        current.receiptName == receiptName) {
                      current.onChanged(choice.product?.link);
                    }
                  }
                },
          icon: const Icon(Icons.link),
          label: Text(s.productChoose),
        ),
      ],
    );
  }
}
