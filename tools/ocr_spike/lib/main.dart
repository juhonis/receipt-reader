import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Map<String, Object> box(ui.Rect r) => {
  'left': r.left,
  'top': r.top,
  'right': r.right,
  'bottom': r.bottom,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Offline OCR development harness')),
    ),
  );
  // Dedicated debug-only package. The host runner stages explicit private
  // inputs here, retrieves results, and uninstalls this package in finally.
  const root = '/data/user/0/fi.juhonis.ocr_spike/files';
  final inputs = Directory('$root/inputs');
  final outputs = Directory('$root/results');
  await outputs.create(recursive: true);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final engineFile = File('$root/engine');
    if (await engineFile.exists() &&
        (await engineFile.readAsString()).trim() == 'tesseract') {
      await const MethodChannel('ocr_spike/tesseract')
          .invokeMethod<void>('recognize');
      await File('${outputs.path}/done').writeAsString('ok');
      return;
    }
    final files = await inputs
        .list()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) throw StateError('No staged inputs');
    for (final entity in files) {
      final file = File(entity.path);
      final id = file.uri.pathSegments.last.split('.').first;
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      final timer = Stopwatch()..start();
      final result = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      timer.stop();
      final blocks = [
        for (final block in result.blocks)
          {
            'text': block.text,
            'box': box(block.boundingBox),
            'lines': [
              for (final line in block.lines)
                {
                  'text': line.text,
                  'box': box(line.boundingBox),
                  'words': [
                    for (final word in line.elements)
                      {
                        'text': word.text,
                        'box': box(word.boundingBox),
                        'corners': [
                          for (final p in word.cornerPoints) [p.x, p.y],
                        ],
                      },
                  ],
                },
            ],
          },
      ];
      await File('${outputs.path}/$id.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'sampleId': id,
          'engine': 'mlkit-latin-16.0.1',
          'adapterVersion': 'google_mlkit_text_recognition-1.0.3',
          'image': {'width': width, 'height': height, 'orientation': 'upright'},
          'elapsedMs': timer.elapsedMilliseconds,
          'text': result.text,
          'blocks': blocks,
        }),
      );
      await file.delete();
    }
    await File('${outputs.path}/done').writeAsString('ok');
  } catch (error) {
    // Never send OCR text or exception details to Android's shared log.
    await File('${outputs.path}/failed').writeAsString(
      jsonEncode({
        'type': error.runtimeType.toString(),
        'code': error is PlatformException ? error.code : null,
        'message': error.toString(),
      }),
    );
  } finally {
    await recognizer.close();
    if (await inputs.exists()) await inputs.delete(recursive: true);
  }
}
