import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

abstract interface class PurchaseHistoryService {
  Future<List<StoredProductPurchase>> purchases(
    DurableId storeId,
    DurableId productId, {
    int limit = 30,
    int offset = 0,
  });
}
