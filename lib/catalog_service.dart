import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

/// Catalog calls share the same dataset queue as receipt saves and restores.
abstract interface class CatalogService {
  Future<List<StoredProduct>> products(
    DurableId storeId, {
    int limit = 30,
    int offset = 0,
  });
  Future<List<StoredProductAlias>> aliases(
    DurableId storeId, {
    bool activeOnly = false,
    int limit = 30,
    int offset = 0,
  });
  Future<StoredProduct?> readProduct(DurableId id);
  Future<StoredProductAlias?> readAlias(DurableId id);
  Future<ProductAliasMatch?> matchAlias(DurableId storeId, String name);
  Future<SaveResult> saveProduct(
    ProductDocument document, {
    required DurableId mutationId,
  });
  Future<SaveResult> saveAlias(
    ProductAliasDocument document, {
    required DurableId mutationId,
  });
}
