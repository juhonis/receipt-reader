part of 'repository.dart';

extension ReceiptSpending on ReceiptRepository {
  /// Trend and comparison folds share a single verified read snapshot.
  Future<SpendingDashboard> spendingDashboard(
    SpendingDashboardQuery query,
  ) => _guard(
    () => _db.transaction(() async {
      final builder = SpendingDashboardBuilder(query);
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
          builder.add(
            (await _read(DurableId.parse(cursor)))!.document.snapshot,
          );
        }
      }
      return builder.build();
    }),
  );

  /// Complete selected receipts in one read transaction, with bounded memory.
  Future<SpendingSummary> spendingSummary({HistoryFilter? filter}) => _guard(
    () => _db.transaction(() async {
      final builder = SpendingSummaryBuilder();
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
