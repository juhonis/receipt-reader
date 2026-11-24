part of '../receipt_domain.dart';

/// Net posted product amounts; no quantities or cross-product price inference.
final class ProductSpending {
  const ProductSpending({
    required this.productId,
    required this.branch,
    required this.name,
    required this.totalCents,
    required this.rowCount,
    required this.receiptCount,
    required this.returnRows,
    required this.returnCents,
  });
  final DurableId productId;
  final ReceiptBranch branch;
  final String name;
  final BigInt totalCents, returnCents;
  final int rowCount, receiptCount, returnRows;
}

final class ProductSpendingSummary {
  ProductSpendingSummary({
    required Iterable<ProductSpending> groups,
    required this.limitExceeded,
    required this.productRows,
    required this.linkedRows,
    required this.linkedCents,
    required this.unlinkedCents,
    required this.depositCents,
    required this.receiptDiscountCents,
    required this.adjustmentCents,
  }) : groups = List.unmodifiable(groups);
  final List<ProductSpending> groups;
  final bool limitExceeded;
  final int productRows, linkedRows;
  final BigInt linkedCents,
      unlinkedCents,
      depositCents,
      receiptDiscountCents,
      adjustmentCents;
  BigInt get receiptTotalCents =>
      linkedCents +
      unlinkedCents +
      depositCents +
      receiptDiscountCents +
      adjustmentCents;
}

/// Bounded exact grouping. On overflow only the ranking is withheld; coverage and
/// financial totals keep consuming all rows so the dashboard stays complete.
final class ProductSpendingBuilder {
  static const maxGroups = 2048;
  final _groups = <(DurableId, DurableId), _ProductSpendingFold>{};
  bool _limited = false;
  int _products = 0, _linked = 0;
  BigInt _linkedCents = BigInt.zero,
      _unlinkedCents = BigInt.zero,
      _deposits = BigInt.zero,
      _receiptDiscounts = BigInt.zero,
      _adjustments = BigInt.zero;

  void add(ReceiptSnapshot receipt, Map<DurableId, ProductSnapshot> products) {
    final nets = {
      for (final row in receipt.items)
        if (row.kind == LineKind.product) row.id: row.cents,
    };
    for (final row in receipt.items) {
      switch (row.kind) {
        case LineKind.product:
          break;
        case LineKind.discount:
          if (row.discountScope == DiscountScope.item) {
            nets[row.parentItemId!] = nets[row.parentItemId!]! + row.cents;
          } else {
            _receiptDiscounts += row.cents;
          }
        case LineKind.deposit:
          _deposits += row.cents;
        case LineKind.adjustment:
          _adjustments += row.cents;
      }
    }
    final seen = <(DurableId, DurableId)>{};
    for (final row in receipt.items.where((r) => r.kind == LineKind.product)) {
      _products++;
      final net = nets[row.id]!;
      final link = row.product;
      if (link == null) {
        _unlinkedCents += net;
        continue;
      }
      _linked++;
      _linkedCents += net;
      if (_limited) continue;
      final metadata = products[link.id];
      _require(
        metadata == null ||
            (metadata.id == link.id && metadata.storeId == receipt.branch.id),
        'product.spending',
        'crossStoreProduct',
      );
      final key = (receipt.branch.id, link.id);
      if (!_groups.containsKey(key) && _groups.length == maxGroups) {
        _limited = true;
        _groups.clear();
        continue;
      }
      final group = _groups.putIfAbsent(
        key,
        () => _ProductSpendingFold(link.id),
      );
      group.add(
        receipt,
        row,
        net,
        metadata?.canonicalName ?? row.name,
        seen.add(key),
      );
    }
  }

  ProductSpendingSummary build() {
    final groups = _groups.values.map((g) => g.build()).toList()
      ..sort((a, b) {
        final amount = b.totalCents.compareTo(a.totalCents);
        if (amount != 0) return amount;
        final name = a.name.compareTo(b.name);
        if (name != 0) return name;
        final branch = a.branch.id.compareTo(b.branch.id);
        return branch != 0 ? branch : a.productId.compareTo(b.productId);
      });
    return ProductSpendingSummary(
      groups: groups,
      limitExceeded: _limited,
      productRows: _products,
      linkedRows: _linked,
      linkedCents: _linkedCents,
      unlinkedCents: _unlinkedCents,
      depositCents: _deposits,
      receiptDiscountCents: _receiptDiscounts,
      adjustmentCents: _adjustments,
    );
  }
}

final class _ProductSpendingFold {
  _ProductSpendingFold(this.productId);
  final DurableId productId;
  BigInt cents = BigInt.zero, returnsCents = BigInt.zero;
  int rows = 0, receipts = 0, returns = 0;
  ReceiptBranch? _branch;
  int? _labelDay;
  DurableId? _labelReceiptId;
  late String name;
  void add(
    ReceiptSnapshot receipt,
    ReceiptItemSnapshot row,
    BigInt net,
    String label,
    bool firstInReceipt,
  ) {
    // Keep only display metadata, never a retained receipt/row collection.
    final day = purchaseCalendarDay(receipt.date);
    if (_labelDay == null ||
        day > _labelDay! ||
        (day == _labelDay && receipt.id.compareTo(_labelReceiptId!) < 0) ||
        (receipt.id == _labelReceiptId && label.compareTo(name) < 0)) {
      _branch = receipt.branch;
      _labelDay = day;
      _labelReceiptId = receipt.id;
      name = label;
    }
    rows++;
    if (firstInReceipt) receipts++;
    cents += net;
    if (row.cents.isNegative || (row.quantityValue?.isNegative ?? false)) {
      returns++;
      returnsCents += net;
    }
  }

  ProductSpending build() => ProductSpending(
    productId: productId,
    branch: _branch!,
    name: name,
    totalCents: cents,
    rowCount: rows,
    receiptCount: receipts,
    returnRows: returns,
    returnCents: returnsCents,
  );
}
