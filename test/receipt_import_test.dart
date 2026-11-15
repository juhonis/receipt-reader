import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show BackButton;
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/receipt_import.dart';

void main() {
  testWidgets('late picker result is disposed after its screen is removed', (
    tester,
  ) async {
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    final pending = Completer<ReceiptEvidence?>();
    await tester.pumpWidget(
      ReceiptReaderApp(imagePicker: () => pending.future),
    );
    await tester.tap(find.text('Avaa kuittikuva'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(evidence);
    await tester.pump();
    expect(evidence.isDisposed, isTrue);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  final unreadable = isA<ReceiptImportException>().having(
    (e) => e.failure,
    'reason',
    ImportFailure.unreadable,
  );
  final unsupported = isA<ReceiptImportException>().having(
    (e) => e.failure,
    'reason',
    ImportFailure.unsupported,
  );
  final tooLarge = isA<ReceiptImportException>().having(
    (e) => e.failure,
    'reason',
    ImportFailure.tooLarge,
  );

  test(
    'rejects unsupported, corrupt and oversized input before review',
    () async {
      await expectLater(
        ReceiptEvidence.decode(Uint8List.fromList([1, 2, 3])),
        throwsA(unsupported),
      );
      await expectLater(
        ReceiptEvidence.decode(Uint8List.fromList([255, 216, 255, 0])),
        throwsA(unreadable),
      );
      await expectLater(
        ReceiptEvidence.decode(Uint8List(ReceiptEvidence.maxBytes + 1)),
        throwsA(tooLarge),
      );
      await expectLater(
        ReceiptEvidence.decode(
          await File('test/fixtures/oversized.png').readAsBytes(),
        ),
        throwsA(tooLarge),
      );
    },
  );

  test(
    'JPEG orientation is honored and pixels have explicit lifetime',
    () async {
      final evidence = await ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      );
      expect(evidence.image.width, 8);
      expect(evidence.image.height, 12);
      evidence.dispose();
      evidence.dispose();
      expect(evidence.isDisposed, isTrue);
    },
  );

  testWidgets('import shows route-owned evidence and releases it on back', (
    tester,
  ) async {
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    await tester.pumpWidget(
      ReceiptReaderApp(imagePicker: () async => evidence),
    );
    await tester.tap(find.text('Avaa kuittikuva'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('receipt-evidence')), findsOneWidget);
    expect(evidence.isDisposed, isFalse);
    expect(PaintingBinding.instance.imageCache.currentSize, 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(evidence.isDisposed, isTrue);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancellation and failure keep the home screen usable', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      ReceiptReaderApp(
        imagePicker: () async {
          if (fail) throw const ReceiptImportException(ImportFailure.tooLarge);
          return null;
        },
      ),
    );
    await tester.tap(find.text('Avaa kuittikuva'));
    await tester.pumpAndSettle();
    expect(find.text('Kuitin tarkistus'), findsNothing);
    fail = true;
    await tester.tap(find.text('Avaa kuittikuva'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kuva on liian suuri'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('desktop preview stays beside review fields', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final evidence = (await tester.runAsync(
      () async => ReceiptEvidence.decode(
        await File('test/fixtures/rotated.jpg').readAsBytes(),
      ),
    ))!;
    await tester.pumpWidget(
      ReceiptReaderApp(imagePicker: () async => evidence),
    );
    await tester.tap(find.text('Avaa kuittikuva'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('branch'))).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const Key('receipt-evidence'))).dx - 1,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(evidence.isDisposed, isTrue);
  });
}
