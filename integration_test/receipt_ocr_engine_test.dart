import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_reader/windows_ocr.dart';

import 'ocr_save_test.dart' show runOcrSaveSmoke;

void main() {
  runOcrSaveSmoke(recognizeWithEngine: true);
  if (Platform.isWindows) {
    testWidgets(
      'native worker cancels and times out without exposing subprocess data',
      (tester) async {
        final pixels = Uint8List(1000 * 1000 * 4)
          ..fillRange(0, 1000 * 1000 * 4, 255);
        final task = WindowsOcrTask(pixels, 1000, 1000);
        final checked = expectLater(
          task.result,
          throwsA(
            isA<WindowsOcrException>().having(
              (e) => e.code,
              'code',
              'cancelled',
            ),
          ),
        );
        for (var i = 0; i < 500 && task.processId == null; i++) {
          await tester.pump(const Duration(milliseconds: 2));
        }
        expect(task.processId, isNotNull);
        task.cancel();
        await checked;
        await task.stopped;
        final timed = WindowsOcrTask(
          pixels,
          1000,
          1000,
          timeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          timed.result,
          throwsA(
            isA<WindowsOcrException>().having((e) => e.code, 'code', 'timeout'),
          ),
        );
        await timed.stopped;
        final again = await WindowsOcrTask(pixels, 1000, 1000).result;
        expect(again.words, isEmpty);
      },
    );
  }
}
