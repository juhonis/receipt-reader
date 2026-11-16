import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import 'support/fake_store.dart';

void main() {
  Future<void> visible(WidgetTester tester, String key) async {
    final vertical = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    tester.state<ScrollableState>(vertical).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(Key(key)),
      160,
      scrollable: vertical,
    );
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<ReceiptEvidence> open(WidgetTester tester, FakeStore store) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    final draft = parseReceipt(
      OcrPage(8, 12, [
        OcrWord('16.11.2026', PixelBox(.5, .5, 3, 1)),
        OcrWord('MILK', PixelBox(.5, 3, 3, 3.5)),
        OcrWord('2,00', PixelBox(6, 3, 7.5, 3.5)),
        OcrWord('YHTEENSÄ', PixelBox(.5, 6, 3, 6.5)),
        OcrWord('2,00', PixelBox(6, 6, 7.5, 6.5)),
      ]),
      itemTop: 2,
      priceColumnLeft: 5,
    );
    await tester.pumpWidget(const ReceiptReaderApp());
    Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ReviewPage(draft: draft, evidence: evidence, store: store),
      ),
    );
    await tester.pumpAndSettle();
    await visible(tester, 'ocr-branch');
    await tester.tap(find.byKey(const Key('ocr-branch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(store.branch.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
    await tester.pumpAndSettle();
    return evidence;
  }

  Future<void> approve(WidgetTester tester) async {
    await visible(tester, 'row-image-compared-0');
    await tester.tap(find.byKey(const Key('row-image-compared-0')));
    await tester.pumpAndSettle();
    await visible(tester, 'review-page-evidence');
    await tester.tap(find.byKey(const Key('review-page-evidence')));
    await tester.pumpAndSettle();
    for (final key in [
      'page-header',
      'page-footer',
      'page-layout',
      'page-complete-image',
    ]) {
      await tester.tap(find.byKey(Key(key)));
    }
    await tester.enterText(
      find.byKey(const Key('page-evidence-note')),
      'PRIVATE TEST NOTE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve-page-evidence')));
    await tester.pumpAndSettle();
    await visible(tester, 'review-confirmation');
    await tester.tap(find.byKey(const Key('review-confirmation')));
    await tester.pumpAndSettle();
  }

  Future<void> finalSave(WidgetTester tester) async {
    await visible(tester, 'ocr-save');
    await tester.tap(find.byKey(const Key('ocr-save')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ocr-confirm-save')))
          .onPressed,
      isNull,
    );
    for (final key in ['ocr-save-date', 'ocr-save-total']) {
      await tester.tap(find.byKey(Key(key)));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ocr-confirm-save')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'OCR save requires live review and final fields, preserves source and disposes image',
    (tester) async {
      final store = FakeStore();
      final evidence = await open(tester, store);
      await visible(tester, 'ocr-save');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ocr-save')))
            .onPressed,
        isNull,
      );
      await approve(tester);
      await finalSave(tester);
      expect(store.saved, hasLength(1));
      expect(store.saved.single.document.review, isA<OcrReviewRecord>());
      expect(
        store.saved.single.document.snapshot.branch.revision,
        store.branch.revision,
      );
      expect(store.saved.single.document.snapshot.items.single.rawName, 'MILK');
      expect(
        ReceiptDocumentCodec.encode(store.saved.single.document),
        isNot(contains('PRIVATE TEST NOTE')),
      );
      expect(evidence.isDisposed, isTrue);
      expect(find.byType(ReviewPage), findsNothing);
    },
  );
  testWidgets(
    'uncertain OCR save retries identical command and prevents returning to editable review',
    (tester) async {
      final store = FakeStore()..failSaveAfterCommit = true;
      final evidence = await open(tester, store);
      await approve(tester);
      await finalSave(tester);
      expect(store.saved, hasLength(1));
      expect(evidence.isDisposed, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr-retry-save')), findsOneWidget);
      store.failSaveAfterCommit = false;
      await tester.tap(find.byKey(const Key('ocr-retry-save')));
      await tester.pumpAndSettle();
      expect(store.saved, hasLength(2));
      expect(identical(store.saved.first, store.saved.last), isTrue);
      expect(store.documents, hasLength(1));
      expect(evidence.isDisposed, isTrue);
    },
  );
  testWidgets(
    'explicit close after uncertain OCR save releases evidence and exits review',
    (tester) async {
      final store = FakeStore()..failSaveAfterCommit = true;
      final evidence = await open(tester, store);
      await approve(tester);
      await finalSave(tester);
      await tester.tap(find.byKey(const Key('ocr-close-pending')));
      await tester.pumpAndSettle();
      expect(evidence.isDisposed, isTrue);
      expect(store.saved, hasLength(1));
      expect(find.byType(ReviewPage), findsNothing);
    },
  );
  testWidgets(
    'changing content during final OCR confirmation rejects visibly',
    (tester) async {
      final store = FakeStore();
      final evidence = await open(tester, store);
      await approve(tester);
      await visible(tester, 'ocr-save');
      await tester.tap(find.byKey(const Key('ocr-save')));
      await tester.pumpAndSettle();
      tester.widget<TextField>(find.byKey(const Key('date'))).controller!.text =
          '17.11.2026';
      for (final key in ['ocr-save-date', 'ocr-save-total']) {
        await tester.tap(find.byKey(Key(key)));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ocr-confirm-save')));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      expect(
        find.byKey(const Key('ocr-save-preparation-error')),
        findsOneWidget,
      );
      expect(evidence.isDisposed, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(evidence.isDisposed, isTrue);
    },
  );
  testWidgets(
    'cancelling final confirmation does not save and normal exit disposes evidence',
    (tester) async {
      final store = FakeStore();
      final evidence = await open(tester, store);
      await approve(tester);
      await visible(tester, 'ocr-save');
      await tester.tap(find.byKey(const Key('ocr-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Peruuta'));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      expect(evidence.isDisposed, isFalse);
      Navigator.of(tester.element(find.byType(ReviewPage))).pop();
      await tester.pumpAndSettle();
      expect(evidence.isDisposed, isTrue);
    },
  );
}
