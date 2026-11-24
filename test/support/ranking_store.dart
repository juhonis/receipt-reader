import 'dart:async';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/spending_service.dart';
import 'package:receipt_reader/purchase_history_service.dart';

import 'fake_catalog_store.dart';

class RankingStore extends FakeCatalogStore
    implements SpendingDashboardService, PurchaseHistoryService {
  final queries = <SpendingDashboardQuery>[];
  final scopes =
      <
        ({
          DurableId branch,
          DurableId product,
          PurchaseDateRange? range,
          int offset,
        })
      >[];
  final otherBranches = <ReceiptBranch>[];
  Completer<void>? dashboardGate, productGate;
  bool failDashboard = false, failProduct = false;
  StoredProduct? productOverride;
  @override
  Future<List<ReceiptBranch>> branches() async => [branch, ...otherBranches];
  @override
  Future<StoredProduct?> readProduct(DurableId id) async {
    await productGate?.future;
    if (failProduct) throw const StorageFailure('database');
    return productOverride ?? await super.readProduct(id);
  }

  StoredProduct product({
    String name = 'SYNTHETIC PRODUCT',
    ReceiptBranch? at,
  }) {
    final selected = at ?? branch;
    final value = StoredProduct(
      ProductDocument(
        product: ProductSnapshot(
          id: DurableId.generate(),
          storeId: selected.id,
          canonicalName: name,
        ),
        storeRevision: selected.revision!,
        expectedHead: null,
        reviewedAtMs: BigInt.one,
        appVersion: 'ranking-widget',
      ),
      RevisionId(branch.revision!.origin, BigInt.from(sequence++)),
    );
    productRecords.add(value);
    return value;
  }

  Future<StoredReceipt> seed(
    List<(StoredProduct?, int)> values, {
    String date = '17.11.2026',
    ReceiptBranch? at,
  }) async {
    final rows = [
      for (final value in values)
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'PRINTED ALIAS',
          kind: LineKind.product,
          cents: BigInt.from(value.$2),
          product: value.$1?.link,
        ),
    ];
    final snapshot = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: at ?? branch,
      date: StoredReceiptDate.parse(date),
      totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
      items: rows,
    );
    await saveManual(
      ReviewedReceipt.manual(
        current: snapshot,
        expectedHeads: [],
        confirmation: ManualReviewChecks(
          snapshot: snapshot,
          expectedHeads: [],
          mutationId: DurableId.generate(),
          branchReviewed: true,
          dateReviewed: true,
          totalReviewed: true,
          reviewedRowIds: rows.map((r) => r.id),
        ).confirm(reviewedAtMs: BigInt.one, appVersion: 'ranking-widget'),
      ),
    );
    return documents.last;
  }

  @override
  Future<SpendingDashboard> spendingDashboard(
    SpendingDashboardQuery query,
  ) async {
    queries.add(query);
    await dashboardGate?.future;
    if (failDashboard) throw const StorageFailure('database');
    final builder = SpendingDashboardBuilder(query);
    for (final saved in documents) {
      builder.add(
        saved.document.snapshot,
        productCategories: categoryLabels,
        products: {
          for (final p in productRecords) p.link.id: p.document.product,
        },
      );
    }
    return builder.build();
  }

  List<StoredProductPurchase> _matches(
    DurableId storeId,
    DurableId productId,
    PurchaseDateRange? range,
  ) {
    final result = <StoredProductPurchase>[];
    for (final saved in documents) {
      final receipt = saved.document.snapshot;
      if (receipt.branch.id != storeId ||
          !(range?.contains(receipt.date) ?? true)) {
        continue;
      }
      for (final row in receipt.items) {
        if (row.product?.id == productId) {
          result.add(
            StoredProductPurchase(
              saved,
              ProductPurchase.fromReceipt(receipt, row.id),
            ),
          );
        }
      }
    }
    result.sort(
      (a, b) =>
          purchaseCalendarDay(b.purchase.date)
              .compareTo(purchaseCalendarDay(a.purchase.date)),
    );
    return result;
  }

  @override
  Future<List<StoredProductPurchase>> purchases(
    DurableId storeId,
    DurableId productId, {
    PurchaseDateRange? range,
    int limit = 30,
    int offset = 0,
  }) async =>
      _matches(storeId, productId, range).skip(offset).take(limit).toList();
  @override
  Future<PurchaseHistoryResult> purchaseHistory(
    DurableId storeId,
    DurableId productId, {
    PurchaseDateRange? range,
    int limit = 30,
    int offset = 0,
  }) async {
    scopes.add((
      branch: storeId,
      product: productId,
      range: range,
      offset: offset,
    ));
    final all = _matches(storeId, productId, range);
    final days = all.map((p) => purchaseCalendarDay(p.purchase.date)).toList()
      ..sort();
    final builder = PurchaseSummaryBuilder(
      storeId: storeId,
      productId: productId,
      firstDay: days.isEmpty
          ? null
          : range?.fromDate == null
          ? days.first
          : purchaseCalendarDay(range!.fromDate!),
      lastDay: days.isEmpty
          ? null
          : range?.throughDate == null
          ? days.last
          : purchaseCalendarDay(range!.throughDate!),
    );
    for (final item in all) {
      builder.add(item.purchase);
    }
    return PurchaseHistoryResult(
      builder.finish(),
      all.skip(offset).take(limit),
    );
  }
}
