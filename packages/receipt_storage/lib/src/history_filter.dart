import 'package:receipt_domain/receipt_domain.dart';

/// Inclusive bounds on printed Helsinki calendar days and exact signed cents.
/// Date bounds must have day precision; they never represent UTC instants.
final class HistoryFilter {
  HistoryFilter({
    this.branchId,
    this.fromDate,
    this.throughDate,
    this.minTotalCents,
    this.maxTotalCents,
  }) {
    for (final date in [fromDate, throughDate]) {
      if (date != null && date.hour != null) {
        throw ArgumentError('history_date_requires_day_precision');
      }
    }
    if (fromDate != null &&
        throughDate != null &&
        _day(fromDate!) > _day(throughDate!)) {
      throw ArgumentError('history_date_range');
    }
    for (final amount in [minTotalCents, maxTotalCents]) {
      if (amount != null) checkedInt64(amount, 'history.amount');
    }
    if (minTotalCents != null &&
        maxTotalCents != null &&
        minTotalCents! > maxTotalCents!) {
      throw ArgumentError('history_amount_range');
    }
  }

  final DurableId? branchId;
  final StoredReceiptDate? fromDate, throughDate;
  final BigInt? minTotalCents, maxTotalCents;

  bool get isEmpty =>
      branchId == null &&
      fromDate == null &&
      throughDate == null &&
      minTotalCents == null &&
      maxTotalCents == null;

  static int _day(StoredReceiptDate date) =>
      date.year * 10000 + date.month * 100 + date.day;
}
