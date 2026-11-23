part of '../receipt_domain.dart';

/// Signed totals of complete, current reviewed receipts, never product prices.
final class SpendingTotals {
  const SpendingTotals(
    this.receiptCount,
    this.totalCents,
    this.negativeReceipts,
    this.adjustedReceipts,
    this.unlinkedReceipts,
  );
  final int receiptCount, negativeReceipts, adjustedReceipts, unlinkedReceipts;
  final BigInt totalCents;
}

final class BranchSpending {
  const BranchSpending(this.branch, this.totals);

  /// Label from the newest selected receipt (date, then durable receipt ID).
  final ReceiptBranch branch;
  final SpendingTotals totals;
}

final class MonthlySpending {
  const MonthlySpending(this.year, this.month, this.totals);
  final int year, month;
  final SpendingTotals totals;
}

final class SpendingSummary {
  SpendingSummary(
    this.totals,
    Iterable<BranchSpending> branches,
    Iterable<MonthlySpending> months,
  ) : branches = List.unmodifiable(branches),
      months = List.unmodifiable(months);
  final SpendingTotals totals;
  final List<BranchSpending> branches;

  /// Nonempty printed calendar months, newest first. Missing months are absent.
  final List<MonthlySpending> months;
}

/// Streaming exact fold; at most 128 branches and 1560 months (1970–2099).
/// Exceeding a bound fails the entire result, never returning partial totals.
final class SpendingSummaryBuilder {
  final _total = _SpendingFold();
  final _branches = _BranchSpendingBuilder();
  final _months = <int, _SpendingFold>{};

  void add(ReceiptSnapshot receipt) {
    final month = receipt.date.year * 100 + receipt.date.month;
    _require(
      _months.containsKey(month) || _months.length < 1560,
      'spending',
      'groupLimit',
    );
    _branches.add(receipt);
    _total.add(receipt);
    (_months[month] ??= _SpendingFold()).add(receipt);
  }

  SpendingSummary build() {
    final months = _months.keys.toList()..sort((a, b) => b.compareTo(a));
    return SpendingSummary(_total.build(), _branches.build(), [
      for (final key in months)
        MonthlySpending(key ~/ 100, key % 100, _months[key]!.build()),
    ]);
  }
}

/// Shared selected-receipt branch fold. Labels never come from comparison data.
final class _BranchSpendingBuilder {
  final _folds = <DurableId, _SpendingFold>{};
  final _labels =
      <DurableId, ({ReceiptBranch branch, int day, String receiptId})>{};
  void add(ReceiptSnapshot receipt) {
    final branch = receipt.branch.id;
    _require(
      _folds.containsKey(branch) || _folds.length < 128,
      'spending',
      'groupLimit',
    );
    final previous = _labels[branch];
    final day = purchaseCalendarDay(receipt.date);
    if (previous == null ||
        day > previous.day ||
        (day == previous.day &&
            receipt.id.value.compareTo(previous.receiptId) > 0)) {
      _labels[branch] = (
        branch: receipt.branch,
        day: day,
        receiptId: receipt.id.value,
      );
    }
    (_folds[branch] ??= _SpendingFold()).add(receipt);
  }

  List<BranchSpending> build() {
    final branches = _folds.keys.toList()
      ..sort((a, b) {
        final order = _labels[a]!.branch.name.compareTo(
          _labels[b]!.branch.name,
        );
        return order == 0 ? a.value.compareTo(b.value) : order;
      });
    return [
      for (final id in branches)
        BranchSpending(_labels[id]!.branch, _folds[id]!.build()),
    ];
  }
}

final class _SpendingFold {
  int count = 0, negative = 0, adjusted = 0, unlinked = 0;
  BigInt cents = BigInt.zero;
  void add(ReceiptSnapshot receipt) {
    count++;
    cents += receipt.totalCents;
    if (receipt.totalCents.isNegative) negative++;
    if (receipt.items.any((row) => row.kind == LineKind.adjustment)) adjusted++;
    if (receipt.items.any(
      (row) => row.kind == LineKind.product && row.product == null,
    ))
      unlinked++;
  }

  SpendingTotals build() =>
      SpendingTotals(count, cents, negative, adjusted, unlinked);
}
