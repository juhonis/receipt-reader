import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:receipt_parser/receipt_parser.dart';

/// Sanitized status only: never includes OCR text, subprocess output or paths.
final class WindowsOcrException implements Exception {
  const WindowsOcrException(this.code);
  final String code;
  @override
  String toString() => 'WindowsOcrException($code)';
}

const _modelHashes = {
  'fin': '61a04cd62b507c3d9ae0e1cda399e6715ebf49dea9df47897c8acdcd3bd3e13c',
  'eng': '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
};

/// One isolated process, bounded input/output, cancellable at route disposal.
final class WindowsOcrTask {
  WindowsOcrTask(
    Uint8List rgba,
    int width,
    int height, {
    Directory? bundle,
    Duration timeout = const Duration(seconds: 90),
  }) {
    _completion = _run(
      rgba,
      width,
      height,
      bundle ??
          Directory('${File(Platform.resolvedExecutable).parent.path}/ocr'),
    );
    result = _completion.timeout(
      timeout,
      onTimeout: () {
        cancel();
        throw const WindowsOcrException('timeout');
      },
    );
  }
  late final Future<OcrPage> result;
  late final Future<OcrPage> _completion;
  Future<void> get stopped => _completion.then<void>(
    (_) {},
    onError: (Object error, StackTrace stack) {},
  );
  int? get processId => _process?.pid;
  Process? _process;
  bool _cancelled = false;
  static bool _busy = false;
  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  void _check() {
    if (_cancelled) throw const WindowsOcrException('cancelled');
  }

  Future<OcrPage> _run(
    Uint8List rgba,
    int width,
    int height,
    Directory bundle,
  ) async {
    if (width <= 0 ||
        height <= 0 ||
        width > 12000 ||
        height > 12000 ||
        width * height > 24000000 ||
        rgba.length != width * height * 4) {
      throw const WindowsOcrException('invalidImage');
    }
    if (_busy) throw const WindowsOcrException('busy');
    _busy = true;
    try {
      await validateWindowsOcrBundle(bundle);
      _check();
      final windows = Platform.environment['SystemRoot'] ?? r'C:/Windows';
      final process = await Process.start(
        '${bundle.path}/receipt_ocr_worker.exe',
        const [],
        workingDirectory: bundle.path,
        runInShell: false,
        includeParentEnvironment: false,
        environment: {
          'SystemRoot': windows,
          'WINDIR': windows,
          'PATH': '$windows/System32',
        },
      );
      _process = process;
      // Attach readers before writing, including on cancellation/startup failure.
      final output = _read(process.stdout, 8 * 1024 * 1024);
      final errors = _read(process.stderr, 64 * 1024, discard: true);
      final header = ByteData(12)
        ..setUint8(0, 82)
        ..setUint8(1, 82)
        ..setUint8(2, 79)
        ..setUint8(3, 49)
        ..setUint32(4, width, Endian.little)
        ..setUint32(8, height, Endian.little);
      final writing = () async {
        _check();
        process.stdin.add(header.buffer.asUint8List());
        process.stdin.add(rgba);
        await process.stdin.close();
      }();
      final values = await Future.wait<Object?>([
        output,
        errors,
        writing,
        process.exitCode,
      ], eagerError: true);
      _check();
      if (values[3] != 0) throw const WindowsOcrException('failed');
      return parseWindowsOcrTsv(
        utf8.decode(values[0]! as Uint8List),
        width,
        height,
      );
    } on WindowsOcrException {
      rethrow;
    } catch (_) {
      throw WindowsOcrException(_cancelled ? 'cancelled' : 'unavailable');
    } finally {
      final process = _process;
      if (process != null) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {
          /* Already detached or stopped. */
        }
      }
      _process = null;
      _busy = false;
    }
  }

  Future<Uint8List> _read(
    Stream<List<int>> stream,
    int maximum, {
    bool discard = false,
  }) async {
    final bytes = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in stream) {
      size += chunk.length;
      if (size > maximum) {
        cancel();
        throw const WindowsOcrException('outputLimit');
      }
      if (!discard) bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

/// Checks accidental corruption and missing assets; this is not code signing.
Future<void> validateWindowsOcrBundle(Directory bundle) async {
  try {
    final file = File('${bundle.path}/manifest.json');
    if (await file.length() > 65536) throw const FormatException();
    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (manifest['schemaVersion'] != 1 ||
        manifest['architecture'] != 'x64' ||
        manifest['engine'] != 'tesseract' ||
        manifest['version'] != '5.5.1' ||
        manifest['languages'] != 'fin+eng' ||
        manifest['protocol'] != 'RRO1' ||
        manifest['pageSegmentationMode'] != 6 ||
        manifest['modelFamily'] != 'tessdata_fast' ||
        manifest['modelRevision'] !=
            '87416418657359cb625c412a48b6e1d6d41c29bd') {
      throw const FormatException();
    }
    final files = manifest['files'] as Map<String, dynamic>;
    for (final name in [
      'receipt_ocr_worker.exe',
      'tessdata/fin.traineddata',
      'tessdata/eng.traineddata',
    ]) {
      final expected = files[name] as String;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
        throw const FormatException();
      }
      final content = File('${bundle.path}/$name');
      if (await content.length() > 32 * 1024 * 1024 ||
          (await sha256.bind(content.openRead()).first).toString() !=
              expected) {
        throw const FormatException();
      }
      for (final entry in _modelHashes.entries) {
        if (name == 'tessdata/${entry.key}.traineddata' &&
            expected != entry.value) {
          throw const FormatException();
        }
      }
    }
  } catch (_) {
    throw const WindowsOcrException('bundle');
  }
}

