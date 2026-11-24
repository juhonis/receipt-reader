part of '../receipt_domain.dart';

/// A purchased quantity in a common exact 10^-12 base-unit scale. Package
/// content is taken from the receipt's recorded product revision, never today's
/// package. Missing purchased quantities cannot be supplied by package metadata.
final class ComparisonQuantity {
  const ComparisonQuantity(this.unit, this.value);
  final QuantityUnit unit;
  final BigInt value;
}

ComparisonQuantity? comparisonQuantity(
  ProductPurchase p,
  ProductSnapshot saved,
) {
  _require(
    p.row.product!.id == saved.id && p.row.product!.storeId == saved.storeId,
    'comparison',
    'identity',
  );
  if (p.isReturn || p.row.quantityValue == null || p.effectiveCents.isNegative)
    return null;
  final unit = p.row.quantityUnit!;
  if (unit == QuantityUnit.kg || unit == QuantityUnit.litre) {
    return ComparisonQuantity(
      unit,
      p.row.quantityValue! * BigInt.from(10).pow(12 - p.row.quantityScale!),
    );
  }
  if (unit != QuantityUnit.piece || saved.packageValue == null) return null;
  return ComparisonQuantity(
    saved.packageUnit!,
    p.row.quantityValue! *
        saved.packageValue! *
        BigInt.from(10).pow(12 - p.row.quantityScale! - saved.packageScale!),
  );
}

final class ProductComparisonSeries {
  ProductComparisonSeries(
    this.branch,
    this.unit,
    this.count,
    this.minimum,
    this.maximum,
    this.weightedMean,
    Iterable<PurchasePriceBucket> buckets,
  ) : buckets = List.unmodifiable(buckets);
  final ReceiptBranch branch;
  final QuantityUnit unit;
  final int count;
  final UnitPrice minimum, maximum, weightedMean;
  final List<PurchasePriceBucket> buckets;
}

final class ProductComparisonSummary {
  ProductComparisonSummary(
    this.firstDay,
    this.lastDay,
    this.totalRows,
    this.comparableRows,
    this.returnRows,
    this.missingQuantityRows,
    this.missingPackageRows,
    this.negativeRows,
    this.receiptDiscountRows,
    this.adjustmentRows,
    Iterable<ProductComparisonSeries> series,
  ) : series = List.unmodifiable(series);
  final int? firstDay, lastDay;
  final int totalRows,
      comparableRows,
      returnRows,
      missingQuantityRows,
      missingPackageRows,
      negativeRows,
      receiptDiscountRows,
      adjustmentRows;
  final List<ProductComparisonSeries> series;
}

/// One verified read, complete bounded folds: at most 64 branch/unit series and
/// 24 shared calendar buckets. Rankings and prices never use rounded numbers.
final class ProductComparisonBuilder {
  ProductComparisonBuilder(this.firstDay, this.lastDay) {
    _require(
      firstDay == null && lastDay == null ||
          firstDay != null && lastDay != null && firstDay! <= lastDay!,
      'comparison',
      'range',
    );
  }
  final int? firstDay, lastDay;
  final _groups = <(DurableId, QuantityUnit), _ComparisonSeriesBuilder>{};
  int _total = 0,
      _comparable = 0,
      _returns = 0,
      _quantity = 0,
      _package = 0,
      _negative = 0,
      _discounts = 0,
      _adjustments = 0;
  int get bucketCount =>
      firstDay == null ? 0 : min(24, lastDay! - firstDay! + 1);
  void add(ProductPurchase p, ProductSnapshot saved, ReceiptBranch branch) {
    final day = purchaseCalendarDay(p.date);
    _require(
      firstDay != null &&
          day >= firstDay! &&
          day <= lastDay! &&
          branch.id == saved.storeId,
      'comparison',
      'outsideRange',
    );
    // Validate identity even for rows excluded from price calculations.
    final q = comparisonQuantity(p, saved);
    _total++;
    if (p.receiptDiscountCents != BigInt.zero) _discounts++;
    if (p.hasReceiptAdjustment) _adjustments++;
    if (p.isReturn) {
      _returns++;
      return;
    }
    if (p.row.quantityValue == null) {
      _quantity++;
      return;
    }
    if (p.effectiveCents.isNegative) {
      _negative++;
      return;
    }
    if (q == null) {
      _package++;
      return;
    }
    final key = (branch.id, q.unit);
    _require(
      _groups.containsKey(key) || _groups.length < 64,
      'comparison',
      'groupLimit',
    );
    final fold = _groups[key] ??= _ComparisonSeriesBuilder(branch, q.unit);
    final index = (day - firstDay!) * bucketCount ~/ (lastDay! - firstDay! + 1);
    fold.add(index, p.effectiveCents, q.value);
    _comparable++;
  }

  ProductComparisonSummary finish() {
    final series = [
      for (final fold in _groups.values)
        fold.finish(firstDay!, lastDay!, bucketCount),
    ];
    series.sort((a, b) {
      final unit = a.unit.index.compareTo(b.unit.index);
      if (unit != 0) return unit;
      final price = a.weightedMean.compareTo(b.weightedMean);
      return price != 0
          ? price
          : a.branch.id.value.compareTo(b.branch.id.value);
    });
    return ProductComparisonSummary(
      firstDay,
      lastDay,
      _total,
      _comparable,
      _returns,
      _quantity,
      _package,
      _negative,
      _discounts,
      _adjustments,
      series,
    );
  }
}

final class _ComparisonAmounts {
  int count = 0;
  BigInt cents = BigInt.zero, quantity = BigInt.zero;
  UnitPrice? minimum, maximum;
  void add(BigInt value, BigInt units) {
    final price = UnitPrice._(value * BigInt.from(10).pow(12), units);
    count++;
    cents += value;
    quantity += units;
    if (minimum == null || price.compareTo(minimum!) < 0) minimum = price;
    if (maximum == null || price.compareTo(maximum!) > 0) maximum = price;
  }

  UnitPrice get mean => UnitPrice._(cents * BigInt.from(10).pow(12), quantity);
}

final class _ComparisonSeriesBuilder {
  _ComparisonSeriesBuilder(this.branch, this.unit);
  final ReceiptBranch branch;
  final QuantityUnit unit;
  final all = _ComparisonAmounts();
  final buckets = <int, _ComparisonAmounts>{};
  void add(int index, BigInt cents, BigInt quantity) {
    all.add(cents, quantity);
    (buckets[index] ??= _ComparisonAmounts()).add(cents, quantity);
  }

  ProductComparisonSeries finish(int first, int last, int count) {
    final keys = buckets.keys.toList()..sort();
    return ProductComparisonSeries(
      branch,
      unit,
      all.count,
      all.minimum!,
      all.maximum!,
      all.mean,
      [
        for (final i in keys)
          PurchasePriceBucket(
            firstDay: _bucketBoundary(first, last, count, i),
            lastDay: _bucketBoundary(first, last, count, i + 1) - 1,
            count: buckets[i]!.count,
            minimum: buckets[i]!.minimum!,
            maximum: buckets[i]!.maximum!,
            weightedMean: buckets[i]!.mean,
          ),
      ],
    );
  }
}
