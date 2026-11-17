part of 'repository.dart';

final class StoredProductPurchase {
  const StoredProductPurchase(this.receipt, this.purchase);
  final StoredReceipt receipt;
  final ProductPurchase purchase;
}

extension ProductPurchaseHistory on ReceiptRepository {
  /// Filter before pagination. Each observation is a row, including duplicate
  /// purchases on one receipt. Only current nondeleted receipt heads contribute.
  Future<List<StoredProductPurchase>> purchases(
    DurableId storeId,
    DurableId productId, {
    int limit = 30,
    int offset = 0,
  }) {
    if (limit < 1 || limit > 200 || offset < 0) {
      throw ArgumentError('invalid_purchase_page');
    }
    return _guard(
      () => _db.transaction(() async {
        final rows = await _rows(
          'SELECT i.receipt_id, i.id FROM receipt_items i '
          'JOIN receipts r ON r.id = i.receipt_id '
          'WHERE r.is_deleted = 0 AND r.store_id = ? AND i.store_id = ? '
          "AND i.product_id = ? AND i.kind = 'product' "
          'ORDER BY r.printed_year DESC, r.printed_month DESC, r.printed_day DESC, '
          'COALESCE(r.printed_hour, -1) DESC, COALESCE(r.printed_minute, -1) DESC, '
          'COALESCE(r.printed_second, -1) DESC, r.id ASC, i.position ASC LIMIT ? OFFSET ?',
          [storeId.value, storeId.value, productId.value, limit, offset],
        );
        final receipts = <DurableId, StoredReceipt>{};
        final result = <StoredProductPurchase>[];
        for (final row in rows) {
          final id = DurableId.parse(row['receipt_id']! as String);
          final receipt = receipts[id] ??= (await _read(id))!;
          result.add(
            StoredProductPurchase(
              receipt,
              ProductPurchase.fromReceipt(
                receipt.document.snapshot,
                DurableId.parse(row['id']! as String),
              ),
            ),
          );
        }
        return List.unmodifiable(result);
      }),
    );
  }
}
