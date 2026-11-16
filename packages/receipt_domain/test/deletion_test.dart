import 'dart:convert';
import 'dart:io';

import 'package:receipt_domain/receipt_domain.dart';
import 'package:test/test.dart';

import 'support.dart' show id;

void main() {
  ReceiptDocument document(String source) => ReceiptDocumentCodec.decode(
    File(
      'test/fixtures/${source == 'manual' ? 'manual' : 'ocr'}_document_v1.json',
    ).readAsStringSync().trim(),
  );
  final head = RevisionId(id(8), BigInt.from(9));
  ReceiptDeletionChecks checks(String source, {bool reviewed = true}) =>
      ReceiptDeletionChecks(
        document: document(source),
        expectedHead: head,
        mutationId: id(99),
        receiptReviewed: reviewed,
      );
  for (final source in ['manual', 'ocr']) {
    test(
      '$source deletion binds the displayed document and head without retaining receipt text',
      () {
        final command = checks(source).confirm(
          deletedAtMs: BigInt.from(123456),
          appVersion: 'deletion-test',
        );
        final tombstone = command.tombstone;
        expect(command.mutationId, id(99));
        expect(tombstone.receiptId, document(source).snapshot.id);
        expect(tombstone.expectedHead, head);
        expect(tombstone.documentSha256, document(source).sha256Hex);
        expect(tombstone.source, source);
        final encoded = ReceiptTombstoneCodec.encode(tombstone);
        expect(
          ReceiptTombstoneCodec.encode(ReceiptTombstoneCodec.decode(encoded)),
          encoded,
        );
        expect(encoded, isNot(contains(document(source).snapshot.branch.name)));
        if (source == 'manual') {
          expect(
            encoded,
            File('test/fixtures/tombstone_v1.json').readAsStringSync().trim(),
          );
        }
      },
    );
  }
  test(
    'deletion requires fresh explicit confirmation and bounded audit fields',
    () {
      expect(
        () => checks(
          'manual',
          reviewed: false,
        ).confirm(deletedAtMs: BigInt.one, appVersion: 'test'),
        throwsA(isA<ReceiptDataException>()),
      );
      for (final at in [-BigInt.one, sqliteInt64Max + BigInt.one]) {
        expect(
          () => checks('manual').confirm(deletedAtMs: at, appVersion: 'test'),
          throwsA(isA<ReceiptDataException>()),
        );
      }
      expect(
        () =>
            checks('manual').confirm(deletedAtMs: BigInt.one, appVersion: ' '),
        throwsA(isA<ReceiptDataException>()),
      );
    },
  );
  test('tombstone decoder rejects unknown policy, unchecked data and malformed canonical values', () {
    final golden = File('test/fixtures/tombstone_v1.json')
        .readAsStringSync()
        .trim();
    for (final patch in <String, Object?>{
      'payload_version': '2',
      'deletion_policy_version': '2',
      'receipt_reviewed': false,
      'reviewed_document_sha256': 'A' * 64,
      'source': 'correction',
      'deleted_at_ms': '-1',
      'app_version': '',
      'unknown_field': 'PRIVATE',
    }.entries) {
      final value = jsonDecode(golden) as Map<String, dynamic>;
      value[patch.key] = patch.value;
      expect(
        () => ReceiptTombstoneCodec.decode(jsonEncode(value)),
        throwsA(isA<ReceiptDataException>()),
        reason: patch.key,
      );
    }
    expect(
      () => ReceiptTombstoneCodec.decode('$golden\n'),
      throwsA(isA<ReceiptDataException>()),
    );
    final value = jsonDecode(golden) as Map<String, dynamic>;
    value['expected_head']['sequence'] = '0';
    expect(
      () => ReceiptTombstoneCodec.decode(jsonEncode(value)),
      throwsA(isA<ReceiptDataException>()),
    );
  });
}
