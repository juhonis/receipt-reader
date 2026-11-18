import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_reader/windows_ocr.dart';

const header =
    'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext';
String page([String rows = '']) =>
    '$header\n1\t1\t0\t0\t0\t0\t0\t0\t100\t100\t-1\t\n$rows';
String word(
  String text, {
  int left = 10,
  int top = 10,
  int width = 20,
  int height = 10,
  int paragraph = 1,
  int line = 1,
}) =>
    '5\t1\t1\t$paragraph\t$line\t1\t$left\t$top\t$width\t$height\t93.5\t$text\n';
void main() {
  test('preserves signed amounts, diacritics and native word coordinates', () {
    final result = parseWindowsOcrTsv(
      page(word('Ääni') + word('-1,25', left: 65)),
      100,
      100,
    );
    expect(result.words.map((w) => w.text), ['Ääni', '-1,25']);
    expect(result.words.last.box.left, 65);
    expect(result.words.last.box.right, 85);
    expect(result.baselineSlope, 0);
  });
  test('a blank page is valid, missing or multiple pages are not', () {
    expect(parseWindowsOcrTsv(page(), 100, 100).words, isEmpty);
    expect(
      () => parseWindowsOcrTsv('$header\n', 100, 100),
      throwsFormatException,
    );
    expect(
      () => parseWindowsOcrTsv(page() + page().split('\n')[1], 100, 100),
      throwsFormatException,
    );
  });
  test(
    'malformed, out of bounds or mismatched output never yields partial rows',
    () {
      for (final invalid in [
        page(word('FIRST') + word('bad', left: 95)),
        page(word('bad', left: -1)),
        page(word('bad', width: 0)),
        page(word('bad', height: 0)),
        page(word('bad', top: 95)),
        page(word('bad')).replaceFirst('100\t100', '101\t100'),
        page(word('bad')).replaceFirst('5\t1', '5\t2'),
        page(word('bad')).replaceFirst('93.5\t', '93.5\tEXTRA\t'),
        'plain OCR text',
        page(word('bad\u0000text')),
      ]) {
        expect(
          () => parseWindowsOcrTsv(invalid, 100, 100),
          throwsFormatException,
        );
      }
    },
  );
  test('paragraph-scoped line IDs do not invent a skewed shared line', () {
    final rows = StringBuffer();
    for (var i = 0; i < 6; i++) {
      rows.write(word('LEFT', left: 10, top: 5 + i * 12, paragraph: i + 1));
      rows.write(word('RIGHT', left: 65, top: 5 + i * 12, paragraph: i + 1));
    }
    final result = parseWindowsOcrTsv(page(rows.toString()), 100, 100);
    expect(result.words, hasLength(12));
    expect(result.baselineSlope, 0);
  });
  test(
    'invalid image dimensions and byte lengths fail before starting a worker',
    () async {
      for (final size in [(0, 1), (1, 0), (12001, 1), (10000, 10000), (2, 2)]) {
        final task = WindowsOcrTask(Uint8List(4), size.$1, size.$2);
        await expectLater(
          task.result,
          throwsA(
            isA<WindowsOcrException>().having(
              (e) => e.code,
              'code',
              'invalidImage',
            ),
          ),
        );
        expect(task.processId, isNull);
      }
    },
  );
  test('missing, oversized and wrong-version bundle manifests fail with a sanitized status', () async {
    final dir = await Directory.systemTemp.createTemp('ocr-bundle-test-');
    try {
      for (final content in [
        null,
        'x' * 65537,
        jsonEncode({'schemaVersion': 99}),
      ]) {
        if (content != null) {
          await File('${dir.path}/manifest.json').writeAsString(content);
        }
        await expectLater(
          validateWindowsOcrBundle(dir),
          throwsA(
            isA<WindowsOcrException>().having(
              (e) => e.toString(),
              'message',
              'WindowsOcrException(bundle)',
            ),
          ),
        );
      }
    } finally {
      if (dir.parent.absolute.path != Directory.systemTemp.absolute.path ||
          !dir.path.contains('ocr-bundle-test-')) {
        throw StateError('unexpected_test_directory');
      }
      await dir.delete(recursive: true);
    }
  });
}
