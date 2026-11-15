import 'finance.dart';
import 'parser.dart';
import 'review.dart';

enum ReviewRelationshipKind {
  quantity,
  explanatoryPrice,
  productDiscount,
  receiptDiscount,
}

/// Field prerequisites for an explicit, image-backed relationship decision.
/// This does not infer a target from proximity or matching arithmetic, allocate
/// discounts, or create a second financial contribution from explanatory text.
bool canResolveRelationship(
  ParseFinding finding,
  ReviewRelationshipKind kind, {
  ReviewRowInput? source,
  ReviewRowInput? target,
}) {
  if (finding.words.isEmpty) return false;
  final product =
      target != null &&
      target.kind == LineKind.product &&
      target.name.trim().isNotEmpty &&
      parseCents(target.amount) != null;
  switch (kind) {
    case ReviewRelationshipKind.quantity:
      return finding.issue == ParseIssue.quantityWithoutProduct &&
          finding.rowIndex == null &&
          product &&
          target.quantityState == QuantityReviewState.matched;
    case ReviewRelationshipKind.explanatoryPrice:
      return finding.issue == ParseIssue.discountNeedsReview &&
          finding.discountKind == DiscountFindingKind.explanatoryPrice &&
          finding.rowIndex == null &&
          product;
    case ReviewRelationshipKind.productDiscount:
    case ReviewRelationshipKind.receiptDiscount:
      final cents = source == null ? null : parseCents(source.amount);
      return finding.issue == ParseIssue.discountNeedsReview &&
          finding.discountKind == DiscountFindingKind.postedDiscount &&
          finding.rowIndex != null &&
          source?.kind == LineKind.discount &&
          source!.name.trim().isNotEmpty &&
          cents != null &&
          cents < BigInt.zero &&
          (kind == ReviewRelationshipKind.productDiscount
              ? product
              : target == null);
  }
}
