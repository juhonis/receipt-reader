import 'finance.dart';
import 'receipt_date.dart';

class ReviewRowInput {
  const ReviewRowInput(
    this.name,
    this.amount,
    this.kind, {
    this.quantity = '',
    this.rate = '',
    this.unit = QuantityUnit.unknown,
  });
  final String name, amount;
  final String quantity, rate;
  final QuantityUnit unit;
  final LineKind kind;

  QuantityReviewState get quantityState {
    if (quantity.trim().isEmpty &&
        rate.trim().isEmpty &&
        unit == QuantityUnit.unknown) {
      return QuantityReviewState.absent;
    }
    final q = parseFixed(quantity, 6), r = parseFixed(rate, 6);
    final cents = parseCents(amount);
    if (q == null ||
        r == null ||
        cents == null ||
        q == BigInt.zero ||
        r < BigInt.zero ||
        unit == QuantityUnit.unknown) {
      return QuantityReviewState.invalid;
    }
    return extendedCents(Quantity(q, 6, unit), r) == cents
        ? QuantityReviewState.matched
        : QuantityReviewState.mismatched;
  }
}

enum QuantityReviewState { absent, invalid, matched, mismatched }

/// Validation for a temporary manual review, not a persistence authorization.
class ReviewValidation {
  ReviewValidation({
    required String branch,
    required String dateText,
    required String totalText,
    required List<ReviewRowInput> rows,
    required bool branchConfirmed,
    required bool reviewed,
    bool hasUnresolvedParserIssues = false,
  }) {
    branchValid = branch.trim().isNotEmpty && branchConfirmed;
    date = parseReceiptDate(dateText);
    rowsValid =
        rows.isNotEmpty &&
        rows.every(
          (r) => r.name.trim().isNotEmpty && parseCents(r.amount) != null,
        );
    final parsed = [
      for (final row in rows)
        if (parseCents(row.amount) case final amount?)
          FinancialRow(name: row.name.trim(), cents: amount, kind: row.kind),
    ];
    total = parseCents(totalText);
    quantitiesValid = rows.every(
      (row) =>
          row.quantityState == QuantityReviewState.absent ||
          row.quantityState == QuantityReviewState.matched,
    );
    totals = Reconciliation(parsed, total);
    // Never display a partial sum as reconciled when an amount is malformed.
    totalsValid =
        rowsValid && total != null && totals.state == TotalState.matched;
    positiveDiscount = parsed.any(
      (r) => r.kind == LineKind.discount && r.cents >= BigInt.zero,
    );
    complete =
        branchValid &&
        date.state == ReceiptDateState.valid &&
        totalsValid &&
        !positiveDiscount &&
        quantitiesValid &&
        !hasUnresolvedParserIssues &&
        reviewed;
  }
  late final bool branchValid,
      quantitiesValid,
      rowsValid,
      totalsValid,
      positiveDiscount,
      complete;
  late final ReceiptDateResult date;
  late final BigInt? total;
  late final Reconciliation totals;
}

String formatCents(BigInt cents) {
  final absolute = cents.abs();
  return '${cents.isNegative ? '-' : ''}${absolute ~/ BigInt.from(100)},'
      '${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
}

/// Exact decimal display for editable quantities and EUR/unit rates.
String formatFixed(BigInt value, int scale) {
  if (scale < 0 || scale > 6) throw ArgumentError.value(scale);
  if (scale == 0) return value.toString();
  final digits = value.abs().toString().padLeft(scale + 1, '0');
  final fraction = digits
      .substring(digits.length - scale)
      .replaceFirst(RegExp(r'0+$'), '');
  return '${value.isNegative ? '-' : ''}${digits.substring(0, digits.length - scale)}'
      '${fraction.isEmpty ? '' : ',$fraction'}';
}
