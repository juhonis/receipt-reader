part of '../receipt_domain.dart';

enum SpendingPeriodUnit { week, month }

/// Inclusive civil-day interval, not a duration measured in a device timezone.
final class SpendingPeriod {
  const SpendingPeriod(this.firstDay, this.lastDay, {this.inProgress = false});
  final int firstDay, lastDay;
  final bool inProgress;
  int get dayCount => lastDay - firstDay + 1;
  bool contains(int day) => day >= firstDay && day <= lastDay;
}

/// Twelve calendar periods ending at the selected week/month. Future days are
/// excluded. The first supported week can be clipped to January 1, 1970.
final class SpendingDashboardQuery {
  SpendingDashboardQuery({
    required this.unit,
    required this.anchor,
    required this.today,
    this.branchId,
  }) {
    _require(
      anchor.hour == null && today.hour == null,
      'dashboard',
      'dayRequired',
    );
    final day = purchaseCalendarDay(anchor), now = purchaseCalendarDay(today);
    _require(day <= now, 'dashboard', 'futurePeriod');
    final date = DateTime.utc(anchor.year, anchor.month, anchor.day);
    DateTime start(int offset) => unit == SpendingPeriodUnit.week
        ? date.subtract(Duration(days: date.weekday - 1 + offset * 7))
        : DateTime.utc(date.year, date.month - offset);
    int ordinal(DateTime value) => value.difference(DateTime.utc(1970)).inDays;
    SpendingPeriod period(int offset) {
      final first = start(offset);
      final end = unit == SpendingPeriodUnit.week
          ? first.add(const Duration(days: 6))
          : DateTime.utc(first.year, first.month + 1, 0);
      return SpendingPeriod(
        max(0, ordinal(first)),
        min(now, ordinal(end)),
        inProgress: ordinal(first) <= now && now <= ordinal(end),
      );
    }

    periods = List.unmodifiable([
      for (var i = 11; i >= 0; i--)
        if (period(i).lastDay >= 0) period(i),
    ]);
    selected = periods.last;
    final previous = period(1);
    if (previous.lastDay >= 0) {
      // Partial periods compare equally many calendar days. If last month was
      // shorter, both comparison windows are shortened and explicitly labelled.
      final days = min(selected.dayCount, previous.dayCount);
      comparisonCurrent = selected.inProgress
          ? SpendingPeriod(selected.firstDay, selected.firstDay + days - 1)
          : selected;
      comparisonPrevious = selected.inProgress
          ? SpendingPeriod(previous.firstDay, previous.firstDay + days - 1)
          : previous;
    } else {
      comparisonCurrent = null;
      comparisonPrevious = null;
    }
  }
  final SpendingPeriodUnit unit;
  final StoredReceiptDate anchor, today;
  final DurableId? branchId;
  late final List<SpendingPeriod> periods;
  late final SpendingPeriod selected;
  late final SpendingPeriod? comparisonCurrent, comparisonPrevious;
}

final class PeriodSpending {
  const PeriodSpending(this.period, this.totals);
  final SpendingPeriod period;
  final SpendingTotals totals;
}

final class SpendingDashboard {
  SpendingDashboard(
    this.query,
    Iterable<PeriodSpending> periods,
    this.comparisonCurrent,
    this.comparisonPrevious,
  ) : periods = List.unmodifiable(periods);
  final SpendingDashboardQuery query;
  final List<PeriodSpending> periods;
  final SpendingTotals comparisonCurrent, comparisonPrevious;
  SpendingTotals get selected => periods.last.totals;
  BigInt get changeCents =>
      comparisonCurrent.totalCents - comparisonPrevious.totalCents;

  /// Signed percentage, in tenths of a percent. Zero/negative baselines and
  /// missing observations do not have a useful conventional percentage change.
  BigInt? get changeTenthsPercent =>
      query.comparisonPrevious == null ||
          comparisonCurrent.receiptCount == 0 ||
          comparisonPrevious.receiptCount == 0 ||
          comparisonPrevious.totalCents <= BigInt.zero
      ? null
      : roundSpendingRatio(
          changeCents * BigInt.from(1000),
          comparisonPrevious.totalCents,
        );
}

/// Display rounding only: nearest integer, halfway away from zero.
BigInt roundSpendingRatio(BigInt numerator, BigInt denominator) {
  if (denominator <= BigInt.zero) throw ArgumentError.value(denominator);
  final rounded =
      (numerator.abs() * BigInt.two + denominator) ~/
      (denominator * BigInt.two);
  return numerator.isNegative ? -rounded : rounded;
}

BigInt? averageReceiptCents(SpendingTotals totals) => totals.receiptCount == 0
    ? null
    : roundSpendingRatio(totals.totalCents, BigInt.from(totals.receiptCount));

/// Complete receipts counted exactly once per calendar bucket. Constant-sized
/// folds; no receipt list, persisted aggregates, or linked-product prerequisite.
final class SpendingDashboardBuilder {
  SpendingDashboardBuilder(this.query)
    : _folds = [for (final _ in query.periods) _SpendingFold()];
  final SpendingDashboardQuery query;
  final List<_SpendingFold> _folds;
  final _current = _SpendingFold(), _previous = _SpendingFold();
  void add(ReceiptSnapshot receipt) {
    if (query.branchId != null && query.branchId != receipt.branch.id) return;
    final day = purchaseCalendarDay(receipt.date);
    for (var i = 0; i < query.periods.length; i++) {
      if (query.periods[i].contains(day)) {
        _folds[i].add(receipt);
        break;
      }
    }
    if (query.comparisonCurrent?.contains(day) ?? false) _current.add(receipt);
    if (query.comparisonPrevious?.contains(day) ?? false)
      _previous.add(receipt);
  }

  SpendingDashboard build() => SpendingDashboard(
    query,
    [
      for (var i = 0; i < query.periods.length; i++)
        PeriodSpending(query.periods[i], _folds[i].build()),
    ],
    _current.build(),
    _previous.build(),
  );
}
