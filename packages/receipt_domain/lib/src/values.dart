part of '../receipt_domain.dart';

final sqliteInt64Min = BigInt.parse('-9223372036854775808');
final sqliteInt64Max = BigInt.parse('9223372036854775807');

/// Field/code only: errors must not expose receipt contents in diagnostics.
final class ReceiptDataException implements Exception {
  const ReceiptDataException(this.field, this.code);
  final String field, code;
  @override
  String toString() => 'ReceiptDataException($field, $code)';
}

void _require(bool condition, String field, String code) {
  if (!condition) throw ReceiptDataException(field, code);
}

BigInt checkedInt64(BigInt value, String field, {bool nonnegative = false}) {
  _require(
    value >= (nonnegative ? BigInt.zero : sqliteInt64Min) &&
        value <= sqliteInt64Max,
    field,
    'integerRange',
  );
  return value;
}

String _text(String value, String field) {
  _require(
    value.isNotEmpty && value == value.trim(),
    field,
    'blankOrUntrimmed',
  );
  // Dart strings can contain unpaired UTF-16 surrogates. Do not let UTF-8
  // replacement characters make two different approved strings hash alike.
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      _require(
        i + 1 < value.length &&
            value.codeUnitAt(i + 1) >= 0xdc00 &&
            value.codeUnitAt(i + 1) <= 0xdfff,
        field,
        'invalidUnicode',
      );
      i++;
    } else {
      _require(unit < 0xdc00 || unit > 0xdfff, field, 'invalidUnicode');
    }
  }
  return value;
}

/// Conservative v1 key: trim, collapse Dart Unicode whitespace, lowercase.
/// Preserve diacritics, punctuation, sizes and variants; no fuzzy matching.
String normalizeReceiptNameV1(String value) => _text(
  value.trim(),
  'name',
).replaceAll(RegExp(r'\s+', unicode: true), ' ').toLowerCase();

final class DurableId implements Comparable<DurableId> {
  DurableId.parse(this.value) {
    _require(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value),
      'id',
      'uuidV4',
    );
  }

  factory DurableId.generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return DurableId.parse(
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}',
    );
  }

  final String value;
  @override
  int compareTo(DurableId other) => value.compareTo(other.value);
  @override
  bool operator ==(Object other) => other is DurableId && value == other.value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

final class RevisionId implements Comparable<RevisionId> {
  RevisionId(this.origin, this.sequence) {
    _require(
      sequence > BigInt.zero && sequence < sqliteInt64Max,
      'revision.sequence',
      'sequenceRange',
    );
  }
  final DurableId origin;
  final BigInt sequence;
  @override
  int compareTo(RevisionId other) {
    final byOrigin = origin.compareTo(other.origin);
    return byOrigin == 0 ? sequence.compareTo(other.sequence) : byOrigin;
  }

  @override
  bool operator ==(Object other) =>
      other is RevisionId &&
      origin == other.origin &&
      sequence == other.sequence;
  @override
  int get hashCode => Object.hash(origin, sequence);
}

/// Session-owned mapping. Equal-but-distinct review objects are distinct rows.
/// Never forget removed rows: IDs cannot be recycled within this session.
final class ReviewRowIds {
  ReviewRowIds();
  final Map<Object, DurableId> _ids = Map.identity();
  final Set<DurableId> _used = {};

  void retain(Object row, DurableId id) {
    final previous = _ids[row];
    _require(previous == null || previous == id, 'row.id', 'identityChanged');
    _require(previous == id || !_used.contains(id), 'row.id', 'identityReused');
    _ids[row] = id;
    _used.add(id);
  }

  DurableId idFor(Object row) {
    final previous = _ids[row];
    if (previous != null) return previous;
    DurableId id;
    do {
      id = DurableId.generate();
    } while (_used.contains(id));
    retain(row, id);
    return id;
  }
}

List<RevisionId> _heads(Iterable<RevisionId> values) {
  final result = values.toList()..sort();
  _require(
    result.toSet().length == result.length,
    'expectedHeads',
    'duplicate',
  );
  return List.unmodifiable(result);
}
