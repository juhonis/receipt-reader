import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/local_store.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import '../packages/receipt_domain/test/ocr_support.dart';
import 'ocr_save_test.dart' show visible, tap;

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
      repository.saveManual(command);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt command) =>
      lastWrite = repository.saveOcr(command);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      repository.deleteReceipt(command);
  @override
  Future<void> close() => _closing ??= repository.close();
}

Future<ReceiptEvidence> _pixels(OcrPage page) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  for (final word in page.words) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
      ..addText(word.text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 480));
    canvas.drawParagraph(paragraph, ui.Offset(word.box.left, word.box.top));
    paragraph.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(500, 500);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return ReceiptEvidence.decode(bytes!.buffer.asUint8List());
}

Future<void> _open(
  WidgetTester tester,
  _ObservedStore store,
  StoredReceipt receipt,
  ReceiptEvidence evidence,
) async {
  Navigator.of(tester.element(find.byKey(const Key('open-history')))).push(
    MaterialPageRoute<bool>(
      builder: (_) => ReviewPage.correction(
        store: store,
        receipt: receipt,
        evidence: evidence,
        draft: OcrFixture().draft,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, 'ocr-branch');
  await tester.tap(find.text('TEST BRANCH').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.text('Olen tarkistanut myymälän toimipisteen'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
  await tester.pumpAndSettle();
  await tap(tester, 'ocr-row-identity-0');
  await tester.tap(
    find
        .text('1. ${receipt.document.snapshot.items.single.name} (2,00 €)')
        .last,
  );
  await tester.pumpAndSettle();
  await visible(tester, 'row-name-0');
  await tester.enterText(find.byKey(const Key('row-name-0')), 'Corrected milk');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tap(tester, 'row-image-compared-0');
  await tap(tester, 'review-page-evidence');
  for (final key in [
    'page-header',
    'page-footer',
    'page-layout',
    'page-complete-image',
  ]) {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tap(tester, key, scroll: false);
  }
  await tester.ensureVisible(find.byKey(const Key('page-evidence-note')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('page-evidence-note')),
    'Compared synthetic original',
  );
  await tester.pumpAndSettle();
  await tap(tester, 'approve-page-evidence', scroll: false);
  await tap(tester, 'review-confirmation');
  await tap(tester, 'ocr-save');
  for (final key in [
    'ocr-save-identities',
    'ocr-save-date',
    'ocr-save-total',
  ]) {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tap(tester, key, scroll: false);
  }
}

ReviewedReceipt _concurrent(StoredReceipt receipt, ReceiptBranch branch) {
  final f = OcrFixture();
  final audit = f.audit();
  final checks = OcrReviewChecks(
    audit: audit,
    branch: branch,
    receiptId: receipt.document.snapshot.id,
    rowIds: f.ids,
    rowDetails: const {},
    expectedHeads: [receipt.revision],
    mutationId: DurableId.generate(),
    dateReviewed: true,
    totalReviewed: true,
  );
  return ReviewedReceipt.ocr(
    current: audit,
    branch: branch,
    rowDetails: const {},
    expectedHeads: [receipt.revision],
    confirmation: checks.confirm(
      reviewedAtMs: BigInt.from(456),
      appVersion: 'native-correction-test',
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh OCR correction survives native reopen and rejects a concurrent stale save',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        '${support.path}/ocr-correction-smoke-${DurableId.generate().value}',
      );
      await directory.create();
      _ObservedStore? store;
      ReceiptEvidence? evidence;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        store = _ObservedStore(await ReceiptRepository.open(file));
        await store.repository.saveOcr(OcrFixture().save());
        final prior = (await store.repository.history()).single;
        final initial = store;
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => initial),
        );
        await tester.pumpAndSettle();
        evidence = await _pixels(OcrFixture().draft.parseContext!.page);
        await _open(tester, initial, prior, evidence);
        await tap(tester, 'ocr-confirm-save', scroll: false);
        await store.lastWrite;
        await tester.pumpAndSettle();
        expect(evidence.isDisposed, isTrue);
        final corrected = (await store.repository.history()).single;
        expect(corrected.document.snapshot.id, prior.document.snapshot.id);
        expect(
          corrected.document.snapshot.items.single.id,
          prior.document.snapshot.items.single.id,
        );
        expect(corrected.document.snapshot.items.single.name, 'Corrected milk');
        expect(corrected.document.snapshot.items.single.rawName, 'MILK');
        expect(corrected.document.review.expectedHeads, [prior.revision]);
        expect(corrected.document.review, isA<OcrReviewRecord>());
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = null;
        store = _ObservedStore(await ReceiptRepository.open(file));
        final reopened = store;
        expect(
          (await store.repository.history()).single.document.sha256Hex,
          corrected.document.sha256Hex,
        );
        await store.repository.verifyIntegrity();
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => reopened),
        );
        await tester.pumpAndSettle();
        evidence = await _pixels(OcrFixture().draft.parseContext!.page);
        await _open(tester, reopened, corrected, evidence);
        final concurrent = _concurrent(
          corrected,
          (await store.repository.branches()).single,
        );
        await store.repository.saveOcr(concurrent);
        await tap(tester, 'ocr-confirm-save', scroll: false);
        await expectLater(
          store.lastWrite,
          throwsA(
            isA<StorageFailure>().having((e) => e.code, 'code', 'staleReceipt'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ocr-retry-save')), findsNothing);
        expect(
          find.textContaining('Tätä korjausta ei tallennettu.'),
          findsOneWidget,
        );
        await tap(tester, 'ocr-close-pending', scroll: false);
        expect(evidence.isDisposed, isTrue);
        expect(
          (await store.repository.history()).single.document.sha256Hex,
          concurrent.document.sha256Hex,
        );
        await store.repository.verifyIntegrity();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        evidence?.dispose();
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('ocr-correction-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
