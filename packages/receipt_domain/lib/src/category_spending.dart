part of '../receipt_domain.dart';

enum CategorySpendingKind {
  product,
  uncategorized,
  deposit,
  receiptDiscount,
  adjustment,
}

/// Typed special groups cannot collide with user-chosen category labels.
final class ReceiptCategory {
  ReceiptCategory.product(String value)
    : kind = CategorySpendingKind.product,
      name = _categoryLabel(value);
  const ReceiptCategory.uncategorized()
    : kind = CategorySpendingKind.uncategorized,
      name = null;
  const ReceiptCategory.deposit()
    : kind = CategorySpendingKind.deposit,
      name = null;
  const ReceiptCategory.receiptDiscount()
    : kind = CategorySpendingKind.receiptDiscount,
      name = null;
  const ReceiptCategory.adjustment()
    : kind = CategorySpendingKind.adjustment,
      name = null;
  final CategorySpendingKind kind;
  final String? name;
  @override
  bool operator ==(Object other) =>
      other is ReceiptCategory && kind == other.kind && name == other.name;
  @override
  int get hashCode => Object.hash(kind, name);
}

/// Every posted row contributes once. Item discounts follow their parent product;
/// deposits, receipt discounts and adjustments remain explicitly unallocated.
List<({ReceiptItemSnapshot row, ReceiptCategory category})> categorizeReceipt(
  ReceiptSnapshot receipt,
  Map<DurableId, String?> currentProductCategories,
) {
  final products = <DurableId, ReceiptCategory>{};
  for (final row in receipt.items.where((r) => r.kind == LineKind.product)) {
    final label = row.product == null
        ? null
        : currentProductCategories[row.product!.id];
    products[row.id] = label == null
        ? const ReceiptCategory.uncategorized()
        : ReceiptCategory.product(label);
  }
  return List.unmodifiable([
    for (final row in receipt.items)
      (
        row: row,
        category: switch (row.kind) {
          LineKind.product => products[row.id]!,
          LineKind.deposit => const ReceiptCategory.deposit(),
          LineKind.adjustment => const ReceiptCategory.adjustment(),
          LineKind.discount =>
            row.discountScope == DiscountScope.item
                ? products[row.parentItemId]!
                : const ReceiptCategory.receiptDiscount(),
        },
      ),
  ]);
}

final class CategorySpending {
  const CategorySpending(
    this.category,
    this.totalCents,
    this.rowCount,
    this.receiptCount,
  );
  final ReceiptCategory category;
  final BigInt totalCents;
  final int rowCount, receiptCount;
}

final class CategorySpendingSummary {
  CategorySpendingSummary(
    Iterable<CategorySpending> groups,
    this.productRows,
    this.categorizedProductRows,
  ) : groups = List.unmodifiable(groups);
  final List<CategorySpending> groups;
  final int productRows, categorizedProductRows;
  int get uncategorizedProductRows => productRows - categorizedProductRows;
  BigInt get totalCents =>
      groups.fold(BigInt.zero, (sum, g) => sum + g.totalCents);
}

final class CategorySpendingBuilder {
  final _groups = <ReceiptCategory, ({BigInt cents, int rows, int receipts})>{};
  int _products = 0, _categorized = 0;
  void add(ReceiptSnapshot receipt, Map<DurableId, String?> categories) {
    final seen = <ReceiptCategory>{};
    for (final value in categorizeReceipt(receipt, categories)) {
      final key = value.category;
      _require(
        _groups.containsKey(key) || _groups.length < 64,
        'category.summary',
        'categoryGroupLimit',
      );
      final before = _groups[key] ?? (cents: BigInt.zero, rows: 0, receipts: 0);
      _groups[key] = (
        cents: before.cents + value.row.cents,
        rows: before.rows + 1,
        receipts: before.receipts + (seen.add(key) ? 1 : 0),
      );
      if (value.row.kind == LineKind.product) {
        _products++;
        if (key.kind == CategorySpendingKind.product) _categorized++;
      }
    }
  }

  CategorySpendingSummary build() {
    final keys = _groups.keys.toList()
      ..sort((a, b) {
        final cents = _groups[b]!.cents.compareTo(_groups[a]!.cents);
        if (cents != 0) return cents;
        final kind = a.kind.index.compareTo(b.kind.index);
        return kind != 0 ? kind : (a.name ?? '').compareTo(b.name ?? '');
      });
    return CategorySpendingSummary(
      [
        for (final key in keys)
          CategorySpending(
            key,
            _groups[key]!.cents,
            _groups[key]!.rows,
            _groups[key]!.receipts,
          ),
      ],
      _products,
      _categorized,
    );
  }
}
