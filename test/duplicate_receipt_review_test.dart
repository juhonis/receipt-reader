import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/duplicate_receipts.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import 'ocr_review_guidance_test.dart' show reveal;
import 'manual_save_test.dart' as manual;
import 'support/fake_store.dart';

Future<StoredReceipt> seedDuplicate(
  FakeStore store, {
  String date = '19.11.2026 12:34',
  int cents = 200,
  String name = 'OLD ITEM',
}) async {
  final snapshot = ReceiptSnapshot(
    id: DurableId.generate(),
    branch: store.branch,
    date: StoredReceiptDate.parse(date),
    totalCents: BigInt.from(cents),
    items: [
      ReceiptItemSnapshot(
        id: DurableId.generate(),
        name: name,
        kind: LineKind.product,
        cents: BigInt.from(cents),
      ),
    ],
  );
  final checks = ManualReviewChecks(
    snapshot: snapshot,
    expectedHeads: [],
    mutationId: DurableId.generate(),
    branchReviewed: true,
    dateReviewed: true,
    totalReviewed: true,
    reviewedRowIds: snapshot.items.map((r) => r.id),
  );
  await store.saveManual(
    ReviewedReceipt.manual(
      current: snapshot,
      expectedHeads: [],
      confirmation: checks.confirm(
        reviewedAtMs: BigInt.one,
        appVersion: 'synthetic-test',
      ),
    ),
  );
  store.saved.clear();
  return store.documents.last;
}

Future<void> openDuplicateOcr(
  WidgetTester t,
  LocalStore store, {
  String date = '19.11.2026 12:34',
}) async {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final evidence = (await t.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 600);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return ReceiptEvidence.decode(bytes!.buffer.asUint8List());
  }))!;
  addTearDown(evidence.dispose);
  final branch = (await store.branches()).single;
  final draft = parseReceipt(
    OcrPage(800, 600, [
      OcrWord(branch.name, PixelBox(20, 20, 400, 36)),
      OcrWord(date, PixelBox(20, 70, 500, 86)),
      OcrWord('NEW ITEM', PixelBox(20, 150, 200, 166)),
      OcrWord('2,00', PixelBox(650, 150, 720, 166)),
      OcrWord('YHTEENSÄ', PixelBox(20, 220, 200, 236)),
      OcrWord('2,00', PixelBox(650, 220, 720, 236)),
    ]),
    itemTop: 120,
    priceColumnLeft: 600,
  );
  await t.pumpWidget(const ReceiptReaderApp());
  Navigator.of(t.element(find.text('Kokeile kuitin tarkistusta'))).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ReviewPage(store: store, draft: draft, evidence: evidence),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> duplicateTap(WidgetTester t, String key) async {
  final finder = find.byKey(ValueKey(key));
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> tryDuplicateSave(WidgetTester t) async {
  await reveal(t, 'ocr-save');
  await duplicateTap(t, 'ocr-save');
}

void main() {
  test('duplicate lookup includes later pages on the same day', () async {
    final store = FakeStore();
    final unrelated = await seedDuplicate(store, date: '19.11.2026 12:00');
    store.documents.addAll(List.filled(199, unrelated));
    final target = await seedDuplicate(store);
    final incoming = ReceiptSnapshot(
      id: DurableId.generate(),
      branch: store.branch,
      date: StoredReceiptDate.parse('19.11.2026 12:34'),
      totalCents: BigInt.from(200),
      items: [
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'TEST ITEM',
          kind: LineKind.product,
          cents: BigInt.from(200),
        ),
      ],
    );
    final matches = await findDuplicateReceipts(store, incoming);
    expect(matches.single.document.snapshot.id, target.document.snapshot.id);
    expect(store.historyOffsets, [0, 200]);
  });
  runDuplicateReceiptReviewTests();
}

