part of '../receipt_domain.dart';

enum SpendingPeriodUnit { week, month, year, custom }

enum SpendingChartScale { day, month, interval }

/// Inclusive civil-day interval, not a duration measured in a device timezone.
final class SpendingPeriod {
  const SpendingPeriod(this.firstDay, this.lastDay, {this.inProgress = false});
  final int firstDay, lastDay;
  final bool inProgress;
  int get dayCount => lastDay - firstDay + 1;
  bool contains(int day) => day >= firstDay && day <= lastDay;
}

/// Chart buckets partition the selected range, never the comparison range.
/// Future days are excluded. Comparisons use verified receipts in the same read.
final class SpendingDashboardQuery {
  SpendingDashboardQuery({
    required this.unit,
    required this.anchor,
    required this.today,
    this.branchId,
    this.customFrom,
    this.customThrough,
  }) {
    _require(
      anchor.hour == null && today.hour == null,
      'dashboard',
      'dayRequired',
    );
    final day = purchaseCalendarDay(anchor), now = purchaseCalendarDay(today);
    _require(day <= now, 'dashboard', 'futurePeriod');
    final date = DateTime.utc(anchor.year, anchor.month, anchor.day);
    int ordinal(DateTime value) => value.difference(DateTime.utc(1970)).inDays;
    if (unit == SpendingPeriodUnit.custom) {
      _require(
        customFrom != null &&
            customThrough != null &&
            customFrom!.hour == null &&
            customThrough!.hour == null,
        'dashboard',
        'customDaysRequired',
      );
      final first = purchaseCalendarDay(customFrom!),
          last = purchaseCalendarDay(customThrough!);
      _require(first <= last && last <= now, 'dashboard', 'customRange');
      selected = SpendingPeriod(first, last);
      final preceding = first - selected.dayCount;
      // Never compare a complete range with a silently clipped predecessor.
      comparisonCurrent = preceding < 0 ? null : selected;
      comparisonPrevious = preceding < 0
          ? null
          : SpendingPeriod(preceding, first - 1);
    } else {
      DateTime start(int offset) => unit == SpendingPeriodUnit.week
          ? date.subtract(Duration(days: date.weekday - 1 + offset * 7))
          : unit == SpendingPeriodUnit.year
          ? DateTime.utc(date.year - offset)
          : DateTime.utc(date.year, date.month - offset);
      SpendingPeriod period(int offset) {
        final first = start(offset);
        final end = unit == SpendingPeriodUnit.week
            ? first.add(const Duration(days: 6))
            : unit == SpendingPeriodUnit.year
            ? DateTime.utc(first.year + 1, 1, 0)
            : DateTime.utc(first.year, first.month + 1, 0);
        return SpendingPeriod(
          max(0, ordinal(first)),
          min(now, ordinal(end)),
          inProgress: ordinal(first) <= now && now <= ordinal(end),
        );
      }

      selected = period(0);
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
    final buckets = <SpendingPeriod>[];
    if (unit == SpendingPeriodUnit.year) {
      chartScale = SpendingChartScale.month;
      for (var month = 1; month <= 12; month++) {
        final first = ordinal(DateTime.utc(anchor.year, month));
        if (first > selected.lastDay) break;
        final last = min(
          selected.lastDay,
          ordinal(DateTime.utc(anchor.year, month + 1, 0)),
        );
        buckets.add(
          SpendingPeriod(
            first,
            last,
            inProgress: selected.inProgress && last == selected.lastDay,
          ),
        );
      }
    } else {
      final count = min(
        selected.dayCount,
        unit == SpendingPeriodUnit.custom ? 24 : 31,
      );
      chartScale = count == selected.dayCount
          ? SpendingChartScale.day
          : SpendingChartScale.interval;
      for (var i = 0; i < count; i++) {
        buckets.add(
          SpendingPeriod(
            selected.firstDay + selected.dayCount * i ~/ count,
            selected.firstDay + selected.dayCount * (i + 1) ~/ count - 1,
            inProgress: selected.inProgress && i == count - 1,
          ),
        );
      }
    }
    periods = List.unmodifiable(buckets);
  }
  final SpendingPeriodUnit unit;
  final StoredReceiptDate anchor, today;
  final DurableId? branchId;
  final StoredReceiptDate? customFrom, customThrough;
  late final SpendingChartScale chartScale;
  late final List<SpendingPeriod> periods;
  late final SpendingPeriod selected;
  late final SpendingPeriod? comparisonCurrent, comparisonPrevious;
  int get scanFirstDay => comparisonPrevious?.firstDay ?? selected.firstDay;
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
    this.selected,
    Iterable<BranchSpending> branches,
    this.categories,
  ) : periods = List.unmodifiable(periods),
      branches = List.unmodifiable(branches);
  final SpendingDashboardQuery query;
  final List<PeriodSpending> periods;
  final SpendingTotals comparisonCurrent, comparisonPrevious;
  final SpendingTotals selected;
  final CategorySpendingSummary categories;

  /// Selected range only, sorted by descending signed net, then label and ID.
  final List<BranchSpending> branches;
  BigInt get positiveBranchNet => branches.fold(
    BigInt.zero,
    (sum, b) =>
        b.totals.totalCents > BigInt.zero ? sum + b.totals.totalCents : sum,
  );
  BigInt get negativeBranchNet => branches.fold(
    BigInt.zero,
    (sum, b) =>
        b.totals.totalCents < BigInt.zero ? sum + b.totals.totalCents : sum,
  );
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
  final _branches = _BranchSpendingBuilder();
  final _categories = CategorySpendingBuilder();
  final _current = _SpendingFold(),
      _previous = _SpendingFold(),
      _selected = _SpendingFold();
  void add(
    ReceiptSnapshot receipt, {
    Map<DurableId, String?> productCategories = const {},
  }) {
    if (query.branchId != null && query.branchId != receipt.branch.id) return;
    final day = purchaseCalendarDay(receipt.date);
    if (query.selected.contains(day)) {
      _branches.add(receipt);
      _selected.add(receipt);
      _categories.add(receipt, productCategories);
    }
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

  SpendingDashboard build() {
    final branches = _branches.build()
      ..sort((a, b) {
        final amount = b.totals.totalCents.compareTo(a.totals.totalCents);
        if (amount != 0) return amount;
        final name = a.branch.name.compareTo(b.branch.name);
        return name != 0
            ? name
            : a.branch.id.value.compareTo(b.branch.id.value);
      });
    return SpendingDashboard(
      query,
      [
        for (var i = 0; i < query.periods.length; i++)
          PeriodSpending(query.periods[i], _folds[i].build()),
      ],
      _current.build(),
      _previous.build(),
      _selected.build(),
      branches,
      _categories.build(),
    );
  }
}
