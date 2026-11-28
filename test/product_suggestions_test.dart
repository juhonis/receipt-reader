import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/product_suggestions.dart';

import 'support/fake_catalog_store.dart';

class _PagedCatalog extends FakeCatalogStore {
  final offsets = <int>[];
  @override
  Future<List<StoredProduct>> products(
    DurableId storeId, {
    int limit = 30,
    int offset = 0,
    String query = '',
  }) async {
    offsets.add(offset);
    return super.products(storeId, limit: limit, offset: offset, query: query);
  }
}

void main() {
  test(
    'exact active alias leads, without collapsing equal-name identities',
    () async {
      final store = FakeCatalogStore();
      final aliasTarget = store.seedProduct(name: 'TEST DRINK');
      store.seedAlias(aliasTarget);
      final first = store.seedProduct(name: 'SYNTHETIC MILK');
      final duplicate = store.seedProduct(name: 'SYNTHETIC MILK');
      final results = await loadProductSuggestions(
        store,
        store.branch.id,
        ' Synthetic   MILK ',
      );
      expect(results.items.first.product.link.id, aliasTarget.link.id);
      expect(results.items.map((s) => s.reason), [
        ProductSuggestionReason.alias,
        ProductSuggestionReason.exactName,
        ProductSuggestionReason.exactName,
      ]);
      expect(results.items.map((s) => s.product.link.id).toSet(), {
        aliasTarget.link.id,
        first.link.id,
        duplicate.link.id,
      });
      expect(store.productWrites, isEmpty);
      expect(store.aliasWrites, isEmpty);
      expect(store.saved, isEmpty);
    },
  );

  test('small spelling errors and diacritics can suggest canonical names', () {
    final store = FakeCatalogStore();
    final target = store.seedProduct(name: 'TEST PÄHKINÄJUOMA 1L');
    final result = rankProductSuggestions(
      store.branch.id,
      'TEST PAHKINÄJUOMA 1L',
      [target],
    );
    expect(result.single.reason, ProductSuggestionReason.similarName);
    expect(result.single.distance, 1);
    expect(
      rankProductSuggestions(store.branch.id, 'TEST PAHKINAJUOMA 1L', [
        target,
      ]).single.distance,
      2,
    );
    expect(
      rankProductSuggestions(store.branch.id, 'TEST PAHKINAJUXMA 1L', [target]),
      isEmpty,
    );
    expect(
      rankProductSuggestions(store.branch.id, 'TEST PAHKINÄJU0MA 1L', [target]),
      isEmpty,
    );
    expect(
      rankProductSuggestions(store.branch.id, 'TEST PAHKINÄJUOMA 1 L', [
        target,
      ]),
      hasLength(1),
    );
  });

  test('numbers, short variant/unit tokens, word order and extra words are protected', () {
    final store = FakeCatalogStore();
    final target = store.seedProduct(name: 'TEST COCONUT DRINK 1L');
    for (final name in [
      'TEST COCONVT DRINK 2L',
      'TEST COCONVT DRINK 1KG',
      'TEST COCONVT DRINK 1.0L',
      'TEST COCONVT DRINK 1L BIO',
      'TEST DRINK COCONVT 1L',
      'COCONVT DRINK 1L',
    ]) {
      expect(
        rankProductSuggestions(store.branch.id, name, [target]),
        isEmpty,
        reason: name,
      );
    }
    final bio = store.seedProduct(name: 'TEST BIO COCONUT DRINK');
    expect(
      rankProductSuggestions(store.branch.id, 'TEST ECO COCONUT DRINK', [bio]),
      isEmpty,
    );
    expect(
      rankProductSuggestions(store.branch.id, 'TEST COCONVT DRINK 1L', [
        target,
      ]),
      hasLength(1),
    );
  });

  test(
    'short names, large edits, empty text and foreign branches do not suggest',
    () {
      final store = FakeCatalogStore(), other = FakeCatalogStore();
      final target = store.seedProduct(name: 'MILK');
      expect(
        rankProductSuggestions(store.branch.id, 'SILK', [target]),
        isEmpty,
      );
      expect(rankProductSuggestions(store.branch.id, '', [target]), isEmpty);
      expect(
        rankProductSuggestions(store.branch.id, 'MILK', [
          other.seedProduct(name: 'MILK'),
        ]),
        isEmpty,
      );
      final long = store.seedProduct(name: 'TEST COCONUT DRINK');
      expect(
        rankProductSuggestions(store.branch.id, 'TEST CHOCOLATE DRINK', [long]),
        isEmpty,
      );
      expect(
        rankProductSuggestions(store.branch.id, List.filled(300, 'A').join(), [
          long,
        ]),
        isEmpty,
      );
    },
  );

  test('disabled aliases cannot propose an unrelated canonical name', () {
    final store = FakeCatalogStore();
    final target = store.seedProduct(name: 'UNRELATED DRINK');
    store.seedAlias(target);
    final active = store.aliasRecords.single;
    final inactive = StoredProductAlias(
      ProductAliasDocument(
        alias: ProductAliasSnapshot(
          id: active.document.alias.id,
          storeId: store.branch.id,
          normalizedName: 'synthetic milk',
          productId: target.link.id,
          isActive: false,
        ),
        storeRevision: store.branch.revision!,
        productRevision: target.revision,
        expectedHead: active.revision,
        reviewedAtMs: BigInt.two,
        appVersion: 'test',
      ),
      RevisionId(store.branch.revision!.origin, BigInt.from(500)),
    );
    expect(
      rankProductSuggestions(store.branch.id, 'SYNTHETIC MILK', [
        target,
      ], alias: ProductAliasMatch(inactive, target)),
      isEmpty,
    );
  });

  test(
    'canonical-name suggestions include later pages and stay bounded',
    () async {
      final store = _PagedCatalog();
      for (var i = 0; i < 205; i++) {
        store.seedProduct(name: 'UNRELATED $i');
      }
      final match = store.seedProduct(name: 'TEST COCONUT DRINK');
      final result = await loadProductSuggestions(
        store,
        store.branch.id,
        'TEST COCONVT DRINK',
      );
      expect(store.offsets, [0, 200]);
      expect(result.items.single.product.link.id, match.link.id);
      expect(result.limited, isFalse);
    },
  );

  test(
    'exact aliases remain available beyond the bounded canonical scan',
    () async {
      final store = _PagedCatalog();
      final filler = store.seedProduct(name: 'UNRELATED DRINK');
      store.productRecords.addAll(List.filled(1999, filler));
      final target = store.seedProduct(name: 'TEST CORRECTED NAME');
      store.seedAlias(target);
      final result = await loadProductSuggestions(
        store,
        store.branch.id,
        'SYNTHETIC MILK',
      );
      expect(store.offsets.length, 10);
      expect(result.limited, isTrue);
      expect(result.items.single.product.link.id, target.link.id);
    },
  );

  test('ranking is stable, keeps at most five identities and never deduplicates names', () {
    final store = FakeCatalogStore();
    for (var i = 0; i < 8; i++) {
      store.seedProduct(name: 'TEST COCONUT DRINK');
    }
    final first = rankProductSuggestions(
      store.branch.id,
      'TEST COCONVT DRINK',
      store.productRecords,
    );
    final second = rankProductSuggestions(
      store.branch.id,
      'TEST COCONVT DRINK',
      store.productRecords.reversed,
    );
    expect(first, hasLength(5));
    expect(
      first.map((s) => s.product.link.id),
      second.map((s) => s.product.link.id),
    );
    expect(first.map((s) => s.product.link.id).toSet(), hasLength(5));
  });
}
