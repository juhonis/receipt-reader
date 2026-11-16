import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';

DurableId id(int number) => DurableId.parse(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
);

ReceiptItemSnapshot row({
  int number = 3,
  String name = 'Maito 1 l',
  BigInt? cents,
  LineKind kind = LineKind.product,
  DurableId? parent,
  DiscountScope? scope,
  ReceiptProductLink? product,
  String? reason,
  BigInt? quantity,
  int? scale,
  QuantityUnit? unit,
  BigInt? rate,
  String? rawName,
}) => ReceiptItemSnapshot(
  id: id(number),
  name: name,
  kind: kind,
  cents: cents ?? BigInt.from(200),
  parentItemId: parent,
  discountScope: scope,
  product: product,
  adjustmentReason: reason,
  quantityValue: quantity,
  quantityScale: scale,
  quantityUnit: unit,
  rateMicros: rate,
  rawName: rawName,
);

ReceiptSnapshot receipt({
  List<ReceiptItemSnapshot>? items,
  ReceiptBranch? branch,
  String date = '16.11.2026',
  BigInt? total,
  int number = 1,
}) => ReceiptSnapshot(
  id: id(number),
  branch: branch ?? ReceiptBranch(id: id(2), name: 'TEST BRANCH'),
  date: StoredReceiptDate.parse(date),
  totalCents: total ?? BigInt.from(200),
  items: items ?? [row()],
);

ManualReviewChecks checks(
  ReceiptSnapshot snapshot, {
  List<RevisionId> heads = const [],
  Iterable<DurableId>? rows,
  bool branch = true,
  bool date = true,
  bool total = true,
}) => ManualReviewChecks(
  snapshot: snapshot,
  expectedHeads: heads,
  mutationId: id(4),
  branchReviewed: branch,
  dateReviewed: date,
  totalReviewed: total,
  reviewedRowIds: rows ?? snapshot.items.map((item) => item.id),
);

ManualReceiptConfirmation confirm(
  ReceiptSnapshot snapshot, {
  List<RevisionId> heads = const [],
}) => checks(
  snapshot,
  heads: heads,
).confirm(reviewedAtMs: BigInt.from(123), appVersion: '0.1.0+1');

ReviewedReceipt command(ReceiptSnapshot snapshot) => ReviewedReceipt.manual(
  current: snapshot,
  expectedHeads: [],
  confirmation: confirm(snapshot),
);
