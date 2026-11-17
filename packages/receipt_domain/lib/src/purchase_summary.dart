part of '../receipt_domain.dart';

/// Inclusive printed Helsinki calendar days; never UTC instants.
final class PurchaseDateRange {
  PurchaseDateRange({this.fromDate, this.throughDate}) {
    for (final date in [fromDate, throughDate]) {
      _require(
        date == null || date.hour == null,
        'purchase.range',
        'dayRequired',
      );
    }
    _require(
      fromDate == null ||
          throughDate == null ||
          purchaseCalendarDay(fromDate!) <= purchaseCalendarDay(throughDate!),
      'purchase.range',
      'reversed',
    );
  }
  final StoredReceiptDate? fromDate, throughDate;
  bool contains(StoredReceiptDate date) =>
      (fromDate == null ||
          purchaseCalendarDay(date) >= purchaseCalendarDay(fromDate!)) &&
      (throughDate == null ||
          purchaseCalendarDay(date) <= purchaseCalendarDay(throughDate!));
  bool get isEmpty => fromDate == null && throughDate == null;
}

/// Gregorian day ordinal used only for calendar intervals, not receipt instants.
int purchaseCalendarDay(StoredReceiptDate date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(1970)).inDays;
StoredReceiptDate purchaseCalendarDate(int day) {
  final date = DateTime.utc(1970).add(Duration(days: day));
  return StoredReceiptDate.parse('${date.day}.${date.month}.${date.year}');
}

final class PurchasePriceBucket {
  const PurchasePriceBucket({
    required this.firstDay,
    required this.lastDay,
    required this.count,
    required this.minimum,
    required this.maximum,
  });
  final int firstDay, lastDay, count;
  final UnitPrice minimum, maximum;
}

final class PurchasePriceGroup {
  PurchasePriceGroup({
    required this.unit,
    required this.productRevision,
    required this.count,
    required this.minimum,
    required this.maximum,
    required this.receiptDiscountRows,
    required this.adjustmentRows,
    required Iterable<PurchasePriceBucket> buckets,
  }) : buckets = List.unmodifiable(buckets);
  final QuantityUnit unit;
  final RevisionId? productRevision;
  final int count, receiptDiscountRows, adjustmentRows;
  final UnitPrice minimum, maximum;
  final List<PurchasePriceBucket> buckets;
}

final class PurchaseSummary {
  PurchaseSummary({
    required this.totalRows,
    required this.comparableRows,
    required this.returnRows,
    required this.missingQuantityRows,
    required this.negativeEffectiveRows,
    required this.receiptDiscountRows,
    required this.adjustmentRows,
    required this.rawCents,
    required this.effectiveCents,
    required this.firstDay,
    required this.lastDay,
    required Iterable<PurchasePriceGroup> groups,
  }) : groups = List.unmodifiable(groups);
  final int totalRows,
      comparableRows,
      returnRows,
      missingQuantityRows,
      negativeEffectiveRows,
      receiptDiscountRows,
      adjustmentRows;
  final BigInt rawCents, effectiveCents;
  final int? firstDay, lastDay;
  final List<PurchasePriceGroup> groups;
}

/// Exact streaming fold. At most 64 comparison groups, 24 buckets each.
/// Overflow fails the whole summary; callers must never present partial results.
final class PurchaseSummaryBuilder {
  PurchaseSummaryBuilder({
    required this.storeId,
    required this.productId,
    required this.firstDay,
    required this.lastDay,
  }) {
    _require(
      (firstDay == null && lastDay == null) ||
          (firstDay != null && lastDay != null && firstDay! <= lastDay!),
      'purchase.summary',
      'range',
    );
  }
  final DurableId storeId, productId;
  final int? firstDay, lastDay;
  final _groups = <(QuantityUnit, RevisionId?), _PriceGroupBuilder>{};
  int _total = 0,
      _comparable = 0,
      _returns = 0,
      _missing = 0,
      _negative = 0,
      _receiptDiscounts = 0,
      _adjustments = 0;
  BigInt _raw = BigInt.zero, _effective = BigInt.zero;
  int get bucketCount =>
      firstDay == null ? 0 : min(24, lastDay! - firstDay! + 1);

