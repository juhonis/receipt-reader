/// Strict decimals: no OCR letter substitutions or inferred missing digits.
BigInt? parseFixed(String text, int decimals) {
  if (decimals < 0 || decimals > 6) throw ArgumentError.value(decimals);
  final value = text.trim().replaceAll('\u2212', '-');
  final match = RegExp(r'^(-?)([0-9]+)(?:[,.]([0-9]+))?$').firstMatch(value);
  if (match == null) return null;
  final fraction = match[3] ?? '';
  if (fraction.length > decimals) return null;
  final result = BigInt.parse('${match[2]}${fraction.padRight(decimals, '0')}');
  return match[1] == '-' ? -result : result;
}

BigInt? parseCents(String text) {
  if (!RegExp(r'^[-\u2212]?[0-9]+[,.][0-9]{2}$').hasMatch(text.trim())) {
    return null;
  }
  return parseFixed(text, 2);
}

enum QuantityUnit { piece, kg, litre, unknown }

class Quantity {
  Quantity(this.value, this.scale, this.unit) {
    if (scale < 0 || scale > 6) throw ArgumentError.value(scale);
  }
  final BigInt value;
  final int scale;
  final QuantityUnit unit;
}

/// Rate is millionths of EUR/unit. Round half away from zero, once, to cents.
BigInt extendedCents(Quantity quantity, BigInt rateMicros) {
  final numerator = quantity.value * rateMicros;
  final denominator = BigInt.from(10).pow(quantity.scale + 4);
  final rounded = (numerator.abs() + denominator ~/ BigInt.two) ~/ denominator;
  return numerator.isNegative ? -rounded : rounded;
}

enum LineKind { product, discount, deposit, adjustment }

class FinancialRow {
  FinancialRow({
    required this.name,
    required this.cents,
    this.kind = LineKind.product,
    this.quantity,
    this.rateMicros,
  });
  final String name;
  final BigInt cents;
  final LineKind kind;
  final Quantity? quantity;
  final BigInt? rateMicros;

  bool? get quantityMatches => quantity == null || rateMicros == null
      ? null
      : extendedCents(quantity!, rateMicros!) == cents;

  FinancialRow withQuantity(Quantity value, BigInt rate) => FinancialRow(
    name: name,
    cents: cents,
    kind: kind,
    quantity: value,
    rateMicros: rate,
  );
}

enum TotalState { matched, mismatched, missing }

class Reconciliation {
  Reconciliation(Iterable<FinancialRow> rows, this.printedTotal)
    : rowSum = rows.fold(BigInt.zero, (sum, row) => sum + row.cents);
  final BigInt rowSum;
  final BigInt? printedTotal;
  BigInt? get difference =>
      printedTotal == null ? null : rowSum - printedTotal!;
  TotalState get state => printedTotal == null
      ? TotalState.missing
      : difference == BigInt.zero
      ? TotalState.matched
      : TotalState.mismatched;
}
