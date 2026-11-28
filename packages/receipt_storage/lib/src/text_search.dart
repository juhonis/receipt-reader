import 'package:receipt_domain/receipt_domain.dart';

/// Literal, case-insensitive partial words. Every word must occur in at least
/// one field; punctuation and Finnish diacritics retain their meaning.
final class TextSearchQuery {
  TextSearchQuery(String value)
    : terms = List.unmodifiable(
        value
            .toLowerCase()
            .split(RegExp(r'\s+', unicode: true))
            .where((s) => s.isNotEmpty),
      );

  final List<String> terms;
  bool get isEmpty => terms.isEmpty;

  bool matches(Iterable<String> fields) {
    if (isEmpty) return true;
    final text = fields.map((s) => s.toLowerCase()).toList();
    return terms.every((term) => text.any((field) => field.contains(term)));
  }

  bool matchesReceipt(ReceiptSnapshot receipt) =>
      matches([receipt.branch.name, ...receipt.items.map((item) => item.name)]);
}
