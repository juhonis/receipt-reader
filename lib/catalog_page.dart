import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'catalog_service.dart';
import 'local_store.dart';
import 'purchase_history_service.dart';
import 'purchase_history_page.dart';
import 'catalog_editor.dart';
import 'product_picker.dart';
import 'l10n/generated/app_localizations.dart';
import 'text_search_field.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.store, required this.catalog});
  final LocalStore store;
  final CatalogService catalog;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late Future<List<ReceiptBranch>> _branches = widget.store.branches();
  ReceiptBranch? _branch;
  bool _aliases = false;
  int _offset = 0;
  String _query = '';
  Future<List<Object>>? _items;
  void _load() {
    final branch = _branch;
    _items = branch == null
        ? null
        : _aliases
        ? widget.catalog.aliases(branch.id, offset: _offset, query: _query)
        : widget.catalog.products(branch.id, offset: _offset, query: _query);
  }

  Future<void> _open({
    StoredProduct? product,
    StoredProductAlias? alias,
  }) async {
    final branch = _branch;
    if (branch == null) return;
    await showDialog<CatalogEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogEditor(
        service: widget.catalog,
        branch: branch,
        aliasMode: _aliases,
        product: product,
        alias: alias,
      ),
    );
    if (mounted) setState(_load); // A failed response can still have committed.
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.catalogTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.catalogNotice),
              const SizedBox(height: 16),
              FutureBuilder(
                future: _branches,
                builder: (context, result) {
                  if (result.hasError) {
                    return TextButton(
                      onPressed: () =>
                          setState(() => _branches = widget.store.branches()),
                      child: Text(s.catalogLoadFailed),
                    );
                  }
                  if (!result.hasData) return const LinearProgressIndicator();
                  final branches = result.data!;
                  if (branches.isEmpty) return Text(s.catalogNoBranch);
                  return DropdownButtonFormField<String>(
                    key: const Key('catalog-branch'),
                    initialValue: _branch?.id.value,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s.branchLabel),
                    items: [
                      for (final b in branches)
                        DropdownMenuItem(
                          value: b.id.value,
                          child: Text(b.name),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      _branch = branches.firstWhere((b) => b.id.value == id);
                      _offset = 0;
                      _load();
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  ChoiceChip(
                    label: Text(s.catalogProducts),
                    selected: !_aliases,
                    onSelected: (_) => setState(() {
                      _aliases = false;
                      _offset = 0;
                      _load();
                    }),
                  ),
                  ChoiceChip(
                    label: Text(s.catalogAliases),
                    selected: _aliases,
                    onSelected: (_) => setState(() {
                      _aliases = true;
                      _offset = 0;
                      _load();
                    }),
                  ),
                ],
              ),
              FilledButton(
                key: const Key('catalog-add'),
                onPressed: _branch == null ? null : () => _open(),
                child: Text(_aliases ? s.catalogAddAlias : s.catalogAddProduct),
              ),
              TextSearchField(
                fieldKey: 'catalog-search',
                value: _query,
                label: s.productSearch,
                hint: _aliases ? s.aliasSearchHint : s.productSearchHint,
                enabled: _branch != null,
                onChanged: (query) => setState(() {
                  _query = query;
                  _offset = 0;
                  _load();
                }),
              ),
              if (_items != null)
                FutureBuilder(
                  key: ValueKey(
                    '${_branch?.id.value}:$_aliases:$_offset:$_query',
                  ),
                  future: _items,
                  builder: (context, result) {
                    if (result.hasError) {
                      return TextButton(
                        onPressed: () => setState(_load),
                        child: Text(s.catalogLoadFailed),
                      );
                    }
                    if (!result.hasData) return const LinearProgressIndicator();
                    final items = result.data!;
                    return Column(
                      children: [
                        if (items.isEmpty)
                          Text(
                            _query.trim().isEmpty
                                ? s.catalogEmpty
                                : s.searchNoMatches,
                          ),
                        for (final item in items)
                          if (item is StoredProduct)
                            ListTile(
                              key: ValueKey(
                                'catalog-product-${item.document.product.id.value}',
                              ),
                              title: Text(productLabel(item)),
                              subtitle: Text(
                                item.document.product.category ??
                                    s.categoryUncategorized,
                              ),
                              trailing: widget.store is PurchaseHistoryService
                                  ? IconButton(
                                      key: ValueKey(
                                        'product-history-${item.document.product.id.value}',
                                      ),
                                      tooltip: s.purchaseHistory,
                                      icon: const Icon(Icons.show_chart),
                                      onPressed: () => Navigator.push<void>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PurchaseHistoryPage(
                                            store: widget.store,
                                            service:
                                                widget.store
                                                    as PurchaseHistoryService,
                                            product: item,
                                            branchName: _branch!.name,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                              onTap: () => _open(product: item),
                            )
                          else if (item is StoredProductAlias)
                            ListTile(
                              key: ValueKey(
                                'catalog-alias-${item.document.alias.id.value}',
                              ),
                              title: Text(item.document.alias.normalizedName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.document.alias.isActive
                                        ? s.catalogActive
                                        : s.catalogInactive,
                                  ),
                                  ProductLinkLabel(
                                    service: widget.catalog,
                                    link: ReceiptProductLink(
                                      id: item.document.alias.productId,
                                      storeId: item.document.alias.storeId,
                                      revision: item.document.productRevision,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _open(alias: item),
                            ),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: _offset == 0
                                  ? null
                                  : () => setState(() {
                                      _offset -= 30;
                                      _load();
                                    }),
                              child: Text(s.catalogPrevious),
                            ),
                            TextButton(
                              onPressed: items.length < 30
                                  ? null
                                  : () => setState(() {
                                      _offset += 30;
                                      _load();
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
      ),
    );
  }
}
