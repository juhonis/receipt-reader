import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
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
    final position = tester.state<ScrollableState>(vertical).position;
    for (
      var attempt = 0;
      attempt < 100 && find.byKey(Key(key)).evaluate().isEmpty;
      attempt++
    ) {
      position.jumpTo(
        (position.pixels + 160).clamp(0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byKey(Key(key)), findsOneWidget);
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<ReceiptEvidence> open(
    WidgetTester tester,
    FakeStore store, {
    StoredReceipt? correction,
    int rows = 1,
  }) async {
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
        if (rows == 2) ...[
          OcrWord('BREAD', PixelBox(.5, 4, 3, 4.5)),
          OcrWord('2,00', PixelBox(6, 4, 7.5, 4.5)),
        ],
        OcrWord('YHTEENSÄ', PixelBox(.5, 6, 3, 6.5)),
        OcrWord(rows == 1 ? '2,00' : '4,00', PixelBox(6, 6, 7.5, 6.5)),
      ]),
      itemTop: 2,
      priceColumnLeft: 5,
    );
    await tester.pumpWidget(const ReceiptReaderApp());
    Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
      MaterialPageRoute<bool>(
        builder: (_) => correction == null
            ? ReviewPage(draft: draft, evidence: evidence, store: store)
            : ReviewPage.correction(
                draft: draft,
                evidence: evidence,
                store: store,
                receipt: correction,
              ),
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

  Future<void> approve(WidgetTester tester, {int rows = 1}) async {
    for (var i = 0; i < rows; i++) {
      await visible(tester, 'row-image-compared-$i');
      await tester.tap(find.byKey(Key('row-image-compared-$i')));
      await tester.pumpAndSettle();
    }
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

  StoredReceipt original(FakeStore store, {int rows = 1}) {
    final json = jsonDecode(
      File('packages/receipt_domain/test/fixtures/ocr_document_v1.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    if (rows == 2) {
      final item = Map<String, dynamic>.from(json['receipt']['items'][0]);
      item['id'] = '00000000-0000-4000-8000-000000000004';
      item['position'] = '1';
      item['name'] = 'BREAD';
      item['raw_name'] = 'BREAD';
      item['normalized_name'] = 'bread';
      json['receipt']['items'].add(item);
      json['receipt']['total_cents'] = '400';
      json['review']['reviewed_row_ids'].add(item['id']);
      json['review']['ocr_evidence']['original_row_ids'].add(item['id']);
    }
    final result = StoredReceipt(
      ReceiptDocumentCodec.decode(jsonEncode(json)),
      RevisionId(store.branch.revision!.origin, BigInt.from(2)),
    );
    store.documents.add(result);
    return result;
  }

  Future<void> matchRow(WidgetTester tester, int row, String label) async {
    await visible(tester, 'ocr-row-identity-$row');
    await tester.tap(find.byKey(Key('ocr-row-identity-$row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> correctionFinal(WidgetTester tester) async {
    await visible(tester, 'ocr-save');
    await tester.tap(find.byKey(const Key('ocr-save')));
    await tester.pumpAndSettle();
    for (final key in ['ocr-save-date', 'ocr-save-total']) {
      final checkbox = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ocr-confirm-save')))
          .onPressed,
      isNull,
    );
    final identities = find.descendant(
      of: find.byKey(const Key('ocr-save-identities')),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(identities);
    await tester.pumpAndSettle();
    await tester.tap(identities);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ocr-confirm-save')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'OCR correction requires fresh evidence and explicit matching, retains receipt and row identity',
    (tester) async {
      final store = FakeStore();
      final prior = original(store);
      final evidence = await open(tester, store, correction: prior);
      await approve(tester);
      await visible(tester, 'ocr-save');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ocr-save')))
            .onPressed,
        isNull,
      );
      await matchRow(tester, 0, '1. MILK (2,00 €)');
      // Matching is a review edit: fresh comparisons and whole-page approval are required.
      await approve(tester);
      await correctionFinal(tester);
      final saved = store.documents.single;
      expect(saved.document.snapshot.id, prior.document.snapshot.id);
      expect(
        saved.document.snapshot.items.single.id,
        prior.document.snapshot.items.single.id,
      );
      expect(saved.document.review.expectedHeads, [prior.revision]);
      expect(saved.document.review, isA<OcrReviewRecord>());
      expect(saved.revision, isNot(prior.revision));
      expect(evidence.isDisposed, isTrue);
    },
  );

  testWidgets(
    'OCR correction explicitly removes unmatched rows and allocates a fresh new row',
    (tester) async {
      final store = FakeStore();
      final prior = original(store, rows: 2);
      await open(tester, store, correction: prior);
      await matchRow(tester, 0, 'Uusi rivi');
      await approve(tester);
      await visible(tester, 'ocr-save');
      await tester.tap(find.byKey(const Key('ocr-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Uudesta versiosta poistuvat tallennetut rivit:'),
        findsOneWidget,
      );
      expect(find.text('1. MILK (2,00 €)'), findsOneWidget);
      expect(find.text('2. BREAD (2,00 €)'), findsOneWidget);
      await tester.tap(find.text('Peruuta'));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      await correctionFinal(tester);
      final row = store.documents.single.document.snapshot.items.single;
      expect(
        prior.document.snapshot.items.map((r) => r.id),
        isNot(contains(row.id)),
      );
      expect(row.rawName, 'MILK');
      expect(
        store.documents.single.document.snapshot.id,
        prior.document.snapshot.id,
      );
    },
  );

  testWidgets(
    'OCR correction prevents duplicate retained identities and supports reordered source rows',
    (tester) async {
      final store = FakeStore();
      final prior = original(store, rows: 2);
      await open(tester, store, correction: prior, rows: 2);
      await matchRow(tester, 0, '2. BREAD (2,00 €)');
      await visible(tester, 'ocr-row-identity-1');
      await tester.tap(find.byKey(const Key('ocr-row-identity-1')));
      await tester.pumpAndSettle();
      // The first row's chosen saved identity cannot be assigned again.
      expect(find.text('2. BREAD (2,00 €)'), findsOneWidget);
      await tester.tap(find.text('1. MILK (2,00 €)').last);
      await tester.pumpAndSettle();
      await approve(tester, rows: 2);
      await correctionFinal(tester);
      expect(
        store.documents.single.document.snapshot.items.map((r) => r.id),
        prior.document.snapshot.items.reversed.map((r) => r.id),
      );
    },
  );

  for (final code in ['staleReceipt', 'staleBranch']) {
    testWidgets('OCR correction $code blocks retry and exits to refresh', (
      tester,
    ) async {
      final store = FakeStore()..saveFailure = code;
      final prior = original(store);
      final evidence = await open(tester, store, correction: prior);
      await matchRow(tester, 0, '1. MILK (2,00 €)');
      await approve(tester);
      await correctionFinal(tester);
      expect(find.byKey(const Key('ocr-retry-save')), findsNothing);
      expect(
        find.textContaining('Tätä korjausta ei tallennettu.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ocr-close-pending')));
      await tester.pumpAndSettle();
      expect(evidence.isDisposed, isTrue);
      expect(store.documents.single.revision, prior.revision);
    });
  }

  testWidgets(
    'uncertain OCR correction retries the identical revision-bound command once',
    (tester) async {
      final store = FakeStore()..failSaveAfterCommit = true;
      final prior = original(store);
      final evidence = await open(tester, store, correction: prior);
      await matchRow(tester, 0, '1. MILK (2,00 €)');
      await approve(tester);
      await correctionFinal(tester);
      final first = store.saved.single;
      store.failSaveAfterCommit = false;
      await tester.tap(find.byKey(const Key('ocr-retry-save')));
      await tester.pumpAndSettle();
      expect(identical(store.saved.last, first), isTrue);
      expect(store.documents, hasLength(1));
      expect(evidence.isDisposed, isTrue);
    },
  );

  testWidgets(
    'layout re-review keeps OCR correction identity and resets approvals and row mapping',
    (tester) async {
      final store = FakeStore();
      final prior = original(store);
      final evidence = await open(tester, store, correction: prior);
      await matchRow(tester, 0, '1. MILK (2,00 €)');
      await visible(tester, 'inspect-layout');
      await tester.tap(find.byKey(const Key('inspect-layout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preview-layout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-layout-review')));
      await tester.pumpAndSettle();
      final fresh = tester.widget<ReviewPage>(find.byType(ReviewPage));
      expect(fresh.evidence, isNot(same(evidence)));
      await visible(tester, 'ocr-branch');
      await tester.tap(find.byKey(const Key('ocr-branch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(store.branch.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Olen tarkistanut myymälän toimipisteen'));
      await tester.pumpAndSettle();
      await visible(tester, 'ocr-row-identity-0');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('ocr-row-identity-0')),
            )
            .initialValue,
        isNull,
      );
      await matchRow(tester, 0, '1. MILK (2,00 €)');
      await approve(tester);
      await correctionFinal(tester);
      expect(
        store.documents.single.document.snapshot.id,
        prior.document.snapshot.id,
      );
      expect(store.documents.single.document.review.expectedHeads, [
        prior.revision,
      ]);
      expect(fresh.evidence!.isDisposed, isTrue);
      expect(evidence.isDisposed, isTrue);
      expect(find.byType(ReviewPage), findsNothing);
    },
  );

  testWidgets(
    'OCR correction final confirmation fits a narrow screen with enlarged text',
    (tester) async {
      final store = FakeStore();
      final prior = original(store, rows: 2);
      await open(tester, store, correction: prior);
      await matchRow(tester, 0, '1. MILK (2,00 €)');
      await approve(tester);
      final binding = tester.binding;
      binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(binding.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      await correctionFinal(tester);
      expect(
        store.documents.single.document.snapshot.items.single.id,
        prior.document.snapshot.items.first.id,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
