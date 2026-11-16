import 'dart:convert';
import 'dart:io';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

import 'support.dart';

final rejectsData = throwsA(isA<ReceiptDataException>());

String golden(String name) =>
    File('test/fixtures/$name.json').readAsStringSync().trimRight();
Map<String, Object?> object(Object? value) => value as Map<String, Object?>;
List<Object?> list(Object? value) => value as List<Object?>;
String edited(String json, void Function(Map<String, Object?>) edit) {
  final fields = object(jsonDecode(json));
  edit(fields);
  return jsonEncode(fields);
}

void main() {
  test(
    'canonical snapshot and manual review bytes match independent fixtures',
    () {
      final snapshot = receipt();
      expect(ReceiptSnapshotCodec.encode(snapshot), golden('snapshot_v1'));
      expect(
        ReceiptSnapshotCodec.encode(
          ReceiptSnapshotCodec.decode(golden('snapshot_v1')),
        ),
        golden('snapshot_v1'),
      );
      final document = command(snapshot).document;
      expect(
        ReceiptDocumentCodec.encode(document),
        golden('manual_document_v1'),
      );
      // Computed independently from the committed UTF-8 fixture using .NET SHA256.
      const digest =
          'c80bbe1a529145702f193ac69147e1a198beeb800e6ccfa1eca09171400ff37b';
      expect(document.sha256Hex, digest);
      expect(
        ReceiptDocumentCodec.decode(golden('manual_document_v1')).sha256Hex,
        digest,
      );
    },
  );

  test('signed integer edges and values beyond double precision round trip exactly', () {
    for (final cents in [
      sqliteInt64Min,
      sqliteInt64Max,
      BigInt.parse('9007199254740993'),
    ]) {
      final snapshot = receipt(
        items: [row(cents: cents)],
        total: cents,
      );
      final decoded = ReceiptSnapshotCodec.decode(
        ReceiptSnapshotCodec.encode(snapshot),
      );
      expect(decoded.totalCents, cents);
      expect(decoded.items.single.cents, cents);
    }
  });

  test('all row structures, optional catalog fields and signed quantities round trip', () {
    final branch = ReceiptBranch(
      id: id(2),
      name: 'MÄNTY 🥛',
      revision: RevisionId(id(8), BigInt.one),
      chain: 'TEST',
      address: 'Test 1',
      printedIdentifier: '42',
    );
    final items = [
      row(
        name: 'MÄNTY "1 l"\nLAKTOOSITON',
        rawName: 'MÄNTY 1 l',
        cents: BigInt.from(-200),
        quantity: BigInt.from(-2000),
        scale: 3,
        unit: QuantityUnit.litre,
        rate: BigInt.from(1000000),
        product: ReceiptProductLink(
          id: id(6),
          storeId: branch.id,
          revision: RevisionId(id(8), BigInt.two),
        ),
      ),
      row(
        number: 4,
        kind: LineKind.deposit,
        parent: id(3),
        cents: BigInt.from(-15),
      ),
      row(
        number: 5,
        kind: LineKind.discount,
        scope: DiscountScope.item,
        parent: id(3),
        cents: BigInt.from(-10),
      ),
      row(
        number: 7,
        kind: LineKind.discount,
        scope: DiscountScope.receipt,
        cents: BigInt.from(-20),
      ),
      row(
        number: 9,
        kind: LineKind.adjustment,
        reason: 'Explicit rounding',
        cents: BigInt.one,
      ),
    ];
    final snapshot = receipt(
      branch: branch,
      date: '15.7.2026 12:34:56',
      items: items,
      total: BigInt.from(-244),
    );
    final encoded = ReceiptSnapshotCodec.encode(snapshot);
    final decoded = ReceiptSnapshotCodec.decode(encoded);
    expect(ReceiptSnapshotCodec.encode(decoded), encoded);
    expect(decoded.branch.address, 'Test 1');
    expect(decoded.items.first.rawName, 'MÄNTY 1 l');
    expect(decoded.items.first.quantityValue, BigInt.from(-2000));
    expect(decoded.items.first.product!.revision.sequence, BigInt.two);
    expect(decoded.items[2].discountScope, DiscountScope.item);
    expect(decoded.date.second, 56);
    final minute = receipt(date: '15.1.2026 12:34');
    expect(
      ReceiptSnapshotCodec.decode(ReceiptSnapshotCodec.encode(minute))
          .date
          .second,
      isNull,
    );
    for (final unit in [QuantityUnit.piece, QuantityUnit.kg]) {
      final measured = receipt(
        items: [
          row(
            quantity: BigInt.two,
            scale: 0,
            unit: unit,
            rate: BigInt.from(1000000),
          ),
        ],
      );
      expect(
        ReceiptSnapshotCodec.decode(ReceiptSnapshotCodec.encode(measured))
            .items
            .single
            .quantityUnit,
        unit,
      );
    }
  });

  test('malformed, unknown, noncanonical, oversized and lossy payloads are rejected', () {
    final baseline = golden('snapshot_v1');
    final mutations = <void Function(Map<String, Object?>)>[
      (m) => m['currency'] = 'USD',
      (m) => m['image'] = 'must not be retained',
      (m) => m.remove('currency'),
      (m) =>
          m['id'] = id(1).value
              .toUpperCase()
              .replaceFirst('00000000', 'AAAAAAAA'),
      (m) => m['total_cents'] = 200,
      (m) => m['total_cents'] = '0200',
      (m) => m['total_cents'] = '200.0',
      (m) => m['total_cents'] = '-0',
      (m) => m['total_cents'] = (sqliteInt64Max + BigInt.one).toString(),
      (m) => m['total_cents'] = '9' * 10000,
      (m) => m['total_cents'] = '201',
      (m) => object(list(m['items']).first)['cents'] = '1e2',
      (m) => object(list(m['items']).first)['position'] = '1',
      (m) => object(list(m['items']).first)['kind'] = 'fee',
      (m) => object(list(m['items']).first)['kind'] = 0,
      (m) => object(list(m['items']).first)['normalizer_version'] = '2',
      (m) => object(list(m['items']).first)['normalized_name'] = 'other',
      (m) => object(list(m['items']).first)['quantity'] = {
        'value': '1',
        'scale': '0',
        'unit': 'unknown',
      },
      (m) => object(list(m['items']).first)['name'] = 'unpaired\ud800',
      (m) => m['items'] = {},
      (m) => m['branch'] = [],
    ];
    for (final mutate in mutations) {
      expect(
        () => ReceiptSnapshotCodec.decode(edited(baseline, mutate)),
        rejectsData,
      );
    }
    for (final invalid in [
      'null',
      '[]',
      '{',
      '$baseline\n',
      ' $baseline',
      baseline.replaceFirst('{"id":', '{"id":"duplicate","id":'),
      '${' ' * (2 * 1024 * 1024)}$baseline',
    ]) {
      expect(() => ReceiptSnapshotCodec.decode(invalid), rejectsData);
    }
  });

  test('date fields must agree with precision, timezone and derived UTC', () {
    final baseline = ReceiptSnapshotCodec.encode(
      receipt(date: '15.1.2026 12:34'),
    );
    for (final mutate in <void Function(Map<String, Object?>)>[
      (d) => d['utc_instant_ms'] = null,
      (d) => d['utc_instant_ms'] = '0',
      (d) => d['timezone'] = 'UTC',
      (d) => d['precision'] = 'day',
      (d) => d['precision'] = 'second',
      (d) => d['precision'] = 'unknown',
      (d) => d['hour'] = null,
      (d) => d['second'] = '0',
      (d) => d['month'] = '2',
      (d) => d['hour'] = '24',
    ]) {
      expect(
        () => ReceiptSnapshotCodec.decode(
          edited(baseline, (m) => mutate(object(m['date']))),
        ),
        rejectsData,
      );
    }
    final day = golden('snapshot_v1');
    expect(
      () => ReceiptSnapshotCodec.decode(
        edited(day, (m) => object(m['date'])['utc_instant_ms'] = '0'),
      ),
      rejectsData,
    );
  });

  test('review metadata rejects unsupported policy, OCR assertions and incomplete review', () {
    final baseline = golden('manual_document_v1');
    expect(
      () => ReceiptDocumentCodec.decode(
        edited(baseline, (m) => m['payload_version'] = '2'),
      ),
      rejectsData,
    );
    for (final mutate in <void Function(Map<String, Object?>)>[
      (r) => r['policy_version'] = '2',
      (r) => r['source'] = 'ocr',
      (r) => r['timezone_rules_version'] = 'unknown',
      (r) => r['reviewed_at_ms'] = '-1',
      (r) => r['branch_reviewed'] = false,
      (r) => r['date_reviewed'] = false,
      (r) => r['total_reviewed'] = false,
      (r) => r['reconciled'] = false,
      (r) => r['reviewed_row_ids'] = [],
      (r) => r['reviewed_row_ids'] = [id(99).value],
      (r) => r['reviewed_row_ids'] = [id(3).value, id(3).value],
      (r) => r['expected_heads'] = [
        {'origin': id(8).value, 'sequence': '0'},
      ],
      (r) => r['notes'] = 'private temporary explanation',
    ]) {
      expect(
        () => ReceiptDocumentCodec.decode(
          edited(baseline, (m) => mutate(object(m['review']))),
        ),
        rejectsData,
      );
    }
    final snapshot = receipt();
    final heads = [
      RevisionId(id(9), BigInt.two),
      RevisionId(id(8), BigInt.one),
    ];
    final reviewed = ReviewedReceipt.manual(
      current: snapshot,
      expectedHeads: heads,
      confirmation: confirm(snapshot, heads: heads),
    );
    final encoded = ReceiptDocumentCodec.encode(reviewed.document);
    expect(
      ReceiptDocumentCodec.decode(encoded).review.expectedHeads.first.origin,
      id(8),
    );
    expect(
      () => ReceiptDocumentCodec.decode(
        edited(encoded, (m) {
          final r = object(m['review']);
          r['expected_heads'] = list(r['expected_heads']).reversed.toList();
        }),
      ),
      rejectsData,
    );
  });

  test('structured failures do not reveal receipt data', () {
    try {
      ReceiptSnapshotCodec.decode(
        edited(
          golden('snapshot_v1'),
          (m) => object(m['branch'])['name'] = ' SECRET BRANCH',
        ),
      );
      fail('Expected validation failure');
    } on ReceiptDataException catch (error) {
      expect(error.toString(), isNot(contains('SECRET')));
      expect(error.field, 'branch.name');
    }
  });
}