/// Portable synthetic images/fake persistence; real SQLite replacement is tested
/// separately on both native platforms.
void runDuplicateReceiptReviewTests() {
  testWidgets(
    'leaving while lookup is pending cannot open a ghost duplicate dialog',
    (t) async {
      final store = FakeStore();
      await seedDuplicate(store);
      await openDuplicateOcr(t, store);
      await reveal(t, 'ocr-save');
      final gate = Completer<void>();
      store.historyGate = gate.future;
      await t.tap(find.byKey(const Key('ocr-save')));
      await t.pump();
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 1));
      gate.complete();
      await t.pumpAndSettle();
      expect(find.byType(ReviewPage), findsNothing);
      expect(find.text('Mahdollinen kaksoiskuitti'), findsNothing);
      expect(store.saved, isEmpty);
      expect(store.deletions, isEmpty);
    },
  );
  testWidgets(
    'a late retry result cannot close the draft after cancelling the dialog',
    (t) async {
      final store = FakeStore();
      await seedDuplicate(store);
      await openDuplicateOcr(t, store);
      store.failHistory = true;
      await tryDuplicateSave(t);
      store.failHistory = false;
      store.documents.clear();
      final gate = Completer<void>();
      store.historyGate = gate.future;
      await t.tap(find.byKey(const Key('duplicate-retry-lookup')));
      await t.pump();
      await t.tap(find.byKey(const Key('duplicate-cancel')));
      await t.pump(const Duration(milliseconds: 1));
      gate.complete();
      await t.pumpAndSettle();
      expect(find.byType(ReviewPage), findsOneWidget);
      expect(store.saved, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('discard new keeps the existing receipt and performs no write', (
    t,
  ) async {
    final store = FakeStore();
    final old = await seedDuplicate(store);
    await openDuplicateOcr(t, store);
    await tryDuplicateSave(t);
    expect(find.text('Mahdollinen kaksoiskuitti'), findsOneWidget);
    expect(store.saved, isEmpty);
    await duplicateTap(t, 'duplicate-discard-new');
    expect(store.documents.single.document.sha256Hex, old.document.sha256Hex);
    expect(store.saved, isEmpty);
    expect(store.deletions, isEmpty);
    expect(find.byType(ReviewPage), findsNothing);
  });

  testWidgets(
    'replace new OCR keeps its values and tombstones only the selected old receipt',
    (t) async {
      final store = FakeStore();
      final old = await seedDuplicate(store, cents: 300);
      await openDuplicateOcr(t, store);
      await tryDuplicateSave(t);
      expect(find.text('3,00 €'), findsOneWidget);
      await duplicateTap(
        t,
        'duplicate-replace-${old.document.snapshot.id.value}',
      );
      expect(store.documents.single.document.review.source, 'ocr');
      expect(
        store.documents.single.document.snapshot.items.single.name,
        'NEW ITEM',
      );
      expect(
        store.documents.single.document.snapshot.totalCents,
        BigInt.from(200),
      );
      expect(
        store.tombstones[old.document.snapshot.id]!.documentSha256,
        old.document.sha256Hex,
      );
      expect(store.replacements, hasLength(1));
    },
  );

  testWidgets(
    'keep both is explicit and cancel returns to the editable draft',
    (t) async {
      final store = FakeStore();
      await seedDuplicate(store);
      await openDuplicateOcr(t, store);
      await tryDuplicateSave(t);
      await duplicateTap(t, 'duplicate-cancel');
      expect(find.byType(ReviewPage), findsOneWidget);
      expect(store.saved, isEmpty);
      await tryDuplicateSave(t);
      await duplicateTap(t, 'duplicate-keep-both');
      expect(store.documents, hasLength(2));
      expect(store.deletions, isEmpty);
    },
  );

  testWidgets('different minute saves without adding a duplicate dialog', (
    t,
  ) async {
    final store = FakeStore();
    await seedDuplicate(store, date: '19.11.2026 12:35');
    await openDuplicateOcr(t, store);
    await tryDuplicateSave(t);
    expect(find.text('Mahdollinen kaksoiskuitti'), findsNothing);
    expect(store.documents, hasLength(2));
  });

  testWidgets('missing time still warns for the same day, branch and amount', (
    t,
  ) async {
    final store = FakeStore();
    await seedDuplicate(store, date: '19.11.2026');
    await openDuplicateOcr(t, store, date: '19.11.2026');
    await tryDuplicateSave(t);
    expect(find.textContaining('Kellonaika puuttuu:'), findsOneWidget);
    await duplicateTap(t, 'duplicate-discard-new');
    expect(store.documents, hasLength(1));
  });

  testWidgets(
    'replacement retry reuses both confirmed commands after an uncertain result',
    (t) async {
      final store = FakeStore();
      final old = await seedDuplicate(store);
      store.failSaveAfterCommit = true;
      await openDuplicateOcr(t, store);
      await tryDuplicateSave(t);
      await duplicateTap(
        t,
        'duplicate-replace-${old.document.snapshot.id.value}',
      );
      expect(store.documents, hasLength(1));
      expect(store.tombstones, hasLength(1));
      final first = store.replacements.single;
      store.failSaveAfterCommit = false;
      await duplicateTap(t, 'ocr-retry-save');
      expect(identical(store.replacements.last.$1, first.$1), isTrue);
      expect(identical(store.replacements.last.$2, first.$2), isTrue);
      expect(store.documents, hasLength(1));
      expect(store.tombstones, hasLength(1));
    },
  );

  testWidgets(
    'stale replacement cannot discard a newer old receipt or commit the new draft',
    (t) async {
      final store = FakeStore();
      final old = await seedDuplicate(store);
      await openDuplicateOcr(t, store);
      await tryDuplicateSave(t);
      store.documents[0] = StoredReceipt(
        old.document,
        RevisionId(old.revision.origin, old.revision.sequence + BigInt.one),
      );
      await duplicateTap(
        t,
        'duplicate-replace-${old.document.snapshot.id.value}',
      );
      expect(
        store.documents.single.document.snapshot.id,
        old.document.snapshot.id,
      );
      expect(store.tombstones, isEmpty);
      expect(find.byKey(const Key('ocr-retry-save')), findsNothing);
      expect(find.byKey(const Key('ocr-close-pending')), findsOneWidget);
    },
  );

  testWidgets(
    'lookup failure retries without silently bypassing duplicate detection',
    (t) async {
      final store = FakeStore();
      await seedDuplicate(store);
      await openDuplicateOcr(t, store);
      store.failHistory = true;
      await tryDuplicateSave(t);
      expect(find.byKey(const Key('duplicate-keep-both')), findsNothing);
      expect(store.saved, isEmpty);
      store.failHistory = false;
      await duplicateTap(t, 'duplicate-retry-lookup');
      await duplicateTap(t, 'duplicate-discard-new');
      expect(store.saved, isEmpty);
      expect(store.documents, hasLength(1));
    },
  );

  testWidgets('multiple matches replace just the chosen old receipt', (
    t,
  ) async {
    final store = FakeStore();
    final first = await seedDuplicate(store, name: 'FIRST OLD ITEM');
    final second = await seedDuplicate(store, name: 'SECOND OLD ITEM');
    await openDuplicateOcr(t, store);
    await tryDuplicateSave(t);
    await duplicateTap(
      t,
      'duplicate-replace-${second.document.snapshot.id.value}',
    );
    expect(store.documents, hasLength(2));
    expect(
      store.documents.any(
        (r) => r.document.snapshot.id == first.document.snapshot.id,
      ),
      isTrue,
    );
    expect(store.tombstones.keys, [second.document.snapshot.id]);
  });

  testWidgets('manual entry uses the same explicit replacement choice', (
    t,
  ) async {
    final store = FakeStore();
    final old = await seedDuplicate(store, date: '16.11.2026');
    await manual.start(t, store);
    await manual.review(t);
    await manual.tapKey(t, 'manual-save');
    await manual.tapKey(t, 'confirm-save');
    await duplicateTap(
      t,
      'duplicate-replace-${old.document.snapshot.id.value}',
    );
    expect(store.documents.single.document.review.source, 'manual');
    expect(
      store.documents.single.document.snapshot.items.single.name,
      'SYNTHETIC MILK',
    );
    expect(store.replacements, hasLength(1));
  });

  testWidgets(
    'duplicate comparison and choices fit a compact enlarged-text screen',
    (t) async {
      final store = FakeStore();
      final old = await seedDuplicate(store);
      await openDuplicateOcr(t, store);
      t.view.physicalSize = const Size(320, 960);
      // This simulates an idle compact display, independent of asynchronous IME
      // metrics left by a previous native manual-entry test.
      t.view.viewInsets = FakeViewPadding.zero;
      addTearDown(t.view.resetViewInsets);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      await tryDuplicateSave(t);
      await duplicateTap(
        t,
        'duplicate-replace-${old.document.snapshot.id.value}',
      );
      expect(store.documents, hasLength(1));
      expect(store.tombstones, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
}
