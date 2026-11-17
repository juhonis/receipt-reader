import 'package:receipt_domain/receipt_domain.dart';

import 'support.dart';

ProductDocument productDocument(
  ReceiptBranch branch, {
  int number = 10,
  String name = 'TEST MILK',
  RevisionId? head,
  int at = 1000,
}) => ProductDocument(
  product: ProductSnapshot(
    id: id(number),
    storeId: branch.id,
    canonicalName: name,
  ),
  storeRevision: branch.revision!,
  expectedHead: head,
  reviewedAtMs: BigInt.from(at),
  appVersion: 'catalog-test',
);

ProductAliasDocument aliasDocument(
  ReceiptBranch branch,
  RevisionId productRevision, {
  int number = 11,
  int product = 10,
  String name = 'test milk',
  bool active = true,
  RevisionId? head,
  int at = 1001,
}) => ProductAliasDocument(
  alias: ProductAliasSnapshot(
    id: id(number),
    storeId: branch.id,
    normalizedName: name,
    productId: id(product),
    isActive: active,
  ),
  storeRevision: branch.revision!,
  productRevision: productRevision,
  expectedHead: head,
  reviewedAtMs: BigInt.from(at),
  appVersion: 'catalog-test',
);
