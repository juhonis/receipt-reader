import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'l10n/generated/app_localizations.dart';
import 'local_store.dart';
import 'catalog_service.dart';
import 'product_picker.dart';
import 'receipt_format.dart';

// Keep aligned with pubspec.yaml when cutting a release.
const receiptAppVersion = '0.1.0+1';

class ManualReceiptPage extends StatefulWidget {
  const ManualReceiptPage({super.key, required this.store}) : _initial = null;
  const ManualReceiptPage._({
    super.key,
    required this.store,
    required this._initial,
  });

  factory ManualReceiptPage.correction({
    Key? key,
    required LocalStore store,
    required StoredReceipt receipt,
  }) {
    if (receipt.document.review is! ManualReviewRecord) {
      throw ArgumentError('manual_correction_requires_manual_source');
    }
    return ManualReceiptPage._(key: key, store: store, initial: receipt);
  }
  final LocalStore store;
  final StoredReceipt? _initial;

  @override
  State<ManualReceiptPage> createState() => _ManualReceiptPageState();
}

class _ManualRow {
  _ManualRow() : id = DurableId.generate();
  _ManualRow.from(ReceiptItemSnapshot item) : id = item.id {
    name.text = item.name;
    amount.text = formatCents(item.cents);
    kind = item.kind;
    rawName = item.rawName;
    product = item.product;
    productName = item.name;
    if (item.quantityValue != null) {
      originalQuantityScale = item.quantityScale!;
      originalQuantityText = formatFixed(
        item.quantityValue!,
        originalQuantityScale,
      );
      quantity.text = originalQuantityText!;
      rate.text = formatFixed(item.rateMicros!, 6);
      unit = item.quantityUnit!;
    }
    reason.text = item.adjustmentReason ?? '';
    if (kind == LineKind.deposit || kind == LineKind.discount) {
      relationship = item.parentItemId?.value ?? 'receipt';
    }
  }
  final DurableId id;
  String? rawName, originalQuantityText;
  int originalQuantityScale = 6;
  ReceiptProductLink? product;
  String? productName;
  final name = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController();
  final rate = TextEditingController();
  final reason = TextEditingController();
  LineKind kind = LineKind.product;
  QuantityUnit unit = QuantityUnit.unknown;
  String? relationship;
  bool reviewed = false;

  void dispose() {
    for (final c in [name, amount, quantity, rate, reason]) {
      c.dispose();
    }
  }
}

class _ManualReceiptPageState extends State<ManualReceiptPage> {
  late final DurableId _receiptId;
  final _newBranchId = DurableId.generate();
  final _name = TextEditingController();
  final _date = TextEditingController();
  final _total = TextEditingController();
  final _rows = <_ManualRow>[];
  List<ReceiptBranch>? _branches;
  String? _branchChoice;
  bool _branchFailed = false;
  bool _branchReviewed = false, _dateReviewed = false, _totalReviewed = false;
  bool _saving = false;
  ReviewedReceipt? _pending;
  bool _saveFailed = false;
  bool _prepareFailed = false, _stale = false;

  bool get _correcting => widget._initial != null;
  List<RevisionId> get _expectedHeads =>
      widget._initial == null ? const [] : [widget._initial!.revision];
  bool get _reviewComplete =>
      _branchReviewed &&
      _dateReviewed &&
      _totalReviewed &&
      !_prepareFailed &&
      _rows.every((row) => row.reviewed);

