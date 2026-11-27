import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';

import 'catalog_service.dart';

enum ProductSuggestionReason { alias, exactName, similarName }

class ProductNameSuggestion {
  const ProductNameSuggestion(this.product, this.reason, this.distance);
  final StoredProduct product;
  final ProductSuggestionReason reason;
  final int distance;
}

class ProductSuggestions {
  ProductSuggestions(
    Iterable<ProductNameSuggestion> items, {
    this.limited = false,
  }) : items = List.unmodifiable(items);
  final List<ProductNameSuggestion> items;
  final bool limited;
}

/// Read only, on request. An exact active alias is checked independently of the
/// bounded canonical-name scan, including products beyond that scan's limit.
Future<ProductSuggestions> loadProductSuggestions(
  CatalogService service,
  DurableId branchId,
  String receiptName,
) async {
  if (receiptName.trim().isEmpty) return ProductSuggestions(const []);
  final alias = await service.matchAlias(branchId, receiptName);
  final products = <StoredProduct>[];
  var limited = false;
  for (var offset = 0; offset < 2000; offset += 200) {
    final page = await service.products(branchId, limit: 200, offset: offset);
    products.addAll(page);
    if (page.length < 200) break;
    limited = offset == 1800;
  }
  return ProductSuggestions(
    rankProductSuggestions(branchId, receiptName, products, alias: alias),
    limited: limited,
  );
}

/// Suggestions never establish product identity. Equal-name identities remain
/// separate choices, and a receipt name cannot select a product automatically.
List<ProductNameSuggestion> rankProductSuggestions(
  DurableId branchId,
  String receiptName,
  Iterable<StoredProduct> products, {
  ProductAliasMatch? alias,
}) {
  if (receiptName.trim().isEmpty) return const [];
  final name = normalizeReceiptNameV1(receiptName);
  final matches = <DurableId, ProductNameSuggestion>{};
  if (alias != null &&
      alias.alias.document.alias.isActive &&
      alias.alias.document.alias.storeId == branchId &&
      alias.alias.document.alias.normalizedName == name &&
      alias.alias.document.alias.productId ==
          alias.product.document.product.id &&
      alias.product.document.product.storeId == branchId) {
    matches[alias.product.document.product.id] = ProductNameSuggestion(
      alias.product,
      ProductSuggestionReason.alias,
      0,
    );
  }
  for (final product in products) {
    final p = product.document.product;
    if (p.storeId != branchId || matches.containsKey(p.id)) continue;
    final canonical = normalizeReceiptNameV1(p.canonicalName);
    if (canonical == name) {
      matches[p.id] = ProductNameSuggestion(
        product,
        ProductSuggestionReason.exactName,
        0,
      );
    } else if (_spellingDistance(name, canonical) case final distance?) {
      matches[p.id] = ProductNameSuggestion(
        product,
        ProductSuggestionReason.similarName,
        distance,
      );
    }
  }
  final ranked = matches.values.toList()
    ..sort((a, b) {
      var order = a.reason.index.compareTo(b.reason.index);
      if (order != 0) return order;
      order = a.distance.compareTo(b.distance);
      if (order != 0) return order;
      order = a.product.document.product.canonicalName.compareTo(
        b.product.document.product.canonicalName,
      );
      return order != 0
          ? order
          : a.product.document.product.id.compareTo(
              b.product.document.product.id,
            );
    });
  return List.unmodifiable(ranked.take(5));
}

final _letters = RegExp(r'^[a-zà-öø-ÿ]+$');
final _tokens = RegExp(r'[a-zà-öø-ÿ]+|[0-9]+(?:[,.][0-9]+)?|[^\s]');

int? _spellingDistance(String a, String b) {
  // Bound work on OCR/catalog text; exact names and aliases above remain usable.
  if (a.length > 256 || b.length > 256) return null;
  List<String> tokens(String text) => _tokens
      .allMatches(text)
      .map((m) => m[0]!)
      .where((t) => t != '.' && t != ',' && t != '-')
      .toList();
  final left = tokens(a), right = tokens(b);
  if (left.length != right.length) return null;
  final letters = left.where((t) => _letters.hasMatch(t)).join().length;
  if (letters < 6) return null;
  final budget = letters < 12 ? 1 : 2;
  var distance = 0;
  for (var i = 0; i < left.length; i++) {
    if (left[i] == right[i]) continue;
    // Preserve numbers, units/symbols and short variant tokens. Do not infer
    // package equivalence, drop words or reorder descriptions.
    if (!_letters.hasMatch(left[i]) ||
        !_letters.hasMatch(right[i]) ||
        left[i].length <= 3 ||
        right[i].length <= 3) {
      return null;
    }
    distance += _editDistance(left[i], right[i], budget - distance);
    if (distance > budget) return null;
  }
  return distance;
}

int _editDistance(String a, String b, int budget) {
  if ((a.length - b.length).abs() > budget) return budget + 1;
  final outside = budget + 1;
  var previous = List.generate(b.length + 1, (i) => i <= budget ? i : outside);
  for (var i = 1; i <= a.length; i++) {
    final current = List.filled(b.length + 1, outside)
      ..[0] = i <= budget ? i : outside;
    var minimum = current[0];
    final start = i - budget > 1 ? i - budget : 1;
    final end = i + budget < b.length ? i + budget : b.length;
    for (var j = start; j <= end; j++) {
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final gap = deletion < insertion ? deletion : insertion;
      current[j] = gap < substitution ? gap : substitution;
      if (current[j] < minimum) minimum = current[j];
    }
    if (minimum > budget) return budget + 1;
    previous = current;
  }
  return previous.last;
}
