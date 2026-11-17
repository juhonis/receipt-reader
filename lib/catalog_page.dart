import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'catalog_service.dart';
import 'local_store.dart';
import 'manual_receipt_page.dart' show receiptAppVersion;
import 'product_picker.dart';
import 'l10n/generated/app_localizations.dart';

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
  Future<List<Object>>? _items;
  void _load() {
    final branch = _branch;
    _items = branch == null
        ? null
        : _aliases
        ? widget.catalog.aliases(branch.id, offset: _offset)
        : widget.catalog.products(branch.id, offset: _offset);
  }

  Future<void> _open({
    StoredProduct? product,
    StoredProductAlias? alias,
  }) async {
    final branch = _branch;
    if (branch == null) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CatalogEditor(
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
              if (_items != null)
                FutureBuilder(
                  key: ValueKey('${_branch?.id.value}:$_aliases:$_offset'),
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
                        if (items.isEmpty) Text(s.catalogEmpty),
                        for (final item in items)
                          if (item is StoredProduct)
                            ListTile(
                              key: ValueKey(
                                'catalog-product-${item.document.product.id.value}',
                              ),
                              title: Text(productLabel(item)),
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

class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({
    required this.service,
    required this.branch,
    required this.aliasMode,
    this.product,
    this.alias,
  });
  final CatalogService service;
  final ReceiptBranch branch;
  final bool aliasMode;
  final StoredProduct? product;
  final StoredProductAlias? alias;
  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final _name = TextEditingController(), _package = TextEditingController();
  final _id = DurableId.generate(), _mutation = DurableId.generate();
  QuantityUnit? _unit;
  ReceiptProductLink? _target;
  bool _active = true, _reviewed = false, _busy = false, _stale = false;
  bool _targetEdited = false;
  String? _error;
  ProductDocument? _productCommand;
  ProductAliasDocument? _aliasCommand;
  bool get _frozen => _productCommand != null || _aliasCommand != null;
  @override
  void initState() {
    super.initState();
    final p = widget.product?.document.product, a = widget.alias?.document;
    _name.text = p?.canonicalName ?? a?.alias.normalizedName ?? '';
    if (p?.packageValue != null) {
      _package.text = formatFixed(p!.packageValue!, p.packageScale!);
      _unit = p.packageUnit;
    }
    if (a != null) {
      _active = a.alias.isActive;
      _target = ReceiptProductLink(
        id: a.alias.productId,
        storeId: a.alias.storeId,
        revision: a.productRevision,
      );
      _refreshTarget(a.alias.productId);
    }
  }

  Future<void> _refreshTarget(DurableId id) async {
    try {
      final p = await widget.service.readProduct(id);
      if (mounted && !_frozen && !_targetEdited) {
        setState(() {
          _target = p?.link;
          _reviewed = false;
        });
      }
    } catch (_) {
      if (mounted && !_frozen && !_targetEdited) {
        setState(() {
          _target = null;
          _error = AppLocalizations.of(context)!.catalogLoadFailed;
        });
      }
    }
  }

  void _edit([String? _]) => setState(() {
    _reviewed = false;
    _error = null;
  });
  Future<void> _save() async {
    if (_busy || _stale || !_reviewed) return;
    final s = AppLocalizations.of(context)!;
    try {
      final revision = widget.branch.revision;
      if (revision == null) throw StateError('missingBranchRevision');
      final now = BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch);
      if (!_frozen) {
        if (widget.aliasMode) {
          if (_target == null) throw const FormatException();
          _aliasCommand = ProductAliasDocument(
            alias: ProductAliasSnapshot(
              id: widget.alias?.document.alias.id ?? _id,
              storeId: widget.branch.id,
              normalizedName: normalizeReceiptNameV1(_name.text),
              productId: _target!.id,
              isActive: _active,
            ),
            storeRevision: revision,
            productRevision: _target!.revision,
            expectedHead: widget.alias?.revision,
            reviewedAtMs: now,
            appVersion: receiptAppVersion,
          );
        } else {
          final empty = _package.text.trim().isEmpty && _unit == null;
          final original = widget.product?.document.product;
          final scale =
              original?.packageValue != null &&
                  _package.text ==
                      formatFixed(
                        original!.packageValue!,
                        original.packageScale!,
                      )
              ? original.packageScale!
              : 6;
          final quantity = empty ? null : parseFixed(_package.text, scale);
          if (!empty && (quantity == null || _unit == null)) {
            throw const FormatException();
          }
          _productCommand = ProductDocument(
            product: ProductSnapshot(
              id: original?.id ?? _id,
              storeId: widget.branch.id,
              canonicalName: _name.text.trim(),
              packageValue: quantity,
              packageScale: empty ? null : scale,
              packageUnit: _unit,
            ),
            storeRevision: revision,
            expectedHead: widget.product?.revision,
            reviewedAtMs: now,
            appVersion: receiptAppVersion,
          );
        }
      }
    } catch (_) {
      setState(() => _error = s.catalogInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_productCommand != null) {
        await widget.service.saveProduct(
          _productCommand!,
          mutationId: _mutation,
        );
      } else {
        await widget.service.saveAlias(_aliasCommand!, mutationId: _mutation);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stale =
              e is StorageFailure &&
              {
                'staleCatalog',
                'staleProduct',
                'staleAlias',
                'staleBranch',
                'aliasCollision',
                'crossStoreProduct',
                'missingProduct',
                'missingBranch',
                'mutationIdentityReused',
              }.contains(e.code);
          _error = _stale ? s.catalogStale : s.catalogSaveFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _package.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final locked = _busy || _frozen;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          widget.aliasMode
              ? (widget.alias == null ? s.catalogAddAlias : s.catalogEditAlias)
              : (widget.product == null
                    ? s.catalogAddProduct
                    : s.catalogEditProduct),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.branch.name),
              TextField(
                key: const Key('catalog-name'),
                controller: _name,
                enabled: !locked && (!widget.aliasMode || widget.alias == null),
                decoration: InputDecoration(
                  labelText: widget.aliasMode
                      ? s.catalogAliasName
                      : s.catalogName,
                ),
                onChanged: _edit,
              ),
              if (widget.aliasMode) ...[
                Text(s.catalogAliasNotice),
                ReceiptProductSelector(
                  service: widget.service,
                  storeId: widget.branch.id,
                  receiptName: _name.text,
                  link: _target,
                  enabled: !locked,
                  onChanged: (link) {
                    _targetEdited = true;
                    _target = link;
                    _edit();
                  },
                ),
                CheckboxListTile(
                  key: const Key('catalog-active'),
                  title: Text(s.catalogActive),
                  value: _active,
                  onChanged: locked
                      ? null
                      : (v) {
                          _active = v ?? false;
                          _edit();
                        },
                ),
              ] else ...[
                TextField(
                  key: const Key('catalog-package'),
                  controller: _package,
                  enabled: !locked,
                  decoration: InputDecoration(labelText: s.catalogPackage),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _edit,
                ),
                DropdownButtonFormField<QuantityUnit>(
                  key: const Key('catalog-unit'),
                  isExpanded: true,
                  itemHeight: null,
                  initialValue: _unit,
                  decoration: InputDecoration(labelText: s.catalogUnit),
                  items: [
                    DropdownMenuItem(value: null, child: Text(s.catalogNoUnit)),
                    const DropdownMenuItem(
                      value: QuantityUnit.piece,
                      child: Text('kpl'),
                    ),
                    const DropdownMenuItem(
                      value: QuantityUnit.kg,
                      child: Text('kg'),
                    ),
                    const DropdownMenuItem(
                      value: QuantityUnit.litre,
                      child: Text('l'),
                    ),
                  ],
                  onChanged: locked
                      ? null
                      : (v) {
                          _unit = v;
                          _edit();
                        },
                ),
              ],
              CheckboxListTile(
                key: const Key('catalog-reviewed'),
                title: Text(s.catalogReviewed),
                value: _reviewed,
                onChanged: locked
                    ? null
                    : (v) => setState(() => _reviewed = v ?? false),
              ),
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.catalogClose),
          ),
          FilledButton(
            key: const Key('catalog-save'),
            onPressed: !_reviewed || _busy || _stale ? null : _save,
            child: Text(_frozen ? s.catalogRetry : s.catalogSave),
          ),
        ],
      ),
    );
  }
}
