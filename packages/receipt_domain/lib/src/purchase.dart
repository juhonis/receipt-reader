part of '../receipt_domain.dart';

/// Exact cents per purchased unit. No binary floating point or early rounding.
final class UnitPrice implements Comparable<UnitPrice> {
  UnitPrice._(this.numerator, this.denominator);
  final BigInt numerator, denominator;

  factory UnitPrice.fromLine(BigInt cents, BigInt quantity, int scale) {
    _require(quantity > BigInt.zero, 'price.quantity', 'positiveRequired');
    _require(scale >= 0 && scale <= 6, 'price.scale', 'invalid');
    return UnitPrice._(cents * BigInt.from(10).pow(scale), quantity);
  }

  @override
  int compareTo(UnitPrice other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  /// EUR, four decimal places, half away from zero. Display only.
  String get euros {
    final scaled = numerator.abs() * BigInt.from(100);
    var rounded = scaled ~/ denominator;
    if ((scaled % denominator) * BigInt.two >= denominator)
      rounded += BigInt.one;
    final text = rounded.toString().padLeft(5, '0');
    return '${numerator.isNegative && rounded != BigInt.zero ? '-' : ''}${text.substring(0, text.length - 4)},${text.substring(text.length - 4)}';
  }

  /// Display percentage in tenths, rounded once; a free baseline is undefined.
  BigInt? changeTenthsPercentFrom(UnitPrice baseline) {
    if (baseline.numerator <= BigInt.zero) return null;
    final delta =
        (numerator * baseline.denominator - baseline.numerator * denominator) *
        BigInt.from(1000);
    final divisor = denominator * baseline.numerator;
    var rounded = delta.abs() ~/ divisor;
    if (delta.abs() % divisor * BigInt.two >= divisor) rounded += BigInt.one;
    return delta.isNegative ? -rounded : rounded;
  }

  /// Relative drawing coordinate only; comparisons remain exact.
  double positionBetween(UnitPrice low, UnitPrice high) {
    if (low.compareTo(high) == 0) return 0.5;
    final delta = numerator * low.denominator - low.numerator * denominator;
    final range =
        high.numerator * low.denominator - low.numerator * high.denominator;
    final scaled =
        delta *
        high.denominator *
        BigInt.from(1000000) ~/
        (denominator * range);
    return scaled.toDouble() / 1000000;
  }
}

/// Read-only interpretation of one reviewed, explicitly linked product row.
/// Package metadata never supplies a missing purchased quantity.
final class ProductPurchase {
  ProductPurchase._(
    this.receiptId,
    this.date,
    this.row,
    this.itemDiscountCents,
    this.depositCents,
    this.receiptDiscountCents,
    this.hasReceiptAdjustment,
  );

  factory ProductPurchase.fromReceipt(
    ReceiptSnapshot receipt,
    DurableId rowId,
  ) {
    final row = receipt.items.where((r) => r.id == rowId).single;
    _require(
      row.kind == LineKind.product && row.product != null,
      'purchase.row',
      'linkedProductRequired',
    );
    BigInt sum(bool Function(ReceiptItemSnapshot) where) =>
        receipt.items.where(where).fold(BigInt.zero, (sum, r) => sum + r.cents);
    return ProductPurchase._(
      receipt.id,
      receipt.date,
      row,
      sum((r) => r.kind == LineKind.discount && r.parentItemId == row.id),
      sum((r) => r.kind == LineKind.deposit && r.parentItemId == row.id),
      sum(
        (r) =>
            r.kind == LineKind.discount &&
            r.discountScope == DiscountScope.receipt,
      ),
      receipt.items.any((r) => r.kind == LineKind.adjustment),
    );
  }
  final DurableId receiptId;
  final StoredReceiptDate date;
  final ReceiptItemSnapshot row;
  final BigInt itemDiscountCents, depositCents, receiptDiscountCents;
  final bool hasReceiptAdjustment;
  BigInt get effectiveCents => row.cents + itemDiscountCents;
  bool get isReturn =>
      row.cents.isNegative || (row.quantityValue?.isNegative ?? false);

  /// Positive purchases only; free products after item discounts are valid.
  UnitPrice? get effectiveUnitPrice =>
      isReturn || row.quantityValue == null || effectiveCents.isNegative
      ? null
      : UnitPrice.fromLine(
          effectiveCents,
          row.quantityValue!,
          row.quantityScale!,
        );

  /// Piece prices stay separated by saved product revision. Weight/volume
  /// comparisons use the reviewed purchased unit, never current package data.
  (QuantityUnit, RevisionId?)? get comparisonGroup => effectiveUnitPrice == null
      ? null
      : (
          row.quantityUnit!,
          row.quantityUnit == QuantityUnit.piece ? row.product!.revision : null,
        );
}
