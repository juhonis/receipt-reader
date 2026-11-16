import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import 'support.dart';

Matcher fails(String code) =>
    throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test(
    'history pages use civil dates, stable ties and exact signed amounts',
    () async {
      final total = BigInt.parse('-9223372036854775808');
      await h.repository.saveManual(
        command(
          snapshot(
            number: 10,
            date: '17.11.2026',
            total: total,
            items: [row(number: 11, cents: total)],
          ),
          mutation: 12,
        ),
      );
      final branch = (await h.repository.branches()).single;
      for (final entry in [
        (20, '16.11.2026 23:59'),
        (30, '17.11.2026'),
        (40, '17.11.2026 00:01'),
      ]) {
        await h.repository.saveManual(
          command(
            snapshot(
              number: entry.$1,
              date: entry.$2,
              branch: branch,
              items: [row(number: entry.$1 + 1)],
            ),
            mutation: entry.$1 + 2,
          ),
        );
      }
      await h.reopen();
      final first = await h.repository.history(limit: 2);
      final second = await h.repository.history(limit: 2, offset: 2);
      expect([...first, ...second].map((r) => r.document.snapshot.id), [
        id(40),
        id(10),
        id(30),
        id(20),
      ]);
      expect(first.last.document.snapshot.totalCents, total);
      expect(first.last.document.snapshot.date.utcInstantMs, isNull);
      expect(await h.repository.history(offset: 4), isEmpty);
      for (final limit in [0, -1, 201]) {
        expect(() => h.repository.history(limit: limit), throwsArgumentError);
      }
      expect(() => h.repository.history(offset: -1), throwsArgumentError);
      // A history query must still check canonical documents and projections.
      h.raw.execute('UPDATE receipts SET total_amount_cents = 0 WHERE id = ?', [
        id(10).value,
      ]);
      await expectLater(h.repository.history(), fails('receiptProjection'));
    },
  );

  test('canonical event envelope matches independent bytes and SHA-256', () async {
    h.raw.execute('UPDATE dataset_state SET dataset_id = ?, device_id = ?', [
      id(90).value,
      id(91).value,
    ]);
    h.raw.execute('UPDATE received_cursors SET origin_device_id = ?', [
      id(91).value,
    ]);
    await h.repository.saveManual(command(snapshot()));
    final event = h.raw
        .select(
          'SELECT canonical_event, event_sha256 FROM change_log WHERE origin_seq = 1',
        )
        .single;
    expect(
      event['canonical_event'],
      File('test/fixtures/store_event_v1.json').readAsStringSync().trimRight(),
    );
    // Independently computed with .NET SHA256 from the committed UTF-8 fixture.
    expect(
      event['event_sha256'],
      'bd1d36852221c66f9b3227ed4c3e7528dff55f3a05f03c1c5d7d9b4fe5b5479a',
    );
    await h.repository.verifyIntegrity();
  });

  test(
    'product links wait for a catalog workflow rather than dropping references',
    () async {
      final linked = ReceiptSnapshot(
        id: id(1),
        branch: ReceiptBranch(id: id(2), name: 'TEST BRANCH'),
        date: StoredReceiptDate.parse('16.11.2026'),
        totalCents: BigInt.from(200),
        items: [
          ReceiptItemSnapshot(
            id: id(3),
            name: 'MILK',
            kind: LineKind.product,
            cents: BigInt.from(200),
            product: ReceiptProductLink(
              id: id(9),
              storeId: id(2),
              revision: RevisionId(id(10), BigInt.one),
            ),
          ),
        ],
      );
      await expectLater(
        h.repository.saveManual(command(linked)),
        fails('unsupportedProductLink'),
      );
      expect(h.count('change_log'), 0);
      expect((await h.repository.identity()).nextLocalSequence, BigInt.one);
    },
  );

  test(
    'new dataset, branch, receipt and full event group survive reopening',
    () async {
      final identity = await h.repository.identity();
      expect(identity.nextLocalSequence, BigInt.one);
      final pending = command(snapshot(date: '15.1.2026 12:34'));
      final result = await h.repository.saveManual(pending);
      expect(result.revision.origin, identity.deviceId);
      expect(result.revision.sequence, BigInt.two);
      expect(result.replayed, isFalse);
      expect(h.count('change_log'), 2);
      expect(h.count('entity_heads'), 2);
      expect(h.count('local_mutations'), 1);
      expect(
        h.raw
            .select(
              'SELECT mutation_index, mutation_count FROM change_log ORDER BY origin_seq',
            )
            .map((r) => [r['mutation_index'], r['mutation_count']]),
        [
          [0, 2],
          [1, 2],
        ],
      );
      expect(
        h.raw
            .select('SELECT dependency_seq FROM event_dependencies')
            .single['dependency_seq'],
        1,
      );
      expect(
        h.raw
            .select(
              'SELECT typeof(total_amount_cents) AS storage FROM receipts',
            )
            .single['storage'],
        'integer',
      );
      expect(
        h.raw
            .select('SELECT printed_second FROM receipts')
            .single['printed_second'],
        isNull,
      );
      await h.reopen();
      final reopened = await h.repository.identity();
      expect(reopened.datasetId, identity.datasetId);
      expect(reopened.deviceId, identity.deviceId);
      expect(reopened.nextLocalSequence, BigInt.from(3));
      final saved = (await h.repository.read(id(1)))!;
      expect(saved.revision, result.revision);
      expect(saved.document.sha256Hex, pending.document.sha256Hex);
      final branch = (await h.repository.branches()).single;
      expect(branch.revision!.sequence, BigInt.one);
      expect(branch.name, 'TEST BRANCH');
      await h.repository.verifyIntegrity();
    },
  );

  test('retry is idempotent even after a later edit and restart', () async {
    final initial = command(snapshot());
    final first = await h.repository.saveManual(initial);
    final branch = (await h.repository.branches()).single;
    final edited = command(
      snapshot(
        branch: branch,
        items: [row(name: 'Corrected milk')],
      ),
      mutation: 5,
      heads: [first.revision],
      at: 100,
    );
    final second = await h.repository.saveManual(edited);
    expect(second.revision.sequence, BigInt.from(3));
    await h.reopen();
    final retried = await h.repository.saveManual(initial);
    expect(retried.replayed, isTrue);
    expect(retried.revision, first.revision);
    expect(
      (await h.repository.read(id(1)))!.document.snapshot.items.single.name,
      'Corrected milk',
    );
    expect(h.count('change_log'), 3);
    expect(
      h.raw
          .select('SELECT created_at_ms, updated_at_ms FROM receipts')
          .single['created_at_ms'],
      123,
    );
    expect(
      h.raw
          .select('SELECT updated_at_ms FROM receipts')
          .single['updated_at_ms'],
      100,
    );
    await expectLater(
      h.repository.saveManual(
        command(snapshot(items: [row(name: 'Different')])),
      ),
      fails('mutationIdentityReused'),
    );
    expect(h.count('change_log'), 3);
  });

  test(
    'receipt children replace atomically; removed IDs remain reserved',
    () async {
      final first = await h.repository.saveManual(
        command(
          snapshot(items: [row(), row(number: 5)], total: BigInt.from(400)),
        ),
      );
      final branch = (await h.repository.branches()).single;
      final second = await h.repository.saveManual(
        command(
          snapshot(
            branch: branch,
            items: [row(number: 5, name: 'Retained')],
          ),
          mutation: 6,
          heads: [first.revision],
        ),
      );
      expect(h.count('receipt_items'), 1);
      expect(h.count('row_identities'), 2);
      expect(h.count('receipt_reviews'), 1);
      expect(h.count('revision_parents'), 1);
      await expectLater(
        h.repository.saveManual(
          command(
            snapshot(branch: branch),
            mutation: 7,
            heads: [second.revision],
          ),
        ),
        fails('rowIdentityReused'),
      );
      await expectLater(
        h.repository.saveManual(
          command(snapshot(number: 8, branch: branch), mutation: 9),
        ),
        fails('rowIdentityReused'),
      );
      expect(h.count('change_log'), 3);
      await h.repository.verifyIntegrity();
    },
  );

  test('stale screens, missing receipts and unconfirmed catalog revisions do not write', () async {
    final first = await h.repository.saveManual(command(snapshot()));
    final branch = (await h.repository.branches()).single;
    await expectLater(
      h.repository.saveManual(
        command(snapshot(), mutation: 5, heads: [first.revision]),
      ),
      fails('staleBranch'),
    );
    await expectLater(
      h.repository.saveManual(command(snapshot(branch: branch), mutation: 6)),
      fails('staleReceipt'),
    );
    await expectLater(
      h.repository.saveManual(
        command(
          snapshot(number: 7, branch: branch, items: [row(number: 8)]),
          mutation: 9,
          heads: [first.revision],
        ),
      ),
      fails('staleReceipt'),
    );
    final second = await h.repository.saveManual(
      command(snapshot(branch: branch), mutation: 5, heads: [first.revision]),
    );
    await expectLater(
      h.repository.saveManual(
        command(snapshot(branch: branch), mutation: 6, heads: [first.revision]),
      ),
      fails('staleReceipt'),
    );
    expect((await h.repository.read(id(1)))!.revision, second.revision);
    expect(h.count('change_log'), 3);
  });

  test(
    'parent references can precede product rows; branch correction is atomic',
    () async {
      final product = row();
      final discount = row(
        number: 5,
        kind: LineKind.discount,
        cents: BigInt.from(-50),
        parent: product.id,
        scope: DiscountScope.item,
      );
      final first = await h.repository.saveManual(
        command(snapshot(items: [discount, product], total: BigInt.from(150))),
      );
      final changed = snapshot(
        branch: ReceiptBranch(id: id(7), name: 'OTHER BRANCH'),
        items: [discount, product],
        total: BigInt.from(150),
      );
      final second = await h.repository.saveManual(
        command(changed, mutation: 8, heads: [first.revision]),
      );
      expect(second.revision.sequence, BigInt.from(4));
      expect(h.count('stores'), 2);
      expect(
        h.raw
            .select('SELECT DISTINCT store_id FROM receipt_items')
            .single['store_id'],
        id(7).value,
      );
      expect(h.raw.select('PRAGMA foreign_key_check'), isEmpty);
      await h.reopen();
      expect(
        (await h.repository.read(id(1)))!
            .document
            .snapshot
            .items
            .first
            .parentItemId,
        product.id,
      );
    },
  );

  test('signed limits and overflow-prone sums persist as integers', () async {
    final current = snapshot(
      items: [
        row(cents: sqliteInt64Max),
        row(number: 5, cents: sqliteInt64Max),
        row(number: 6, cents: -sqliteInt64Max),
      ],
      total: sqliteInt64Max,
    );
    await h.repository.saveManual(command(current));
    await h.reopen();
    expect(
      (await h.repository.read(id(1)))!.document.snapshot.totalCents,
      sqliteInt64Max,
    );
    expect(
      h.raw
          .select(
            'SELECT line_total_cents FROM receipt_items ORDER BY position',
          )
          .first['line_total_cents'],
      sqliteInt64Max.toInt(),
    );
    final branch = (await h.repository.branches()).single;
    await h.repository.saveManual(
      command(
        snapshot(
          number: 7,
          branch: branch,
          items: [row(number: 8, cents: sqliteInt64Min)],
          total: sqliteInt64Min,
        ),
        mutation: 9,
      ),
    );
    await h.reopen();
    expect(
      (await h.repository.read(id(7)))!.document.snapshot.totalCents,
      sqliteInt64Min,
    );
  });

  test('signed weighed quantities and exact rates survive reopen', () async {
    final weighed = ReceiptItemSnapshot(
      id: id(3),
      name: 'MÄNTY 🥛',
      kind: LineKind.product,
      cents: -BigInt.one,
      quantityValue: BigInt.from(-5),
      quantityScale: 1,
      quantityUnit: QuantityUnit.kg,
      rateMicros: BigInt.from(10000),
    );
    await h.repository.saveManual(
      command(snapshot(items: [weighed], total: -BigInt.one)),
    );
    await h.reopen();
    final row = (await h.repository.read(id(1)))!
        .document
        .snapshot
        .items
        .single;
    expect(row.quantityValue, BigInt.from(-5));
    expect(row.quantityScale, 1);
    expect(row.quantityUnit, QuantityUnit.kg);
    expect(row.rateMicros, BigInt.from(10000));
    expect(row.cents, -BigInt.one);
    expect(
      h.raw
          .select('SELECT quantity_value FROM receipt_items')
          .single['quantity_value'],
      -5,
    );
    await h.repository.verifyIntegrity();
  });

  test(
    'concurrent connections never silently overwrite the same base',
    () async {
      final first = await h.repository.saveManual(command(snapshot()));
      final branch = (await h.repository.branches()).single;
      final other = await ReceiptRepository.open(h.file);
      try {
        Future<Object> attempt(
          ReceiptRepository repository,
          String name,
          int mutation,
        ) async {
          try {
            return await repository.saveManual(
              command(
                snapshot(
                  branch: branch,
                  items: [row(name: name)],
                ),
                mutation: mutation,
                heads: [first.revision],
              ),
            );
          } on StorageFailure catch (error) {
            return error;
          }
        }

        final outcomes = await Future.wait([
          attempt(h.repository, 'Writer A', 5),
          attempt(other, 'Writer B', 6),
        ]);
        expect(outcomes.whereType<SaveResult>(), hasLength(1));
        final error = outcomes.whereType<StorageFailure>().single;
        expect(error.code, anyOf('staleReceipt', 'busy'));
        expect(h.count('change_log'), 3);
        await h.repository.verifyIntegrity();
      } finally {
        await other.close();
      }
    },
  );
}
