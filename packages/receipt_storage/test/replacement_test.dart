import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

import '../../receipt_domain/test/ocr_support.dart';
import 'support.dart';
import 'deletion_test.dart' show deletion;

class _BranchOcr extends OcrFixture {
  _BranchOcr(this.selected);
  final ReceiptBranch selected;
  @override
  ReceiptBranch get branch => selected;
}

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());
  Future<StoredReceipt> oldReceipt() async {
    await h.repository.saveManual(
      command(snapshot(number: 60, items: [row(number: 61)]), mutation: 64),
    );
    return (await h.repository.history()).single;
  }

  Future<ReviewedReceipt> incoming({
    String date = '16.11.2026',
    int rowId = 21,
  }) async => command(
    snapshot(
      number: 20,
      branch: (await h.repository.branches()).single,
      items: [row(number: rowId)],
      date: date,
    ),
    mutation: 24,
  );
  Matcher fails(String code) =>
      throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));

  test('replacement is one visible receipt, retains history and retries across reopen/backup', () async {
    final old = await oldReceipt(), fresh = await incoming();
    final remove = deletion(old);
    final saved = await h.repository.replaceReceipt(fresh, remove);
    expect(
      (await h.repository.history()).single.document.snapshot.id,
      fresh.document.snapshot.id,
    );
    expect(await h.repository.read(old.document.snapshot.id), isNull);
    expect(
      (await h.repository.readDeleted(old.document.snapshot.id))!
          .tombstone
          .documentSha256,
      old.document.sha256Hex,
    );
    expect(h.count('change_log'), 4);
    await h.reopen();
    final retried = await h.repository.replaceReceipt(fresh, remove);
    expect(retried.replayed, isTrue);
    expect(retried.revision, saved.revision);
    final backup = await h.repository.exportBackup();
    final restored = await ReceiptRepository.restoreBackup(
      backup,
      stagingParent: h.directory,
    );
    final repository = await ReceiptRepository.open(restored.databaseFile);
    try {
      expect(
        (await repository.history()).single.document.snapshot.id,
        fresh.document.snapshot.id,
      );
      expect((await repository.replaceReceipt(fresh, remove)).replayed, isTrue);
      await repository.verifyIntegrity();
    } finally {
      await repository.close();
    }
    await h.repository.verifyIntegrity();
  });

  test(
    'OCR can replace a manual duplicate without rewriting its provenance',
    () async {
      final old = await oldReceipt();
      final fresh = _BranchOcr((await h.repository.branches()).single).save();
      await h.repository.replaceReceipt(fresh, deletion(old));
      expect(
        (await h.repository.history()).single.document.review.source,
        'ocr',
      );
      expect(
        (await h.repository.readDeleted(old.document.snapshot.id))!
            .tombstone
            .source,
        'manual',
      );
      await h.reopen();
    },
  );

  test('stale prior receipt and invalid incoming content leave the old receipt live', () async {
    final old = await oldReceipt(), fresh = await incoming();
    final branch = (await h.repository.branches()).single;
    await h.repository.saveManual(
      command(
        snapshot(
          number: 60,
          branch: branch,
          items: [row(number: 61, name: 'EDITED ITEM')],
        ),
        mutation: 65,
        heads: [old.revision],
      ),
    );
    final count = h.count('change_log');
    await expectLater(
      h.repository.replaceReceipt(fresh, deletion(old)),
      fails('staleReceipt'),
    );
    expect(await h.repository.read(fresh.document.snapshot.id), isNull);
    final current = (await h.repository.history()).single;
    await expectLater(
      h.repository.replaceReceipt(await incoming(rowId: 61), deletion(current)),
      fails('rowIdentityReused'),
    );
    expect(h.count('change_log'), count);
    expect(
      (await h.repository.history()).single.document.snapshot.id,
      old.document.snapshot.id,
    );
  });

  for (final point in [
    'DELETE ON receipt_items',
    'INSERT ON local_mutations',
  ]) {
    test(
      'outer transaction rolls back new save and old deletion on $point failure',
      () async {
        final old = await oldReceipt(), fresh = await incoming();
        final remove = deletion(old);
        final sequence = (await h.repository.identity()).nextLocalSequence;
        final field = point.startsWith('DELETE')
            ? 'OLD.receipt_id'
            : 'NEW.receipt_id';
        h.raw.execute(
          "CREATE TRIGGER fail_replace BEFORE $point WHEN $field = '${old.document.snapshot.id.value}' BEGIN SELECT RAISE(ABORT, 'synthetic replacement failure'); END",
        );
        await expectLater(
          h.repository.replaceReceipt(fresh, remove),
          fails('constraint'),
        );
        expect(h.count('change_log'), 2);
        expect(h.count('local_mutations'), 1);
        expect((await h.repository.identity()).nextLocalSequence, sequence);
        expect(await h.repository.read(fresh.document.snapshot.id), isNull);
        expect(
          (await h.repository.history()).single.document.sha256Hex,
          old.document.sha256Hex,
        );
        await h.repository.verifyIntegrity();
        h.raw.execute('DROP TRIGGER fail_replace');
        await h.repository.replaceReceipt(fresh, remove);
        await h.reopen();
      },
    );
  }

  test('separately saved incoming mutation cannot be used to delete an old receipt', () async {
    final old = await oldReceipt(), fresh = await incoming();
    await h.repository.saveManual(fresh);
    await expectLater(
      h.repository.replaceReceipt(fresh, deletion(old)),
      fails('replacementState'),
    );
    expect(await h.repository.history(), hasLength(2));
    expect(h.count('change_log'), 3);
  });
  test(
    'a previously separate deletion cannot commit a new incoming receipt',
    () async {
      final old = await oldReceipt(), fresh = await incoming();
      final remove = deletion(old);
      await h.repository.deleteReceipt(remove);
      await expectLater(
        h.repository.replaceReceipt(fresh, remove),
        fails('replacementState'),
      );
      expect(await h.repository.history(), isEmpty);
      expect(await h.repository.read(fresh.document.snapshot.id), isNull);
    },
  );
  test('replacement rejects unrelated receipts and corrections', () async {
    final old = await oldReceipt();
    await expectLater(
      h.repository.replaceReceipt(
        await incoming(date: '17.11.2026'),
        deletion(old),
      ),
      fails('notDuplicate'),
    );
    final correction = command(
      old.document.snapshot,
      mutation: 25,
      heads: [old.revision],
    );
    await expectLater(
      h.repository.replaceReceipt(correction, deletion(old)),
      fails('replacementRequiresNewReceipt'),
    );
    expect(
      (await h.repository.history()).single.document.sha256Hex,
      old.document.sha256Hex,
    );
  });
  test('retry after the new receipt is later deleted cannot resurrect either receipt', () async {
    final old = await oldReceipt(), fresh = await incoming();
    final remove = deletion(old);
    await h.repository.replaceReceipt(fresh, remove);
    await h.repository.deleteReceipt(
      deletion((await h.repository.history()).single, mutation: 81),
    );
    expect((await h.repository.replaceReceipt(fresh, remove)).replayed, isTrue);
    expect(await h.repository.history(), isEmpty);
    await h.reopen();
  });
}
