import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/catalog_service.dart';

import 'fake_store.dart';

class FakeCatalogStore extends FakeStore implements CatalogService {
  final productRecords = <StoredProduct>[];
  final aliasRecords = <StoredProductAlias>[];
  final productWrites = <(ProductDocument, DurableId)>[];
  final aliasWrites = <(ProductAliasDocument, DurableId)>[];
  final results = <DurableId, SaveResult>{};
  String? catalogFailure;
  bool uncertain = false;
  int sequence = 100;
  @override
  Future<List<StoredProduct>> products(
    DurableId storeId, {
    int limit = 30,
    int offset = 0,
  }) async => productRecords
      .where((p) => p.document.product.storeId == storeId)
      .skip(offset)
      .take(limit)
      .toList();
  @override
  Future<List<StoredProductAlias>> aliases(
    DurableId storeId, {
    bool activeOnly = false,
    int limit = 30,
    int offset = 0,
  }) async => aliasRecords
      .where(
        (a) =>
            a.document.alias.storeId == storeId &&
            (!activeOnly || a.document.alias.isActive),
      )
      .skip(offset)
      .take(limit)
      .toList();
  @override
  Future<StoredProduct?> readProduct(DurableId id) async =>
      productRecords.where((p) => p.document.product.id == id).firstOrNull;
  @override
  Future<StoredProductAlias?> readAlias(DurableId id) async =>
      aliasRecords.where((a) => a.document.alias.id == id).firstOrNull;
  @override
  Future<ProductAliasMatch?> matchAlias(DurableId storeId, String name) async {
    final a = aliasRecords
        .where(
          (a) =>
              a.document.alias.storeId == storeId &&
              a.document.alias.isActive &&
              a.document.alias.normalizedName == normalizeReceiptNameV1(name),
        )
        .firstOrNull;
    if (a == null) return null;
    return ProductAliasMatch(
      a,
      (await readProduct(a.document.alias.productId))!,
    );
  }

  @override
  Future<SaveResult> saveProduct(
    ProductDocument document, {
    required DurableId mutationId,
  }) async {
    productWrites.add((document, mutationId));
    if (catalogFailure != null) throw StorageFailure(catalogFailure!);
    if (results[mutationId] case final result?) {
      return SaveResult(result.revision, replayed: true);
    }
    final result = SaveResult(
      RevisionId(branch.revision!.origin, BigInt.from(sequence++)),
      replayed: false,
    );
    results[mutationId] = result;
    productRecords.removeWhere(
      (p) => p.document.product.id == document.product.id,
    );
    productRecords.add(StoredProduct(document, result.revision));
    if (uncertain) throw const StorageFailure('database');
    return result;
  }

  @override
  Future<SaveResult> saveAlias(
    ProductAliasDocument document, {
    required DurableId mutationId,
  }) async {
    aliasWrites.add((document, mutationId));
    if (catalogFailure != null) throw StorageFailure(catalogFailure!);
    if (results[mutationId] case final result?) {
      return SaveResult(result.revision, replayed: true);
    }
    final result = SaveResult(
      RevisionId(branch.revision!.origin, BigInt.from(sequence++)),
      replayed: false,
    );
    results[mutationId] = result;
    aliasRecords.removeWhere((a) => a.document.alias.id == document.alias.id);
    aliasRecords.add(StoredProductAlias(document, result.revision));
    if (uncertain) throw const StorageFailure('database');
    return result;
  }

  StoredProduct seedProduct({String name = 'SYNTHETIC MILK'}) {
    final p = StoredProduct(
      ProductDocument(
        product: ProductSnapshot(
          id: DurableId.generate(),
          storeId: branch.id,
          canonicalName: name,
        ),
        storeRevision: branch.revision!,
        expectedHead: null,
        reviewedAtMs: BigInt.one,
        appVersion: 'widget-test',
      ),
      RevisionId(branch.revision!.origin, BigInt.from(sequence++)),
    );
    productRecords.add(p);
    return p;
  }

  void seedAlias(StoredProduct p) {
    aliasRecords.add(
      StoredProductAlias(
        ProductAliasDocument(
          alias: ProductAliasSnapshot(
            id: DurableId.generate(),
            storeId: branch.id,
            normalizedName: 'synthetic milk',
            productId: p.document.product.id,
            isActive: true,
          ),
          storeRevision: branch.revision!,
          productRevision: p.revision,
          expectedHead: null,
          reviewedAtMs: BigInt.one,
          appVersion: 'widget-test',
        ),
        RevisionId(branch.revision!.origin, BigInt.from(sequence++)),
      ),
    );
  }
}
