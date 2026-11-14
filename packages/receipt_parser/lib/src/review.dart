import 'finance.dart';
import 'receipt_date.dart';

class ReviewRowInput {
  const ReviewRowInput(this.name, this.amount, this.kind);
  final String name, amount;
  final LineKind kind;
}

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
        !hasUnresolvedParserIssues &&
        reviewed;
  }
  late final bool branchValid,
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
