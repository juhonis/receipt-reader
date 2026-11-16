import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

final rejectsData = throwsA(isA<ReceiptDataException>());

void main() {
  test('UUIDs and event sequences are canonical and bounded', () {
    final generated = List.generate(100, (_) => DurableId.generate());
    expect(generated.toSet(), hasLength(100));
    for (final value in generated) {
      expect(DurableId.parse(value.value), value);
    }
    for (final value in [
      'invalid',
      id(1).value.toUpperCase().replaceFirst('00000000', 'AAAAAAAA'),
      id(1).value.replaceFirst('-4000-', '-1000-'),
      id(1).value.replaceFirst('-8000-', '-7000-'),
      '${id(1)}\n',
    ]) {
      expect(() => DurableId.parse(value), rejectsData);
    }
    expect(RevisionId(id(1), BigInt.one), RevisionId(id(1), BigInt.one));
    RevisionId(id(1), sqliteInt64Max - BigInt.one);
    for (final value in [
      BigInt.zero,
      -BigInt.one,
      sqliteInt64Max,
      sqliteInt64Max + BigInt.one,
    ]) {
      expect(() => RevisionId(id(1), value), rejectsData);
    }
  });

  test('row mapping preserves identity and cannot reassign or recycle IDs', () {
    final map = ReviewRowIds();
    final first = Object(), second = Object();
    map.retain(first, id(3));
    expect(map.idFor(first), id(3));
    map.retain(first, id(3));
    expect(() => map.retain(first, id(4)), rejectsData);
    expect(() => map.retain(second, id(3)), rejectsData);
    final secondId = map.idFor(second);
    expect(map.idFor(second), secondId);
    expect(secondId, isNot(id(3)));
    final equalA = _EqualRow(), equalB = _EqualRow();
    expect(equalA, equalB);
    expect(map.idFor(equalA), isNot(map.idFor(equalB)));
  });

  test('signed limits and sums use BigInt without intermediate overflow', () {
    for (final value in [sqliteInt64Min, sqliteInt64Max]) {
      expect(
        receipt(
          items: [row(cents: value)],
          total: value,
        ).totalCents,
        value,
      );
    }
    for (final value in [
      sqliteInt64Min - BigInt.one,
      sqliteInt64Max + BigInt.one,
    ]) {
      expect(() => row(cents: value), rejectsData);
      expect(() => receipt(total: value), rejectsData);
    }
    final large = receipt(
      items: [
        row(cents: sqliteInt64Max),
        row(number: 4, cents: sqliteInt64Max),
        row(number: 5, cents: -sqliteInt64Max),
      ],
      total: sqliteInt64Max,
    );
    expect(large.totalCents, sqliteInt64Max);
    expect(() => receipt(total: BigInt.from(201)), rejectsData);
    expect(() => receipt(items: [], total: BigInt.zero), rejectsData);
  });

  test(
    'quantity groups reject partial, unknown, zero, overflow and mismatches',
    () {
      expect(row().quantityValue, isNull);
      for (final make in <ReceiptItemSnapshot Function()>[
        () => row(quantity: BigInt.one),
        () => row(rate: BigInt.one),
        () => row(unit: QuantityUnit.unknown),
        () => row(
          quantity: BigInt.one,
          scale: 0,
          unit: QuantityUnit.unknown,
          rate: BigInt.from(2000000),
        ),
        () => row(
          quantity: BigInt.zero,
          scale: 0,
          unit: QuantityUnit.piece,
          rate: BigInt.zero,
        ),
        () => row(
          quantity: BigInt.one,
          scale: -1,
          unit: QuantityUnit.piece,
          rate: BigInt.one,
        ),
        () => row(
          quantity: BigInt.one,
          scale: 7,
          unit: QuantityUnit.piece,
          rate: BigInt.one,
        ),
        () => row(
          quantity: sqliteInt64Max + BigInt.one,
          scale: 0,
          unit: QuantityUnit.piece,
          rate: BigInt.zero,
        ),
        () => row(
          quantity: BigInt.one,
          scale: 0,
          unit: QuantityUnit.piece,
          rate: sqliteInt64Max + BigInt.one,
        ),
        () => row(
          quantity: BigInt.one,
          scale: 0,
          unit: QuantityUnit.piece,
          rate: -BigInt.one,
        ),
        () => row(
          quantity: BigInt.one,
          scale: 0,
          unit: QuantityUnit.piece,
          rate: BigInt.one,
        ),
      ]) {
        expect(make, rejectsData);
      }
      expect(
        row(
          quantity: BigInt.from(2),
          scale: 0,
          unit: QuantityUnit.piece,
          rate: BigInt.from(1000000),
        ).quantityValue,
        BigInt.two,
      );
      // 0.5 kg * EUR 0.01/kg rounds exactly once, including returns.
      for (final sign in [1, -1]) {
        final weighed = row(
          cents: BigInt.from(sign),
          quantity: BigInt.from(sign * 5),
          scale: 1,
          unit: QuantityUnit.kg,
          rate: BigInt.from(10000),
        );
        expect(weighed.cents, BigInt.from(sign));
      }
    },
  );

  test(
    'typed financial links, adjustments and branch ownership are checked',
    () {
      final product = row();
      final discount = row(
        number: 4,
        kind: LineKind.discount,
        cents: BigInt.from(-50),
        scope: DiscountScope.item,
        parent: product.id,
      );
      final deposit = row(
        number: 5,
        kind: LineKind.deposit,
        cents: BigInt.from(15),
        parent: product.id,
      );
      receipt(items: [product, discount, deposit], total: BigInt.from(165));
      receipt(
        items: [
          product,
          row(
            number: 4,
            kind: LineKind.discount,
            cents: BigInt.from(-50),
            scope: DiscountScope.receipt,
          ),
        ],
        total: BigInt.from(150),
      );
      for (final make in <Object Function()>[
        () => row(kind: LineKind.discount, scope: DiscountScope.receipt),
        () => row(kind: LineKind.discount, cents: BigInt.from(-1)),
        () => row(
          kind: LineKind.discount,
          cents: BigInt.from(-1),
          scope: DiscountScope.item,
        ),
        () => row(
          kind: LineKind.discount,
          cents: BigInt.from(-1),
          scope: DiscountScope.receipt,
          parent: id(7),
        ),
        () => row(parent: id(7)),
        () => row(kind: LineKind.deposit, parent: id(3)),
        () => receipt(items: [discount], total: discount.cents),
        () => receipt(items: [row(), row()], total: BigInt.from(400)),
        () => receipt(items: [row(number: 1)]),
        () => receipt(
          items: [
            row(number: 3, kind: LineKind.deposit),
            discount,
          ],
          total: BigInt.from(150),
        ),
        () => row(kind: LineKind.adjustment),
        () => row(reason: 'Rounding'),
        () => row(kind: LineKind.adjustment, reason: ' '),
        () => row(
          kind: LineKind.deposit,
          product: ReceiptProductLink(
            id: id(6),
            storeId: id(2),
            revision: RevisionId(id(8), BigInt.one),
          ),
        ),
        () => receipt(
          items: [
            row(
              product: ReceiptProductLink(
                id: id(6),
                storeId: id(9),
                revision: RevisionId(id(8), BigInt.one),
              ),
            ),
          ],
        ),
      ]) {
        expect(make, rejectsData);
      }
      row(kind: LineKind.adjustment, reason: 'User confirmed rounding');
      receipt(
        items: [
          row(
            product: ReceiptProductLink(
              id: id(6),
              storeId: id(2),
              revision: RevisionId(id(8), BigInt.one),
            ),
          ),
        ],
      );
    },
  );

  test(
    'civil dates retain precision and never choose a DST instant silently',
    () {
      final day = StoredReceiptDate.parse('29.2.2024');
      expect(day.hour, isNull);
      expect(day.utcInstantMs, isNull);
      expect(day.precision, DatePrecision.day);
      final minute = StoredReceiptDate.parse('15.1.2026 12:34');
      expect(minute.second, isNull);
      expect(
        minute.utcInstantMs,
        BigInt.from(DateTime.utc(2026, 1, 15, 10, 34).millisecondsSinceEpoch),
      );
      expect(
        StoredReceiptDate.parse('15.7.2026 12:34:56').precision,
        DatePrecision.second,
      );
      for (final text in [
        '29.2.2025',
        '29.3.2026 03:30',
        '25.10.2026 03:30',
        '15.7.2099 12:00',
      ]) {
        expect(() => StoredReceiptDate.parse(text), rejectsData);
      }
    },
  );

  test(
    'immutable names preserve Finnish variants and meaningful package sizes',
    () {
      final rows = [row(name: 'MÄNTY  1,5 l')];
      final snapshot = receipt(items: rows);
      rows.clear();
      expect(snapshot.items.single.normalizedName, 'mänty 1,5 l');
      expect(normalizeReceiptNameV1('  MÄNTY\u00a01,5 l  '), 'mänty 1,5 l');
      expect(
        normalizeReceiptNameV1('MÄNTY 1,5 l'),
        isNot(normalizeReceiptNameV1('MÄNTY 1 l')),
      );
      expect(() => snapshot.items.clear(), throwsUnsupportedError);
      for (final name in ['', ' ', ' untrimmed', 'bad\ud800', 'bad\udc00']) {
        expect(() => row(name: name), rejectsData);
      }
      row(name: 'Maito 🥛');
    },
  );
}

class _EqualRow {
  @override
  bool operator ==(Object other) => other is _EqualRow;
  @override
  int get hashCode => 1;
}
