import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_storage/receipt_storage.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/history_page.dart';
import 'package:receipt_reader/ocr_correction_page.dart';
import 'package:receipt_reader/receipt_import.dart';
import 'package:receipt_reader/review_page.dart';

import 'support/fake_store.dart';

void main() {
  StoredReceipt original(FakeStore store) {
    final result = StoredReceipt(
      ReceiptDocumentCodec.decode(
        File('packages/receipt_domain/test/fixtures/ocr_document_v1.json')
            .readAsStringSync()
            .trim(),
      ),
      RevisionId(store.branch.revision!.origin, BigInt.two),
    );
    store.documents.add(result);
    return result;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 250);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    FakeStore store,
    Future<ReceiptEvidence?> Function() picker,
  ) async {
    await tester.pumpWidget(
      ReceiptReaderApp(storageOpener: () async => store, imagePicker: picker),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'open-history');
    await tester.tap(
      find.text(store.documents.single.document.snapshot.branch.name),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'edit-ocr-receipt');
  }

  Future<ReceiptEvidence> pixels(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => ReceiptEvidence.decode(
          await File('test/fixtures/rotated.jpg').readAsBytes(),
        ),
      ))!;

  testWidgets(
    'manual receipts cannot enter either OCR correction entry point',
    (tester) async {
      final store = FakeStore();
      final manual = StoredReceipt(
        ReceiptDocumentCodec.decode(
          File('packages/receipt_domain/test/fixtures/manual_document_v1.json')
              .readAsStringSync()
              .trim(),
        ),
        store.branch.revision!,
      );
      final evidence = await pixels(tester);
      try {
        expect(
          () => OcrCorrectionPage(store: store, receipt: manual),
          throwsArgumentError,
        );
        expect(
          () => ReviewPage.correction(
            store: store,
            receipt: manual,
            evidence: evidence,
          ),
          throwsArgumentError,
        );
      } finally {
        evidence.dispose();
      }
    },
  );

  testWidgets(
    'history forwards picker, cancellation writes nothing, and original-image confirmation is required',
    (tester) async {
      final store = FakeStore();
      original(store);
      var calls = 0;
      await open(tester, store, () async {
        calls++;
        return null;
      });
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ocr-correction-image')))
            .onPressed,
        isNull,
      );
      await tap(tester, 'ocr-correction-original');
      await tap(tester, 'ocr-correction-image');
      expect(calls, 1);
      expect(find.byType(OcrCorrectionPage), findsOneWidget);
      expect(store.saved, isEmpty);
      Navigator.of(tester.element(find.byType(OcrCorrectionPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptDetailPage), findsOneWidget);
    },
  );

  testWidgets(
    'history forwards camera capture and requires the original receipt',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = FakeStore();
      original(store);
      var captures = 0;
      await tester.pumpWidget(
        ReceiptReaderApp(
          storageOpener: () async => store,
          cameraCapture: () async {
            captures++;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'open-history');
      await tester.tap(
        find.text(store.documents.single.document.snapshot.branch.name),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'edit-ocr-receipt');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('ocr-correction-camera')),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'ocr-correction-original');
      await tap(tester, 'ocr-correction-camera');
      expect(captures, 1);
      expect(store.saved, isEmpty);
      expect(find.byType(OcrCorrectionPage), findsOneWidget);
    },
  );

  testWidgets(
    'import failures stay recoverable without exposing exception details',
    (tester) async {
      final store = FakeStore();
      original(store);
      var calls = 0;
      await open(tester, store, () async {
        calls++;
        if (calls == 1) {
          throw const ReceiptImportException(ImportFailure.tooLarge);
        }
        throw StateError('PRIVATE FILE PATH');
      });
      await tap(tester, 'ocr-correction-original');
      await tap(tester, 'ocr-correction-image');
      expect(find.textContaining('20 Mt'), findsOneWidget);
      await tap(tester, 'ocr-correction-image');
      expect(calls, 2);
      expect(find.textContaining('PRIVATE FILE PATH'), findsNothing);
      expect(store.saved, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ocr-correction-image')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'cancelled fresh review disposes its pixels and keeps saved detail',
    (tester) async {
      final store = FakeStore();
      original(store);
      final evidence = await pixels(tester);
      await open(tester, store, () async => evidence);
      await tap(tester, 'ocr-correction-original');
      await tap(tester, 'ocr-correction-image');
      expect(find.byType(ReviewPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReviewPage))).pop();
      await tester.pumpAndSettle();
      expect(evidence.isDisposed, isTrue);
      expect(store.saved, isEmpty);
      expect(find.byType(OcrCorrectionPage), findsOneWidget);
    },
  );

  testWidgets(
    'late picker result is disposed after leaving the correction route',
    (tester) async {
      final store = FakeStore();
      original(store);
      final evidence = await pixels(tester);
      final pending = Completer<ReceiptEvidence?>();
      await open(tester, store, () => pending.future);
      await tap(tester, 'ocr-correction-original');
      await tap(tester, 'ocr-correction-image');
      Navigator.of(tester.element(find.byType(OcrCorrectionPage))).pop();
      await tester.pumpAndSettle();
      pending.complete(evidence);
      await tester.pumpAndSettle();
      expect(evidence.isDisposed, isTrue);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'completed correction returns to refreshed history while cancelled review does not',
    (tester) async {
      final store = FakeStore();
      original(store);
      final evidence = await pixels(tester);
      await open(tester, store, () async => evidence);
      final calls = store.historyCalls;
      await tap(tester, 'ocr-correction-original');
      await tap(tester, 'ocr-correction-image');
      Navigator.of(tester.element(find.byType(ReviewPage))).pop(true);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptDetailPage), findsNothing);
      expect(find.byType(OcrCorrectionPage), findsNothing);
      expect(find.byType(HistoryPage), findsOneWidget);
      expect(store.historyCalls, calls + 1);
      expect(store.historyOffsets.last, 0);
      expect(evidence.isDisposed, isTrue);
    },
  );
}
