part of '../receipt_domain.dart';

// Identifies the exact bundled rules used by the parser's pinned dependency.
const receiptTimezoneRulesVersion = 'timezone-0.11.2/latest_all';

final class StoredReceiptDate {
  StoredReceiptDate._(
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.second,
    this.precision,
    this.utcInstantMs,
  );

  factory StoredReceiptDate.parse(String printedText) {
    final parsed = parseReceiptDate(printedText);
    _require(parsed.state == ReceiptDateState.valid, 'date', parsed.state.name);
    final date = parsed.printed!;
    return StoredReceiptDate._(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
      date.precision,
      parsed.utcInstant == null
          ? null
          : BigInt.from(parsed.utcInstant!.millisecondsSinceEpoch),
    );
  }

  final int year, month, day;
  final int? hour, minute, second;
  final DatePrecision precision;
  final BigInt? utcInstantMs;
  String get timezone => 'Europe/Helsinki';
}

/// Existing branch revision, or a pending explicitly named branch creation.
final class ReceiptBranch {
  ReceiptBranch({
    required this.id,
    required String name,
    this.revision,
    String? chain,
    String? address,
    String? printedIdentifier,
  }) : name = _text(name, 'branch.name'),
       chain = chain == null ? null : _text(chain, 'branch.chain'),
       address = address == null ? null : _text(address, 'branch.address'),
       printedIdentifier = printedIdentifier == null
           ? null
           : _text(printedIdentifier, 'branch.printedIdentifier');
  final DurableId id;
  final String name;
  final RevisionId? revision;
  final String? chain, address, printedIdentifier;
}

final class ReceiptProductLink {
  ReceiptProductLink({
    required this.id,
    required this.storeId,
    required this.revision,
  });
  final DurableId id, storeId;
  final RevisionId revision;
}

enum DiscountScope { item, receipt }

final class ReceiptItemSnapshot {
  ReceiptItemSnapshot({
    required this.id,
    required String name,
    required this.kind,
    required BigInt cents,
    String? rawName,
    this.quantityValue,
    this.quantityScale,
    this.quantityUnit,
    this.rateMicros,
    this.parentItemId,
    this.discountScope,
    this.product,
    String? adjustmentReason,
  }) : name = _text(name, 'row.name'),
       rawName = rawName == null ? null : _text(rawName, 'row.rawName'),
       cents = checkedInt64(cents, 'row.cents'),
       adjustmentReason = adjustmentReason == null
           ? null
           : _text(adjustmentReason, 'row.adjustmentReason') {
    final absent =
        quantityValue == null &&
        quantityScale == null &&
        quantityUnit == null &&
        rateMicros == null;
    if (!absent) {
      _require(
        quantityValue != null &&
            quantityScale != null &&
            quantityUnit != null &&
            quantityUnit != QuantityUnit.unknown &&
            rateMicros != null,
        'row.quantity',
        'incomplete',
      );
      checkedInt64(quantityValue!, 'row.quantityValue');
      checkedInt64(rateMicros!, 'row.rateMicros', nonnegative: true);
      _require(
        quantityValue != BigInt.zero &&
            quantityScale! >= 0 &&
            quantityScale! <= 6,
        'row.quantity',
        'invalid',
      );
      _require(
        extendedCents(
              Quantity(quantityValue!, quantityScale!, quantityUnit!),
              rateMicros!,
            ) ==
            cents,
        'row.quantity',
        'amountMismatch',
      );
    }
    _require(
      kind == LineKind.discount
          ? cents < BigInt.zero && discountScope != null
          : discountScope == null,
      'row.discount',
      'invalidScopeOrSign',
    );
    _require(
      kind != LineKind.discount ||
          (discountScope == DiscountScope.item
              ? parentItemId != null
              : parentItemId == null),
      'row.parent',
      'discountScope',
    );
    _require(
      parentItemId == null ||
          kind == LineKind.discount ||
          kind == LineKind.deposit,
      'row.parent',
      'unsupportedKind',
    );
    _require(parentItemId != id, 'row.parent', 'selfReference');
    _require(
      product == null || kind == LineKind.product,
      'row.product',
      'unsupportedKind',
    );
    _require(
      kind == LineKind.adjustment
          ? this.adjustmentReason != null
          : this.adjustmentReason == null,
      'row.adjustmentReason',
      'requiredOnlyForAdjustment',
    );
  }

  final DurableId id;
  final String name;
  final String? rawName, adjustmentReason;
  final LineKind kind;
  final BigInt cents;
  final BigInt? quantityValue, rateMicros;
  final int? quantityScale;
  final QuantityUnit? quantityUnit;
  final DurableId? parentItemId;
  final DiscountScope? discountScope;
  final ReceiptProductLink? product;
  String get normalizedName => normalizeReceiptNameV1(name);
}

/// Valid, reconciled data is still unreviewed. This type cannot authorize writes.
final class ReceiptSnapshot {
  ReceiptSnapshot({
    required this.id,
    required this.branch,
    required this.date,
    required BigInt totalCents,
    required Iterable<ReceiptItemSnapshot> items,
  }) : totalCents = checkedInt64(totalCents, 'totalCents'),
       items = List.unmodifiable(items) {
    _require(this.items.isNotEmpty, 'items', 'empty');
    final byId = {for (final item in this.items) item.id: item};
    _require(
      byId.length == this.items.length && !byId.containsKey(id),
      'items',
      'duplicateId',
    );
    for (final item in this.items) {
      if (item.parentItemId != null) {
        _require(
          byId[item.parentItemId]?.kind == LineKind.product,
          'row.parent',
          'missingOrNotProduct',
        );
      }
      _require(
        item.product == null || item.product!.storeId == branch.id,
        'row.product',
        'crossBranch',
      );
    }
    final sum = this.items.fold(BigInt.zero, (sum, item) => sum + item.cents);
    _require(sum == totalCents, 'totalCents', 'notReconciled');
  }

  final DurableId id;
  final ReceiptBranch branch;
  final StoredReceiptDate date;
  final BigInt totalCents;
  final List<ReceiptItemSnapshot> items;
  String get currency => 'EUR';
}
