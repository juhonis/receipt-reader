import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/local_store.dart';

class _ObservedStore implements LocalStore {
  _ObservedStore(this.repository);
  final ReceiptRepository repository;
  Future<void>? _closing;
  Future<SaveResult>? lastWrite;
  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) => repository.history(limit: limit, offset: offset, filter: filter);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt command) =>
      lastWrite = repository.saveManual(command);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      repository.saveOcr(command);
  @override
  Future<void> close() => _closing ??= repository.close();
}

ReviewedReceipt _command(
  ReceiptSnapshot snapshot, {
  List<RevisionId> heads = const [],
}) => ReviewedReceipt.manual(
  current: snapshot,
  expectedHeads: heads,
  confirmation: ManualReviewChecks(
    snapshot: snapshot,
    expectedHeads: heads,
    mutationId: DurableId.generate(),
    branchReviewed: true,
    dateReviewed: true,
    totalReviewed: true,
    reviewedRowIds: snapshot.items.map((r) => r.id),
  ).confirm(reviewedAtMs: BigInt.one, appVersion: 'correction-smoke'),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 300);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _review(WidgetTester tester) async {
  for (final key in [
    'manual-branch-reviewed',
    'manual-date-reviewed',
    'manual-total-reviewed',
    for (var i = 0; i < 4; i++) 'manual-row-reviewed-$i',
  ]) {
    await _tap(tester, key);
  }
}

Future<void> _openHistory(WidgetTester tester, _ObservedStore store) async {
  await tester.pumpWidget(ReceiptReaderApp(storageOpener: () async => store));
  await tester.pumpAndSettle();
  await _tap(tester, 'open-history');
  await tester.tap(find.text('SYNTHETIC CORRECTION BRANCH'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native manual correction preserves metadata, reopens and rejects stale edits',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        '${support.path}/manual-correction-smoke-${DurableId.generate().value}',
      );
      await directory.create();
      _ObservedStore? store;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        store = _ObservedStore(await ReceiptRepository.open(file));
        final product = DurableId.generate();
        final original = ReceiptSnapshot(
          id: DurableId.generate(),
          branch: ReceiptBranch(
            id: DurableId.generate(),
            name: 'SYNTHETIC CORRECTION BRANCH',
          ),
          date: StoredReceiptDate.parse('16.11.2026 23:59:56'),
          totalCents: BigInt.from(250),
          items: [
            ReceiptItemSnapshot(
              id: product,
              name: 'SYNTHETIC PRODUCT',
              rawName: 'PRINTED PRODUCT',
              kind: LineKind.product,
              cents: BigInt.from(300),
              quantityValue: BigInt.from(15),
              quantityScale: 1,
              quantityUnit: QuantityUnit.kg,
              rateMicros: BigInt.from(2000000),
            ),
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC DISCOUNT',
              kind: LineKind.discount,
              cents: BigInt.from(-50),
              parentItemId: product,
              discountScope: DiscountScope.item,
            ),
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC DEPOSIT',
              kind: LineKind.deposit,
              cents: BigInt.from(10),
            ),
            ReceiptItemSnapshot(
              id: DurableId.generate(),
              name: 'SYNTHETIC ADJUSTMENT',
              kind: LineKind.adjustment,
              cents: BigInt.from(-10),
              adjustmentReason: 'SYNTHETIC REASON',
            ),
          ],
        );
        final created = await store.saveManual(_command(original));
        final identity = await store.repository.identity();
        await _openHistory(tester, store);
        await _tap(tester, 'edit-manual-receipt');
        await _review(tester);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('manual-save')))
              .onPressed,
          isNull,
        );
        await _enter(tester, 'manual-date', '17.11.2026');
        await _enter(
          tester,
          'manual-row-name-0',
          'SYNTHETIC CORRECTED PRODUCT',
        );
        await _review(tester);
        await _tap(tester, 'manual-save');
        await _tap(tester, 'confirm-save');
        await store.lastWrite;
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptDetailPage), findsNothing);
        expect(find.byType(HistoryPage), findsOneWidget);
        final corrected = (await store.repository.history()).single;
        final snapshot = corrected.document.snapshot;
        expect(snapshot.id, original.id);
        expect(
          snapshot.items.map((r) => r.id),
          original.items.map((r) => r.id),
        );
        expect(snapshot.items.first.rawName, 'PRINTED PRODUCT');
        expect(snapshot.items.first.quantityValue, BigInt.from(15));
        expect(snapshot.items.first.quantityScale, 1);
        expect(snapshot.items.first.rateMicros, BigInt.from(2000000));
        expect(snapshot.items[1].parentItemId, product);
        expect(snapshot.items[1].discountScope, DiscountScope.item);
        expect(snapshot.items[2].parentItemId, isNull);
        expect(snapshot.items[3].adjustmentReason, 'SYNTHETIC REASON');
        expect(snapshot.date.day, 17);
        expect(snapshot.date.hour, isNull);
        expect(corrected.document.review.source, 'manual');
        expect(corrected.document.review.expectedHeads, [created.revision]);
        expect(
          corrected.revision.sequence,
          created.revision.sequence + BigInt.one,
        );
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = _ObservedStore(await ReceiptRepository.open(file));
        expect(
          (await store.repository.history()).single.document.sha256Hex,
          corrected.document.sha256Hex,
        );
        expect(
          (await store.repository.identity()).datasetId,
          identity.datasetId,
        );
        expect((await store.repository.identity()).deviceId, identity.deviceId);
        await _openHistory(tester, store);
        expect(find.text('SYNTHETIC CORRECTED PRODUCT'), findsOneWidget);
        await _tap(tester, 'edit-manual-receipt');
        await _enter(tester, 'manual-date', '19.11.2026');
        await _review(tester);
        await _tap(tester, 'manual-save');
        // Another reviewed command wins while this editor holds the old head.
        final concurrent = _command(
          ReceiptSnapshot(
            id: snapshot.id,
            branch: snapshot.branch,
            date: StoredReceiptDate.parse('18.11.2026'),
            totalCents: snapshot.totalCents,
            items: snapshot.items,
          ),
          heads: [corrected.revision],
        );
        await store.saveManual(concurrent);
        final beforeStale = await store.repository.identity();
        await _tap(tester, 'confirm-save');
        await expectLater(
          store.lastWrite,
          throwsA(
            isA<StorageFailure>().having((e) => e.code, 'code', 'staleReceipt'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('manual-save')))
              .onPressed,
          isNull,
        );
        expect(
          find.textContaining('Tätä korjausta ei tallennettu.'),
          findsOneWidget,
        );
        await _tap(tester, 'manual-close-pending');
        expect(find.byType(ReceiptDetailPage), findsNothing);
        expect(find.text('18.11.2026'), findsOneWidget);
        final after = (await store.repository.history()).single;
        expect(after.document.sha256Hex, concurrent.document.sha256Hex);
        expect(
          (await store.repository.identity()).nextLocalSequence,
          beforeStale.nextLocalSequence,
        );
        await store.repository.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('manual-correction-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