  void add(ProductPurchase purchase) {
    _require(
      purchase.row.product!.storeId == storeId &&
          purchase.row.product!.id == productId,
      'purchase.summary',
      'identity',
    );
    final day = purchaseCalendarDay(purchase.date);
    _require(
      firstDay != null && day >= firstDay! && day <= lastDay!,
      'purchase.summary',
      'outsideRange',
    );
    final price = purchase.effectiveUnitPrice;
    final group = purchase.comparisonGroup;
    if (group != null && !_groups.containsKey(group)) {
      _require(_groups.length < 64, 'purchase.summary', 'groupLimit');
      _groups[group] = _PriceGroupBuilder(group.$1, group.$2);
    }
    _total++;
    _raw += purchase.row.cents;
    _effective += purchase.effectiveCents;
    if (purchase.receiptDiscountCents != BigInt.zero) _receiptDiscounts++;
    if (purchase.hasReceiptAdjustment) _adjustments++;
    if (purchase.isReturn) {
      _returns++;
    } else if (purchase.row.quantityValue == null) {
      _missing++;
    } else if (price == null) {
      _negative++;
    } else {
      _comparable++;
      final index =
          (day - firstDay!) * bucketCount ~/ (lastDay! - firstDay! + 1);
      _groups[group]!.add(purchase, price, index);
    }
  }

  PurchaseSummary finish() => PurchaseSummary(
    totalRows: _total,
    comparableRows: _comparable,
    returnRows: _returns,
    missingQuantityRows: _missing,
    negativeEffectiveRows: _negative,
    receiptDiscountRows: _receiptDiscounts,
    adjustmentRows: _adjustments,
    rawCents: _raw,
    effectiveCents: _effective,
    firstDay: firstDay,
    lastDay: lastDay,
    groups: [
      for (final group in _groups.values)
        group.finish(firstDay!, lastDay!, bucketCount),
    ],
  );
}

final class _PriceGroupBuilder {
  _PriceGroupBuilder(this.unit, this.revision);
  final QuantityUnit unit;
  final RevisionId? revision;
  int count = 0, discounts = 0, adjustments = 0;
  UnitPrice? minimum, maximum;
  final buckets = <int, _PriceBucketBuilder>{};
  void add(ProductPurchase p, UnitPrice price, int index) {
    count++;
    if (p.receiptDiscountCents != BigInt.zero) discounts++;
    if (p.hasReceiptAdjustment) adjustments++;
    if (minimum == null || price.compareTo(minimum!) < 0) minimum = price;
    if (maximum == null || price.compareTo(maximum!) > 0) maximum = price;
    (buckets[index] ??= _PriceBucketBuilder()).add(price);
  }

  PurchasePriceGroup finish(int first, int last, int bucketCount) {
    final span = last - first + 1;
    final indices = buckets.keys.toList()..sort();
    // Invert floor(day * count / span) with exact integer ceiling boundaries.
    int boundary(int index) =>
        first + (index * span + bucketCount - 1) ~/ bucketCount;
    return PurchasePriceGroup(
      unit: unit,
      productRevision: revision,
      count: count,
      minimum: minimum!,
      maximum: maximum!,
      receiptDiscountRows: discounts,
      adjustmentRows: adjustments,
      buckets: [
        for (final i in indices)
          PurchasePriceBucket(
            firstDay: boundary(i),
            lastDay: boundary(i + 1) - 1,
            count: buckets[i]!.count,
            minimum: buckets[i]!.minimum!,
            maximum: buckets[i]!.maximum!,
          ),
      ],
    );
  }
}

final class _PriceBucketBuilder {
  int count = 0;
  UnitPrice? minimum, maximum;
  void add(UnitPrice price) {
    count++;
    if (minimum == null || price.compareTo(minimum!) < 0) minimum = price;
    if (maximum == null || price.compareTo(maximum!) > 0) maximum = price;
  }
}
