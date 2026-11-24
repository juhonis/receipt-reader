part of 'repository.dart';

final class ComparisonMember {
  const ComparisonMember(this.product, this.branch);
  final StoredProduct product;
  final ReceiptBranch branch;
}

final class ProductComparisonResult {
  ProductComparisonResult(
    this.anchor,
    Iterable<ComparisonMember> members,
    this.summary,
  ) : members = List.unmodifiable(members);
  final StoredProduct anchor;
  final List<ComparisonMember> members;
  final ProductComparisonSummary summary;
}

extension CrossStoreProductComparison on ReceiptRepository {
  /// Current explicit membership, historical package revisions and all matching
  /// purchases are resolved inside one transaction, never from detail pages.
  Future<ProductComparisonResult> productComparison(
    DurableId productId, {
    PurchaseDateRange? range,
  }) => _guard(
    () => _db.transaction(() async {
      final anchor = await _product(productId);
      final key = anchor.document.product.comparisonKey;
      final members = <ComparisonMember>[];
      if (key == null)
        return ProductComparisonResult(
          anchor,
          members,
          ProductComparisonBuilder(null, null).finish(),
        );
      var cursor = '';
      while (true) {
        final batch = await _rows(
          'SELECT id FROM products WHERE id > ? ORDER BY id LIMIT 64',
          [cursor],
        );
        if (batch.isEmpty) break;
        for (final row in batch) {
          cursor = row['id']! as String;
          final p = await _product(DurableId.parse(cursor));
          if (p.document.product.comparisonKey != key) continue;
          _check(members.length < 64, 'comparisonGroupLimit');
          final branch = (await _rows('SELECT * FROM stores WHERE id = ?', [
            p.document.product.storeId.value,
          ])).single;
          members.add(ComparisonMember(p, _branch(branch)));
        }
      }
      final memberById = {
        for (final m in members) m.product.document.product.id: m,
      };
      final ids = members
          .map((m) => m.product.document.product.id.value)
          .toList();
      var where =
          "r.is_deleted = 0 AND i.kind = 'product' AND i.product_id IN (${ids.map((_) => '?').join(',')})";
      final args = <Object>[...ids];
      for (final bound in [
        (range?.fromDate, '>='),
        (range?.throughDate, '<='),
      ]) {
        if (bound.$1 case final date?) {
          where +=
              ' AND (r.printed_year, r.printed_month, r.printed_day) ${bound.$2} (?, ?, ?)';
          args.addAll([date.year, date.month, date.day]);
        }
      }
      final span = (await _rows(
        'SELECT MIN(r.printed_year*10000+r.printed_month*100+r.printed_day) AS first, '
        'MAX(r.printed_year*10000+r.printed_month*100+r.printed_day) AS last '
        'FROM receipts r JOIN receipt_items i ON i.receipt_id = r.id WHERE $where',
        args,
      )).single;
      int day(int v) => purchaseCalendarDay(
        StoredReceiptDate.parse('${v % 100}.${v ~/ 100 % 100}.${v ~/ 10000}'),
      );
      final first = span['first'] as int?, last = span['last'] as int?;
      final builder = ProductComparisonBuilder(
        first == null
            ? null
            : range?.fromDate == null
            ? day(first)
            : purchaseCalendarDay(range!.fromDate!),
        last == null
            ? null
            : range?.throughDate == null
            ? day(last)
            : purchaseCalendarDay(range!.throughDate!),
      );
      final packages = LinkedHashMap<RevisionId, ProductSnapshot>();
      cursor = '';
      while (true) {
        final batch = await _rows(
          'SELECT r.id FROM receipts r WHERE r.id > ? AND EXISTS ('
          'SELECT 1 FROM receipt_items i WHERE i.receipt_id = r.id AND $where) ORDER BY r.id LIMIT 16',
          [cursor, ...args],
        );
        if (batch.isEmpty) break;
        for (final row in batch) {
          cursor = row['id']! as String;
          final receipt = (await _read(DurableId.parse(cursor)))!
              .document
              .snapshot;
          for (final item in receipt.items) {
            final member = memberById[item.product?.id];
            if (member == null) continue;
            final link = item.product!;
            var saved = packages.remove(link.revision);
            if (saved == null) {
              final event = (await _rows(
                'SELECT entity_kind, entity_id, payload FROM change_log '
                'WHERE origin_device_id = ? AND origin_seq = ?',
                [link.revision.origin.value, link.revision.sequence.toInt()],
              )).single;
              _check(
                event['entity_kind'] == 'product' &&
                    event['entity_id'] == link.id.value,
                'productDependency',
              );
              saved = ProductDocumentCodec.decode(event['payload']! as String)
                  .product;
            }
            packages[link.revision] = saved;
            if (packages.length > 128) packages.remove(packages.keys.first);
            try {
              builder.add(
                ProductPurchase.fromReceipt(receipt, item.id),
                saved,
                member.branch,
              );
            } on ReceiptDataException catch (e) {
              if (e.field == 'comparison' && e.code == 'groupLimit')
                throw const StorageFailure('comparisonGroupLimit');
              rethrow;
            }
          }
        }
      }
      return ProductComparisonResult(anchor, members, builder.finish());
    }),
  );
}
