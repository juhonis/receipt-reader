part of 'repository.dart';

final class StoredProductPurchase {
  const StoredProductPurchase(this.receipt, this.purchase);
  final StoredReceipt receipt;
  final ProductPurchase purchase;
}

/// Summary and one detail page from the same database transaction.
final class PurchaseHistoryResult {
  PurchaseHistoryResult(this.summary, Iterable<StoredProductPurchase> purchases)
    : purchases = List.unmodifiable(purchases);
  final PurchaseSummary summary;
  final List<StoredProductPurchase> purchases;
}

extension ProductPurchaseHistory on ReceiptRepository {
  Future<List<StoredProductPurchase>> purchases(
    DurableId storeId,
    DurableId productId, {
    PurchaseDateRange? range,
    int limit = 30,
    int offset = 0,
  }) {
    _purchasePage(limit, offset);
    return _guard(
      () => _db.transaction(
        () => _purchaseRows(
          _PurchaseQuery(storeId, productId, range),
          limit,
          offset,
        ),
      ),
    );
  }

  /// Streams every matching current receipt once, retaining only 64 groups with
  /// 24 calendar buckets each. No limit on contributing rows or silent truncation.
  Future<PurchaseHistoryResult> purchaseHistory(
    DurableId storeId,
    DurableId productId, {
    PurchaseDateRange? range,
    int limit = 30,
    int offset = 0,
  }) {
    _purchasePage(limit, offset);
    return _guard(
      () => _db.transaction(() async {
        final query = _PurchaseQuery(storeId, productId, range);
        final span = (await _rows(
          'SELECT MIN(r.printed_year*10000+r.printed_month*100+r.printed_day) AS first, '
          'MAX(r.printed_year*10000+r.printed_month*100+r.printed_day) AS last '
          '${query.from} WHERE ${query.where}',
          query.args,
        )).single;
        int day(int value) => purchaseCalendarDay(
          StoredReceiptDate.parse(
            '${value % 100}.${value ~/ 100 % 100}.${value ~/ 10000}',
          ),
        );
        final first = span['first'] as int?, last = span['last'] as int?;
        final builder = PurchaseSummaryBuilder(
          storeId: storeId,
          productId: productId,
          firstDay: first == null
              ? null
              : range?.fromDate == null
              ? day(first)
              : purchaseCalendarDay(range!.fromDate!),
          lastDay: last == null
              ? null
              : range?.throughDate == null
              ? day(last)
              : purchaseCalendarDay(range!.throughDate!),
        );
        var cursor = '';
        while (true) {
          // Walk receipt primary keys rather than sorting/deduplicating every
          // matching item ID into an intermediate SQLite result.
          final batch = await _rows(
            'SELECT r.id FROM receipts r WHERE r.id > ? AND EXISTS ('
            'SELECT 1 FROM receipt_items i WHERE i.receipt_id = r.id AND ${query.where}) '
            'ORDER BY r.id LIMIT 16',
            [cursor, ...query.args],
          );
          if (batch.isEmpty) break;
          for (final row in batch) {
            cursor = row['id']! as String;
            final receipt = (await _read(DurableId.parse(cursor)))!
                .document
                .snapshot;
            for (final item in receipt.items) {
              if (item.product?.id != productId) continue;
              try {
                builder.add(ProductPurchase.fromReceipt(receipt, item.id));
              } on ReceiptDataException catch (e) {
                if (e.field == 'purchase.summary' && e.code == 'groupLimit') {
                  throw const StorageFailure('purchaseGroupLimit');
                }
                rethrow;
              }
            }
          }
        }
        return PurchaseHistoryResult(
          builder.finish(),
          await _purchaseRows(query, limit, offset),
        );
      }),
    );
  }

  Future<List<StoredProductPurchase>> _purchaseRows(
    _PurchaseQuery query,
    int limit,
    int offset,
  ) async {
    final rows = await _rows(
      'SELECT i.receipt_id, i.id ${query.from} WHERE ${query.where} '
      'ORDER BY r.printed_year DESC, r.printed_month DESC, r.printed_day DESC, '
      'COALESCE(r.printed_hour, -1) DESC, COALESCE(r.printed_minute, -1) DESC, '
      'COALESCE(r.printed_second, -1) DESC, r.id ASC, i.position ASC LIMIT ? OFFSET ?',
      [...query.args, limit, offset],
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
  }
}

void _purchasePage(int limit, int offset) {
  if (limit < 1 || limit > 200 || offset < 0)
    throw ArgumentError('invalid_purchase_page');
}

final class _PurchaseQuery {
  _PurchaseQuery(
    DurableId storeId,
    DurableId productId,
    PurchaseDateRange? range,
  ) : args = [storeId.value, storeId.value, productId.value] {
    for (final bound in [(range?.fromDate, '>='), (range?.throughDate, '<=')]) {
      if (bound.$1 case final date?) {
        where +=
            ' AND (r.printed_year, r.printed_month, r.printed_day) ${bound.$2} (?, ?, ?)';
        args.addAll([date.year, date.month, date.day]);
      }
    }
  }
  final from = 'FROM receipt_items i JOIN receipts r ON r.id = i.receipt_id';
  String where =
      'r.is_deleted = 0 AND r.store_id = ? AND i.store_id = ? '
      "AND i.product_id = ? AND i.kind = 'product'";
  final List<Object> args;
}
