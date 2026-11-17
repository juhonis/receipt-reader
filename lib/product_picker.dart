import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'catalog_service.dart';
import 'l10n/generated/app_localizations.dart';

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
  late Future<(List<StoredProduct>, ProductAliasMatch?)> _load = _read();
  Future<(List<StoredProduct>, ProductAliasMatch?)> _read() async {
    final products = await widget.service.products(
      widget.storeId,
      offset: _offset,
    );
    final match = widget.receiptName == null
        ? null
        : await widget.service.matchAlias(widget.storeId, widget.receiptName!);
    return (products, match);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    Widget tile(StoredProduct product, String key) => ListTile(
      key: ValueKey(key),
      title: Text(productLabel(product)),
      onTap: () => Navigator.pop(context, ProductChoice(product)),
    );
    return AlertDialog(
      title: Text(s.productChoose),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: FutureBuilder(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  Text(s.catalogLoadFailed),
                  TextButton(
                    onPressed: () => setState(() => _load = _read()),
                    child: Text(s.catalogReload),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (products, match) = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (match != null) ...[
                  Text(s.productSuggestion),
                  tile(match.product, 'product-suggestion'),
                  const Divider(),
                ],
                if (products.isEmpty) Text(s.catalogEmpty),
                for (final product in products)
                  tile(
                    product,
                    'pick-product-${product.document.product.id.value}',
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _offset == 0
                          ? null
                          : () => setState(() {
                              _offset -= 30;
                              _load = _read();
                            }),
                      child: Text(s.catalogPrevious),
                    ),
                    TextButton(
                      onPressed: products.length < 30
                          ? null
                          : () => setState(() {
                              _offset += 30;
                              _load = _read();
                            }),
                      child: Text(s.catalogNext),
                    ),
                  ],
                ),
              ],
            );
          },
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
  });
  final CatalogService service;
  final ReceiptProductLink link;
  @override
  State<ProductLinkLabel> createState() => _ProductLinkLabelState();
}

class _ProductLinkLabelState extends State<ProductLinkLabel> {
  late Future<StoredProduct?> _product = widget.service.readProduct(
    widget.link.id,
  );
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
            if (product.revision != widget.link.revision)
              Text(s.productCurrentLabel),
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
                    onChanged(choice.product?.link);
                  }
                },
          icon: const Icon(Icons.link),
          label: Text(s.productChoose),
        ),
      ],
    );
  }
}