/// Strict TSV adapter preserving paragraph-scoped lines for the shared geometry.
OcrPage parseWindowsOcrTsv(String text, int width, int height) {
  const header =
      'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext';
  if (width <= 0 || height <= 0 || text.length > 8 * 1024 * 1024) {
    throw const FormatException('Invalid OCR output');
  }
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty || lines.first != header) {
    throw const FormatException('Invalid OCR header');
  }
  final blocks = <String, Map<String, List<Map<String, Object>>>>{};
  var words = 0, pages = 0;
  for (final line in lines.skip(1)) {
    if (line.isEmpty) continue;
    final fields = line.split('\t');
    if (fields.length != 12) throw const FormatException('Invalid OCR row');
    final numbers = [for (final value in fields.take(10)) int.tryParse(value)];
    if (numbers.any((n) => n == null || n < 0) ||
        numbers[0]! < 1 ||
        numbers[0]! > 5 ||
        numbers[1] != 1) {
      throw const FormatException('Invalid OCR coordinates');
    }
    final left = numbers[6]!,
        top = numbers[7]!,
        w = numbers[8]!,
        h = numbers[9]!;
    if (numbers[0] == 1) {
      pages++;
      if (pages != 1 || left != 0 || top != 0 || w != width || h != height) {
        throw const FormatException('Invalid OCR page');
      }
    }
    if (numbers[0] != 5 || fields[11].trim().isEmpty) continue;
    if (++words > 50000 ||
        w <= 0 ||
        h <= 0 ||
        left + w > width ||
        top + h > height ||
        fields[11].contains('\u0000')) {
      throw const FormatException('Invalid OCR word');
    }
    final block = blocks.putIfAbsent('${numbers[1]}:${numbers[2]}', () => {});
    final group = block.putIfAbsent('${numbers[3]}:${numbers[4]}', () => []);
    group.add({
      'text': fields[11],
      'box': {'left': left, 'top': top, 'right': left + w, 'bottom': top + h},
    });
  }
  if (pages != 1) throw const FormatException('Missing OCR page');
  return OcrPage.fromJson({
    'schemaVersion': 1,
    'image': {'width': width, 'height': height, 'orientation': 'upright'},
    'blocks': [
      for (final block in blocks.values)
        {
          'lines': [
            for (final group in block.values) {'words': group},
          ],
        },
    ],
  });
}