  @override
  void initState() {
    super.initState();
    final snapshot = widget._initial?.document.snapshot;
    _receiptId = snapshot?.id ?? DurableId.generate();
    if (snapshot == null) {
      _rows.add(_ManualRow());
    } else {
      _branchChoice = snapshot.branch.id.value;
      _date.text = receiptDateText(snapshot.date);
      _total.text = formatCents(snapshot.totalCents);
      _rows.addAll(snapshot.items.map(_ManualRow.from));
    }
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _branchFailed = false);
    try {
      final branches = await widget.store.branches();
      if (mounted) {
        setState(() {
          _branches = branches;
          // An unavailable catalog branch needs an explicit new selection.
          if (_branchChoice != null &&
              _branchChoice != 'new' &&
              !branches.any((b) => b.id.value == _branchChoice)) {
            _branchChoice = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _branchFailed = true);
    }
  }

  void _edit([String? value]) => setState(() {
    _prepareFailed = false;
    _branchReviewed = _dateReviewed = _totalReviewed = false;
    for (final row in _rows) {
      row.reviewed = false;
      if (row.kind != LineKind.product ||
          row.name.text.trim() != row.productName ||
          row.product?.storeId.value != _branchChoice) {
        row.product = null;
      }
    }
  });

  ReceiptSnapshot _snapshot() {
    final branch = _branchChoice == 'new'
        ? ReceiptBranch(id: _newBranchId, name: _name.text.trim())
        : _branches?.where((b) => b.id.value == _branchChoice).firstOrNull;
    if (branch == null) {
      throw const ReceiptDataException('branch', 'unselected');
    }
    BigInt amount(String value, String field, int scale) {
      final parsed = scale == 2 ? parseCents(value) : parseFixed(value, scale);
      if (parsed == null) throw ReceiptDataException(field, 'invalid');
      return parsed;
    }

    return ReceiptSnapshot(
      id: _receiptId,
      branch: branch,
      date: StoredReceiptDate.parse(_date.text),
      totalCents: amount(_total.text, 'totalCents', 2),
      items: [for (final row in _rows) _item(row, amount)],
    );
  }

  ReceiptItemSnapshot _item(
    _ManualRow row,
    BigInt Function(String, String, int) amount,
  ) {
    final related =
        row.kind == LineKind.discount || row.kind == LineKind.deposit;
    if (related && row.relationship == null) {
      throw const ReceiptDataException('row.parent', 'unselected');
    }
    final quantityAbsent =
        row.quantity.text.trim().isEmpty &&
        row.rate.text.trim().isEmpty &&
        row.unit == QuantityUnit.unknown;
    final quantityScale = row.quantity.text == row.originalQuantityText
        ? row.originalQuantityScale
        : 6;
    return ReceiptItemSnapshot(
      id: row.id,
      rawName: row.rawName,
      product: row.product,
      name: row.name.text.trim(),
      kind: row.kind,
      cents: amount(row.amount.text, 'row.cents', 2),
      quantityValue: quantityAbsent
          ? null
          : amount(row.quantity.text, 'row.quantity', quantityScale),
      quantityScale: quantityAbsent ? null : quantityScale,
      quantityUnit: quantityAbsent ? null : row.unit,
      rateMicros: quantityAbsent
          ? null
          : amount(row.rate.text, 'row.quantity', 6),
      parentItemId: related && row.relationship != 'receipt'
          ? DurableId.parse(row.relationship!)
          : null,
      discountScope: row.kind != LineKind.discount
          ? null
          : row.relationship == 'receipt'
          ? DiscountScope.receipt
          : DiscountScope.item,
      adjustmentReason: row.kind == LineKind.adjustment
          ? row.reason.text.trim()
          : null,
    );
  }

  Future<void> _save(ReceiptSnapshot snapshot) async {
    final s = AppLocalizations.of(context)!;
    late final ManualReviewChecks checks;
    try {
      checks = ManualReviewChecks(
        snapshot: snapshot,
        expectedHeads: _expectedHeads,
        mutationId: DurableId.generate(),
        branchReviewed: _branchReviewed,
        dateReviewed: _dateReviewed,
        totalReviewed: _totalReviewed,
        reviewedRowIds: _rows.where((r) => r.reviewed).map((r) => r.id),
      );
    } on ReceiptDataException {
      _edit();
      setState(() => _prepareFailed = true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _correcting ? s.manualCorrectionFinalTitle : s.manualFinalTitle,
        ),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(snapshot.branch.name),
            if (widget.store is CatalogService) ...[
              Text(s.productLinksReview),
              for (final item in snapshot.items.where(
                (r) => r.kind == LineKind.product,
              )) ...[
                Text(item.name),
                if (item.product == null)
                  Text(s.productUnlinked)
                else
                  ProductLinkLabel(
                    service: widget.store as CatalogService,
                    link: item.product!,
                  ),
              ],
            ],
            Text(_date.text),
            Text('${formatCents(snapshot.totalCents)} €'),
            Text(
              _correcting ? s.manualCorrectionFinalNotice : s.manualFinalNotice,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancelAction),
          ),
          FilledButton(
            key: const Key('confirm-save'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_correcting ? s.saveCorrection : s.saveReceipt),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      if (!_reviewComplete) {
        throw const ReceiptDataException('review', 'changedDuringConfirmation');
      }
      final pending = ReviewedReceipt.manual(
        current: _snapshot(),
        expectedHeads: _expectedHeads,
        confirmation: checks.confirm(
          reviewedAtMs: BigInt.from(
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
          appVersion: receiptAppVersion,
        ),
      );
      // Check the final document as well as the snapshot before locking editing.
      ReceiptDocumentCodec.encode(pending.document);
      _pending = pending;
    } on ReceiptDataException {
      _edit();
      setState(() => _prepareFailed = true);
      return;
    }
    await _sendPending();
  }

  Future<void> _sendPending() async {
    if (_saving || _stale) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.store.saveManual(_pending!);
      if (mounted) Navigator.pop(context, true);
    } on StorageFailure catch (error) {
      if (mounted) {
        setState(() {
          _saveFailed = true;
          _stale =
              {
                'staleProduct',
                'missingProduct',
                'crossStoreProduct',
              }.contains(error.code) ||
              error.code == 'staleReceipt' ||
              error.code == 'staleBranch' ||
              error.code == 'receiptDeleted';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _total.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  // A branch dependency revision can become known after creation without
  // changing receipt content. It must not turn a no-op into a correction.
  String _content(ReceiptSnapshot snapshot) => ReceiptSnapshotCodec.encode(
    ReceiptSnapshot(
      id: snapshot.id,
      branch: ReceiptBranch(
        id: snapshot.branch.id,
        name: snapshot.branch.name,
        chain: snapshot.branch.chain,
        address: snapshot.branch.address,
        printedIdentifier: snapshot.branch.printedIdentifier,
      ),
      date: snapshot.date,
      totalCents: snapshot.totalCents,
      items: snapshot.items,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    ReceiptSnapshot? snapshot;
    ReceiptDataException? invalid;
    var changed = true;
    try {
      snapshot = _snapshot();
      changed =
          !_correcting ||
          _content(snapshot) != _content(widget._initial!.document.snapshot);
    } on ReceiptDataException catch (error) {
      snapshot = null;
      invalid = error;
    }
    final ready = snapshot != null && changed && _reviewComplete;
    final locked = _pending != null;
    final kinds = {
      LineKind.product: s.productKind,
      LineKind.discount: s.discountKind,
      LineKind.deposit: s.depositKind,
      LineKind.adjustment: s.adjustmentKind,
    };
    Widget check(
      String key,
      String title,
      bool value,
      ValueChanged<bool?> change,
    ) => CheckboxListTile(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: locked ? null : change,
    );
    Widget field(
      String key,
      TextEditingController controller,
      String label, {
      String? hint,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        enabled: !locked,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: _edit,
      ),
    );
    return PopScope(
      canPop: !_saving && _pending == null,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _correcting ? s.manualCorrectionTitle : s.manualEntryTitle,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _correcting
                          ? s.manualCorrectionNotice
                          : s.manualEntryNotice,
                    ),
                    const SizedBox(height: 16),
                    if (_branches == null && !_branchFailed)
                      const LinearProgressIndicator(),
                    if (_branchFailed) ...[
                      Text(s.branchLoadFailed),
                      TextButton(
                        onPressed: _loadBranches,
                        child: Text(s.retryAction),
                      ),
                    ],
                    if (_branches != null) ...[
                      DropdownButtonFormField<String>(
                        key: const Key('manual-branch'),
                        initialValue: _branchChoice,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: InputDecoration(labelText: s.branchLabel),
                        items: [
                          for (final branch in _branches!)
                            DropdownMenuItem(
                              value: branch.id.value,
                              child: Text(
                                branch.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          DropdownMenuItem(
                            value: 'new',
                            child: Text(s.newBranch),
                          ),
                        ],
                        onChanged: locked
                            ? null
                            : (value) {
                                _branchChoice = value;
                                _edit();
                              },
                      ),
                      if (_branchChoice == 'new') ...[
                        const SizedBox(height: 12),
                        Text(s.newBranchNotice),
                        field('manual-branch-name', _name, s.branchLabel),
                      ],
                      check(
                        'manual-branch-reviewed',
                        s.branchConfirmation,
                        _branchReviewed,
                        (value) =>
                            setState(() => _branchReviewed = value ?? false),
                      ),
                    ],
                    field('manual-date', _date, s.dateLabel, hint: s.dateHint),
                    check(
                      'manual-date-reviewed',
                      s.manualDateReviewed,
                      _dateReviewed,
                      (value) => setState(() => _dateReviewed = value ?? false),
                    ),
                    field('manual-total', _total, s.totalLabel, hint: '0,00'),
                    check(
                      'manual-total-reviewed',
                      s.manualTotalReviewed,
                      _totalReviewed,
                      (value) =>
                          setState(() => _totalReviewed = value ?? false),
                    ),
                    Text(
                      s.rowsHeading,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (var i = 0; i < _rows.length; i++)
                      _rowEditor(i, field, check, kinds, locked),
                    OutlinedButton.icon(
                      key: const Key('manual-add-row'),
                      onPressed: locked
                          ? null
                          : () {
                              _rows.add(_ManualRow());
                              _edit();
                            },
                      icon: const Icon(Icons.add),
                      label: Text(s.addRow),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      snapshot != null
                          ? s.manualValid
                          : switch (invalid?.field) {
                              'branch' || 'branch.name' => s.branchNeedsReview,
                              'date' => s.manualDateInvalid,
                              'json' => s.manualPrepareFailed,
                              'row.parent' ||
                              'row.discount' => s.manualRelationshipInvalid,
                              'row.quantity' ||
                              'row.quantityValue' ||
                              'row.rateMicros' => s.quantityInvalidSummary,
                              'row.adjustmentReason' =>
                                s.adjustmentReasonRequired,
                              'totalCents' => s.manualTotalInvalid,
                              _ => s.manualRowsInvalid,
                            },
                      key: const Key('manual-validation'),
                    ),
                    if (_correcting && !changed)
                      Text(s.manualCorrectionUnchanged),
                    Text(s.manualRecheckNotice),
                    if (_prepareFailed)
                      Text(
                        s.manualPrepareFailed,
                        key: const Key('manual-prepare-error'),
                      ),
                    if (locked) Text(s.pendingSaveNotice),
                    if (_saveFailed)
                      Text(
                        _stale ? s.manualCorrectionStale : s.manualSaveFailed,
                        key: const Key('manual-save-error'),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('manual-save'),
                      onPressed: _saving || _stale
                          ? null
                          : locked
                          ? _sendPending
                          : ready
                          ? () => _save(snapshot!)
                          : null,
                      child: Text(
                        _saving
                            ? s.savingReceipt
                            : locked
                            ? s.retrySave
                            : _correcting
                            ? s.saveCorrection
                            : s.saveReceipt,
                      ),
                    ),
                    if (_saveFailed)
                      TextButton(
                        key: const Key('manual-close-pending'),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(s.closeToHistory),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowEditor(
    int index,
    Widget Function(String, TextEditingController, String, {String? hint})
    field,
    Widget Function(String, String, bool, ValueChanged<bool?>) check,
    Map<LineKind, String> kinds,
    bool locked,
  ) {
    final s = AppLocalizations.of(context)!;
    final row = _rows[index];
    final related =
        row.kind == LineKind.discount || row.kind == LineKind.deposit;
    final products = _rows.where((r) => r != row && r.kind == LineKind.product);
    final options = {'receipt', ...products.map((p) => p.id.value)};
    return Card(
      key: ValueKey(row.id),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.manualRowNumber(index + 1)),
            field('manual-row-name-$index', row.name, s.rowNameLabel),
            if (row.kind == LineKind.product && widget.store is CatalogService)
              ReceiptProductSelector(
                key: ValueKey('manual-product-$index'),
                service: widget.store as CatalogService,
                storeId: _branches
                    ?.where((b) => b.id.value == _branchChoice)
                    .firstOrNull
                    ?.id,
                receiptName: row.name.text,
                link: row.product,
                enabled: !locked,
                onChanged: (link) {
                  row.product = link;
                  row.productName = row.name.text.trim();
                  _edit();
                },
              ),
            field(
              'manual-row-amount-$index',
              row.amount,
              s.rowAmountLabel,
              hint: '0,00',
            ),
            DropdownButtonFormField<LineKind>(
              key: ValueKey('manual-row-kind-$index'),
              initialValue: row.kind,
              isExpanded: true,
              itemHeight: null,
              decoration: InputDecoration(labelText: s.rowKindLabel),
              items: [
                for (final k in kinds.entries)
                  DropdownMenuItem(value: k.key, child: Text(k.value)),
              ],
              onChanged: locked
                  ? null
                  : (value) {
                      if (value == null) return;
                      row.kind = value;
                      row.relationship = null;
                      // A former product can no longer be a parent.
                      for (final other in _rows) {
                        if (other.relationship == row.id.value) {
                          other.relationship = null;
                        }
                      }
                      _edit();
                    },
            ),
            if (related)
              DropdownButtonFormField<String>(
                key: ValueKey('manual-parent-$index-${row.relationship}'),
                initialValue: options.contains(row.relationship)
                    ? row.relationship
                    : null,
                isExpanded: true,
                itemHeight: null,
                decoration: InputDecoration(labelText: s.manualRelationship),
                items: [
                  DropdownMenuItem(
                    value: 'receipt',
                    child: Text(
                      row.kind == LineKind.discount
                          ? s.receiptDiscount
                          : s.standaloneDeposit,
                    ),
                  ),
                  for (final p in products)
                    DropdownMenuItem(
                      value: p.id.value,
                      child: Text(
                        s.parentProduct(_rows.indexOf(p) + 1, p.name.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: locked
                    ? null
                    : (value) {
                        row.relationship = value;
                        _edit();
                      },
              ),
            if (row.kind == LineKind.adjustment)
              field('manual-reason-$index', row.reason, s.adjustmentReason),
            ExpansionTile(
              title: Text(s.quantityDetails),
              children: [
                field('manual-quantity-$index', row.quantity, s.quantityLabel),
                field('manual-rate-$index', row.rate, s.rateLabel),
                DropdownButtonFormField<QuantityUnit>(
                  key: ValueKey('manual-unit-$index'),
                  initialValue: row.unit,
                  decoration: InputDecoration(labelText: s.unitLabel),
                  items: [
                    for (final unit in QuantityUnit.values)
                      DropdownMenuItem(
                        value: unit,
                        child: Text(switch (unit) {
                          QuantityUnit.unknown => s.unitUnknown,
                          QuantityUnit.piece => 'kpl',
                          QuantityUnit.kg => 'kg',
                          QuantityUnit.litre => 'l',
                        }),
                      ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) {
                          row.unit = value!;
                          _edit();
                        },
                ),
              ],
            ),
            check(
              'manual-row-reviewed-$index',
              s.manualRowReviewed,
              row.reviewed,
              (value) => setState(() => row.reviewed = value ?? false),
            ),
            TextButton.icon(
              key: ValueKey('manual-remove-row-$index'),
              onPressed: locked
                  ? null
                  : () {
                      _rows.remove(row);
                      for (final other in _rows) {
                        if (other.relationship == row.id.value) {
                          other.relationship = null;
                        }
                      }
                      _edit();
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => row.dispose(),
                      );
                    },
              icon: const Icon(Icons.delete_outline),
              label: Text(s.removeRow),
            ),
          ],
        ),
      ),
    );
  }
}
