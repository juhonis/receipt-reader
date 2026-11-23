part of 'repository.dart';

extension ReceiptSpending on ReceiptRepository {
  Future<List<StoredReceipt>> _categoryHistory(
    String where,
    List<Object> args,
    ReceiptCategory category,
    int limit,
    int offset,
  ) async {
    final lookup = _CurrentProductCategories(this);
    final result = <StoredReceipt>[];
    var matched = 0;
    List<Object>? cursor;
    const dateKey =
        '(printed_year, printed_month, printed_day, COALESCE(printed_hour, -1), COALESCE(printed_minute, -1), COALESCE(printed_second, -1))';
    while (true) {
      final rows = await _rows(
        'SELECT id, printed_year AS y, printed_month AS m, printed_day AS d, '
        'COALESCE(printed_hour, -1) AS h, COALESCE(printed_minute, -1) AS n, COALESCE(printed_second, -1) AS s '
        'FROM receipts $where ${cursor == null ? '' : 'AND ($dateKey < (?, ?, ?, ?, ?, ?) OR ($dateKey = (?, ?, ?, ?, ?, ?) AND id > ?)) '} '
        'ORDER BY printed_year DESC, printed_month DESC, printed_day DESC, COALESCE(printed_hour, -1) DESC, '
        'COALESCE(printed_minute, -1) DESC, COALESCE(printed_second, -1) DESC, id ASC LIMIT 64',
        [
          ...args,
          if (cursor != null) ...[...cursor.take(6), ...cursor],
        ],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        cursor = [
          for (final key in ['y', 'm', 'd', 'h', 'n', 's', 'id']) row[key]!,
        ];
        final stored = (await _read(DurableId.parse(row['id']! as String)))!;
        final receipt = stored.document.snapshot;
        final categories = await lookup.forReceipt(receipt);
        if (!categorizeReceipt(
          receipt,
          categories,
        ).any((v) => v.category == category))
          continue;
        if (matched++ < offset) continue;
        result.add(stored);
        if (result.length == limit) return List.unmodifiable(result);
      }
    }
    return List.unmodifiable(result);
  }

  /// Trend and comparison folds share a single verified read snapshot.
  Future<SpendingDashboard> spendingDashboard(
    SpendingDashboardQuery query,
  ) => _guard(
    () => _db.transaction(() async {
      final builder = SpendingDashboardBuilder(query);
      final categoryLookup = _CurrentProductCategories(this);
      var cursor = '';
      final first = purchaseCalendarDate(query.scanFirstDay);
      final last = purchaseCalendarDate(query.selected.lastDay);
      while (true) {
        final batch = await _rows(
          'SELECT id FROM receipts WHERE is_deleted = 0 AND id > ? '
          'AND (printed_year, printed_month, printed_day) >= (?, ?, ?) '
          'AND (printed_year, printed_month, printed_day) <= (?, ?, ?) '
          '${query.branchId == null ? '' : 'AND store_id = ? '}ORDER BY id LIMIT 16',
          [
            cursor,
            first.year,
            first.month,
            first.day,
            last.year,
            last.month,
            last.day,
            if (query.branchId != null) query.branchId!.value,
          ],
        );
        if (batch.isEmpty) break;
        for (final row in batch) {
          cursor = row['id']! as String;
          final receipt = (await _read(DurableId.parse(cursor)))!
              .document
              .snapshot;
          try {
            builder.add(
              receipt,
              productCategories:
                  query.selected.contains(purchaseCalendarDay(receipt.date))
                  ? await categoryLookup.forReceipt(receipt)
                  : const {},
            );
          } on ReceiptDataException catch (error) {
            if (error.code == 'groupLimit')
              throw const StorageFailure('spendingGroupLimit');
            if (error.code == 'categoryGroupLimit')
              throw const StorageFailure('categoryGroupLimit');
            rethrow;
          }
        }
      }
      return builder.build();
    }),
  );

  /// Complete selected receipts in one read transaction, with bounded memory.
  Future<SpendingSummary> spendingSummary({HistoryFilter? filter}) => _guard(
    () => _db.transaction(() async {
      final builder = SpendingSummaryBuilder();
      final categoryLookup = filter?.category == null
          ? null
          : _CurrentProductCategories(this);
      var cursor = '';
      final conditions = <String>['is_deleted = 0', 'id > ?'];
      final args = <Object>[];
      if (filter?.branchId case final id?) {
        conditions.add('store_id = ?');
        args.add(id.value);
      }
      for (final bound in [
        (filter?.fromDate, '>='),
        (filter?.throughDate, '<='),
      ]) {
        if (bound.$1 case final date?) {
          conditions.add(
            '(printed_year, printed_month, printed_day) ${bound.$2} (?, ?, ?)',
          );
          args.addAll([date.year, date.month, date.day]);
        }
      }
      for (final bound in [
        (filter?.minTotalCents, '>='),
        (filter?.maxTotalCents, '<='),
      ]) {
        if (bound.$1 case final amount?) {
          conditions.add('total_amount_cents ${bound.$2} ?');
          args.add(amount.toInt());
        }
      }
      while (true) {
        final batch = await _rows(
          'SELECT id FROM receipts WHERE ${conditions.join(' AND ')} ORDER BY id LIMIT 16',
          [cursor, ...args],
        );
        if (batch.isEmpty) break;
        for (final row in batch) {
          cursor = row['id']! as String;
          final receipt = (await _read(DurableId.parse(cursor)))!;
          if (filter?.category case final category?) {
            final categories = await categoryLookup!.forReceipt(
              receipt.document.snapshot,
            );
            if (!categorizeReceipt(
              receipt.document.snapshot,
              categories,
            ).any((value) => value.category == category)) {
              continue;
            }
          }
          try {
            builder.add(receipt.document.snapshot);
          } on ReceiptDataException catch (error) {
            if (error.code == 'groupLimit')
              throw const StorageFailure('spendingGroupLimit');
            rethrow;
          }
        }
      }
      return builder.build();
    }),
  );
}

/// Bounded current-product metadata, resolved in the caller's read transaction.
/// The canonical product event is authoritative; no new SQL projection is needed.
final class _CurrentProductCategories {
  _CurrentProductCategories(this.repository);
  final ReceiptRepository repository;
  final _cache =
      LinkedHashMap<DurableId, ({DurableId store, String? category})>();
  Future<Map<DurableId, String?>> forReceipt(ReceiptSnapshot receipt) async {
    final result = <DurableId, String?>{};
    for (final row in receipt.items) {
      final link = row.product;
      if (link == null || result.containsKey(link.id)) continue;
      var value = _cache.remove(link.id);
      if (value == null) {
        final product = (await repository._product(link.id)).document.product;
        value = (store: product.storeId, category: product.category);
      }
      _check(value.store == receipt.branch.id, 'crossStoreProduct');
      _cache[link.id] = value;
      if (_cache.length > 128) _cache.remove(_cache.keys.first);
      result[link.id] = value.category;
    }
    return result;
  }
}
