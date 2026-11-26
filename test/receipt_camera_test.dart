import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('receipt_reader/import');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'camera bridge decodes JPEG orientation without a path or image cache',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'captureImage');
        expect(call.arguments, isNull);
        return File('test/fixtures/rotated.jpg').readAsBytes();
      });
      final evidence = await captureReceiptImage();
      expect(evidence!.image.width, 8);
      expect(evidence.image.height, 12);
      expect(PaintingBinding.instance.imageCache.currentSize, 0);
      evidence.dispose();
      expect(evidence.isDisposed, isTrue);
    },
  );

  test(
    'camera cancellation and sanitized permission/device errors are distinct',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await captureReceiptImage(), isNull);
      for (final entry in {
        'camera_denied': ImportFailure.cameraDenied,
        'camera_unavailable': ImportFailure.cameraUnavailable,
        'capture_failed': ImportFailure.captureFailed,
        'too_large': ImportFailure.tooLarge,
      }.entries) {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: entry.key, message: 'PRIVATE DETAIL');
        });
        await expectLater(
          captureReceiptImage(),
          throwsA(
            isA<ReceiptImportException>().having(
              (error) => error.failure,
              'failure',
              entry.value,
            ),
          ),
        );
      }
    },
  );

  testWidgets('camera opens review and disposes evidence when review closes', (
    tester,
  ) async {
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    var galleryCalls = 0;
    await tester.pumpWidget(
      ReceiptReaderApp(
        cameraCapture: () async => evidence,
        imagePicker: () async {
          galleryCalls++;
          return null;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('capture-receipt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('receipt-evidence')), findsOneWidget);
    expect(galleryCalls, 0);
    expect(evidence.isDisposed, isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(evidence.isDisposed, isTrue);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and denied permission leave capture and gallery usable', (
    tester,
  ) async {
    var denied = false;
    await tester.pumpWidget(
      ReceiptReaderApp(
        cameraCapture: () async {
          if (denied) {
            throw const ReceiptImportException(ImportFailure.cameraDenied);
          }
          return null;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('capture-receipt')));
    await tester.pumpAndSettle();
    denied = true;
    await tester.tap(find.byKey(const Key('capture-receipt')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kameran käyttö on estetty'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('capture-receipt')))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Avaa kuittikuva'), findsOneWidget);
  });

  testWidgets('late camera result is released when the app route is removed', (
    tester,
  ) async {
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    final pending = Completer<ReceiptEvidence?>();
    await tester.pumpWidget(
      ReceiptReaderApp(cameraCapture: () => pending.future),
    );
    await tester.tap(find.byKey(const Key('capture-receipt')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(evidence);
    await tester.pump();
    expect(evidence.isDisposed, isTrue);
  });

  testWidgets(
    'Windows retains image import and hides unsupported camera action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(const ReceiptReaderApp());
      expect(find.byKey(const Key('capture-receipt')), findsNothing);
      expect(find.text('Avaa kuittikuva'), findsOneWidget);
    },
  );
}
