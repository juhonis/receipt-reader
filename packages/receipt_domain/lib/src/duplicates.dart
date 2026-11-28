part of '../receipt_domain.dart';

enum ReceiptDuplicateReason { sameMinute, sameDayBranchTotal }

/// A warning candidate, never proof of identity or permission to delete. Printed
/// seconds may be missing/misread, so timestamp matching uses minute precision.
/// Without a time on either receipt, require branch and total as well as the day.
ReceiptDuplicateReason? receiptDuplicateReason(
  ReceiptSnapshot a,
  ReceiptSnapshot b,
) {
  if (a.id == b.id ||
      a.date.year != b.date.year ||
      a.date.month != b.date.month ||
      a.date.day != b.date.day)
    return null;
  if (a.date.hour != null && b.date.hour != null) {
    return a.date.hour == b.date.hour && a.date.minute == b.date.minute
        ? ReceiptDuplicateReason.sameMinute
        : null;
  }
  final sameBranch =
      a.branch.id == b.branch.id ||
      normalizeReceiptNameV1(a.branch.name) ==
          normalizeReceiptNameV1(b.branch.name);
  return sameBranch && a.totalCents == b.totalCents
      ? ReceiptDuplicateReason.sameDayBranchTotal
      : null;
}
