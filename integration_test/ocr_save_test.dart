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

class ObservedStore implements LocalStore {
  ObservedStore(this.repository);
  final ReceiptRepository repository;
  Future<void>? closing;
  @override
  Future<List<ReceiptBranch>> branches() => repository.branches();
  @override
  Future<List<StoredReceipt>> history({
    int limit = 30,
    int offset = 0,
    HistoryFilter? filter,
  }) => repository.history(limit: limit, offset: offset, filter: filter);
  @override
  Future<SaveResult> saveManual(ReviewedReceipt c) => repository.saveManual(c);
  @override
  Future<SaveResult> saveOcr(ReviewedReceipt c) => repository.saveOcr(c);
  @override
  Future<SaveResult> deleteReceipt(ReviewedReceiptDeletion command) =>
      repository.deleteReceipt(command);
  @override
  Future<void> close() => closing ??= repository.close();
}

Future<void> visible(WidgetTester tester, String key) async {
  final scroll = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  // A drag through the narrow image preview pans the InteractiveViewer. Move
  // the review list directly so this smoke test can reach offscreen fields.
  final position = tester.state<ScrollableState>(scroll).position;
  for (
    var attempt = 0;
    attempt < 80 && find.byKey(Key(key)).evaluate().isEmpty;
    attempt++
  ) {
    position.jumpTo((position.pixels + 180).clamp(0, position.maxScrollExtent));
    await tester.pumpAndSettle();
  }
  expect(find.byKey(Key(key)), findsOneWidget);
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key, {bool scroll = true}) async {
  if (scroll) await visible(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reviewed synthetic OCR saves offline and survives native reopen',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        '${support.path}/ocr-ui-smoke-${DurableId.generate().value}',
      );
      await directory.create();
      ObservedStore? store;
      ReceiptEvidence? evidence;
      try {
        final file = File('${directory.path}/receipts.sqlite');
        store = ObservedStore(await ReceiptRepository.open(file));
        final initial = store;
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => initial),
        );
        await tester.pumpAndSettle();
        final words = [
          OcrWord('16.11.2026', PixelBox(10, 10, 150, 26)),
          OcrWord('MILK', PixelBox(10, 70, 150, 86)),
          OcrWord('2,00', PixelBox(400, 70, 480, 86)),
          OcrWord('YHTEENSÄ', PixelBox(10, 220, 200, 236)),
          OcrWord('2,00', PixelBox(400, 220, 480, 236)),
        ];
        // Synthetic source pixels and seeded geometry test saving, not recognition accuracy.
        final recorder = ui.PictureRecorder();
        final actualCanvas = ui.Canvas(recorder);
        actualCanvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
        for (final word in words) {
          final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
            ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
            ..addText(word.text);
          final paragraph = b.build()
            ..layout(const ui.ParagraphConstraints(width: 480));
          actualCanvas.drawParagraph(
            paragraph,
            ui.Offset(word.box.left, word.box.top),
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(500, 500);
        picture.dispose();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        evidence = await ReceiptEvidence.decode(data!.buffer.asUint8List());
        final draft = parseReceipt(
          OcrPage(500, 500, words),
          itemTop: 40,
          priceColumnLeft: 350,
        );
        Navigator.of(
          tester.element(find.byKey(const Key('open-history'))),
        ).push(
          MaterialPageRoute<bool>(
            builder: (_) =>
                ReviewPage(draft: draft, evidence: evidence, store: initial),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'ocr-branch');
        await tester.tap(find.text('Luo uusi toimipiste').last);
        await tester.pumpAndSettle();
        await visible(tester, 'branch');
        await tester.enterText(
          find.byKey(const Key('branch')),
          'SYNTHETIC OCR BRANCH',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text('Olen tarkistanut myymälän toimipisteen'),
        );
        await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
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
          await tap(tester, key, scroll: false);
        }
        await tester.ensureVisible(find.byKey(const Key('page-evidence-note')));
        await tester.enterText(
          find.byKey(const Key('page-evidence-note')),
          'Compared synthetic source',
        );
        await tester.pumpAndSettle();
        await tap(tester, 'approve-page-evidence', scroll: false);
        await tap(tester, 'review-confirmation');
        await tap(tester, 'ocr-save');
        await tap(tester, 'ocr-save-date', scroll: false);
        await tap(tester, 'ocr-save-total', scroll: false);
        await tap(tester, 'ocr-confirm-save', scroll: false);
        expect(evidence.isDisposed, isTrue);
        final saved = (await store.repository.history()).single;
        expect(saved.document.review, isA<OcrReviewRecord>());
        expect(saved.document.snapshot.items.single.rawName, 'MILK');
        await tester.pumpWidget(const SizedBox());
        await store.close();
        store = null;
        store = ObservedStore(await ReceiptRepository.open(file));
        final reopened = store;
        expect(
          (await store.repository.history()).single.document.sha256Hex,
          saved.document.sha256Hex,
        );
        await store.repository.verifyIntegrity();
        await tester.pumpWidget(
          ReceiptReaderApp(storageOpener: () async => reopened),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('open-history')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SYNTHETIC OCR BRANCH'));
        await tester.pumpAndSettle();
        expect(find.text('MILK'), findsOneWidget);
        expect(find.text('16.11.2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        evidence?.dispose();
        await store?.close();
        if (directory.parent.absolute.path != support.absolute.path ||
            !directory.path.contains('ocr-ui-smoke-')) {
          throw StateError('unexpected_smoke_directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
