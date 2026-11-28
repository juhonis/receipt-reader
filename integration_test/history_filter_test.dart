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

import '../test/support/navigation.dart';

class _ObservedStore implements LocalStore {
  _ObservedStore(this.repository);
  final ReceiptRepository repository;
  final pages = <List<StoredReceipt>>[];
  final offsets = <int>[];
  final filters = <HistoryFilter?>[];
  Future<void>? _closing;
  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) async {
    offsets.add(offset);
    filters.add(filter);
    final page = await repository.history(
      limit: limit,
      offset: offset,
      filter: filter,
    );
    pages.add(page);
    return page;
  }

  @override
  Future<SaveResult> saveManual(ReviewedReceipt c) => repository.saveManual(c);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt c) => repository.saveOcr(c);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      repository.deleteReceipt(command);
  @override
  Future<void> close() => _closing ??= repository.close();
}

ReviewedReceipt _command(ReceiptBranch branch, String date, BigInt cents) {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: branch,
    date: StoredReceiptDate.parse(date),
    totalCents: cents,
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: 'SYNTHETIC FILTER ROW',
        kind: LineKind.product,
        cents: cents,
      ),
    ],
  );
  return ReviewedReceipt.manual(
    current: snapshot,
    expectedHeads: [],
    confirmation: ManualReviewChecks(
      snapshot: snapshot,
      expectedHeads: [],
      mutationId: DurableId.generate(),
      branchReviewed: true,
      dateReviewed: true,
      totalReviewed: true,
      reviewedRowIds: snapshot.items.map((r) => r.id),
    ).confirm(reviewedAtMs: BigInt.one, appVersion: 'filter-smoke'),
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final target = find.byKey(Key('history-filter-$key'));
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void _historyTop(WidgetTester tester) {
  tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(HistoryPage),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .jumpTo(0);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native filtered history reopens, pages, resets and preserves data',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        '${support.path}/history-filter-smoke-${DurableId.generate().value}',
      );
      await directory.create();
      _ObservedStore? store;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        store = _ObservedStore(await ReceiptRepository.open(file));
        final aId = DurableId.generate(), bId = DurableId.generate();
        await store.saveManual(
          _command(
            ReceiptBranch(id: aId, name: 'SYNTHETIC FILTER A'),
            '15.11.2026',
            BigInt.from(-50),
          ),
        );
        final a = (await store.branches()).single;
        await store.saveManual(
          _command(
            ReceiptBranch(id: bId, name: 'SYNTHETIC FILTER B'),
            '16.11.2026',
            BigInt.from(-50),
          ),
        );
        await store.saveManual(_command(a, '16.11.2026', BigInt.zero));
        for (var i = 0; i < 31; i++) {
          await store.saveManual(
            _command(
              a,
              i.isEven ? '16.11.2026' : '16.11.2026 23:59:59',
              BigInt.from(-50),
            ),
          );
        }
        final before = await store.repository.history();
        final identity = await store.repository.identity();
        await store.close();
        store = _ObservedStore(await ReceiptRepository.open(file));
        final opened = store;
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => opened),
        );
        await tester.pumpAndSettle();
        await openReceiptManagement(tester);
        await _tap(tester, 'open-history');
        expect(store.pages.last, hasLength(30));
        await _tap(tester, 'history-filters');
        await _tap(tester, 'history-filter-branch');
        await tester.tap(find.text('SYNTHETIC FILTER A').last);
        await tester.pumpAndSettle();
        await _enter(tester, 'from', '16.11.2026');
        await _enter(tester, 'through', '16.11.2026');
        await _enter(tester, 'min', '-0,50');
        await _enter(tester, 'max', '-0,50');
        await _tap(tester, 'history-filter-apply');
        final filter = store.filters.last;
        expect(store.offsets, [0, 0]);
        expect(store.pages.last, hasLength(30));
        for (final receipt in store.pages.last) {
          expect(receipt.document.snapshot.branch.id, aId);
          expect(receipt.document.snapshot.date.day, 16);
          expect(receipt.document.snapshot.totalCents, BigInt.from(-50));
        }
        await tester.scrollUntilVisible(
          find.byKey(const Key('history-more')),
          500,
          scrollable: verticalScrollable(),
        );
        await _tap(tester, 'history-more');
        expect(store.offsets.last, 30);
        expect(store.pages.last, hasLength(1));
        expect(identical(store.filters.last, filter), isTrue);
        expect(find.byKey(const Key('history-more')), findsNothing);
        _historyTop(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('SYNTHETIC FILTER A').first);
        await tester.pumpAndSettle();
        expect(find.byType(ReceiptDetailPage), findsOneWidget);
        expect(find.text('SYNTHETIC FILTER ROW'), findsOneWidget);
        Navigator.of(tester.element(find.byType(ReceiptDetailPage))).pop();
        await tester.pumpAndSettle();
        await _tap(tester, 'history-refresh');
        expect(store.offsets.last, 0);
        expect(identical(store.filters.last, filter), isTrue);
        await _tap(tester, 'history-reset');
        expect(store.offsets.last, 0);
        expect(store.filters.last, isNull);
        expect(store.pages.last, hasLength(30));
        expect(
          (await store.repository.history()).map((r) => r.document.sha256Hex),
          before.map((r) => r.document.sha256Hex),
        );
        expect((await store.repository.history(limit: 200)), hasLength(34));
        final after = await store.repository.identity();
        expect(after.datasetId, identity.datasetId);
        expect(after.deviceId, identity.deviceId);
        expect(after.nextLocalSequence, identity.nextLocalSequence);
        await store.repository.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('history-filter-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
