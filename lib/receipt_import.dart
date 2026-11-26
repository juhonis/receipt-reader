import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

enum ImportFailure {
  tooLarge,
  unsupported,
  unreadable,
  cameraDenied,
  cameraUnavailable,
  captureFailed,
}

bool get supportsReceiptCamera =>
    defaultTargetPlatform == TargetPlatform.android;

/// Native JPEG bytes never pass through a file or Flutter's shared image cache.
Future<ReceiptEvidence?> captureReceiptImage() async {
  if (!supportsReceiptCamera) {
    throw const ReceiptImportException(ImportFailure.cameraUnavailable);
  }
  try {
    final bytes = await const MethodChannel('receipt_reader/import')
        .invokeMethod<Uint8List>('captureImage');
    return bytes == null ? null : await ReceiptEvidence.decode(bytes);
  } on ReceiptImportException {
    rethrow;
  } on PlatformException catch (error) {
    throw ReceiptImportException(switch (error.code) {
      'camera_denied' => ImportFailure.cameraDenied,
      'camera_unavailable' => ImportFailure.cameraUnavailable,
      'too_large' => ImportFailure.tooLarge,
      _ => ImportFailure.captureFailed,
    });
  } catch (_) {
    throw const ReceiptImportException(ImportFailure.captureFailed);
  }
}

class ReceiptImportException implements Exception {
  const ReceiptImportException(this.failure);
  final ImportFailure failure;
}

/// Route-owned pixels. RawImage avoids the process-wide Flutter ImageCache.
class ReceiptEvidence {
  ReceiptEvidence._(this.image);
  final ui.Image image;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Another route-owned handle to the same immutable pixels. No file copy.
  ReceiptEvidence clone() {
    if (_disposed) throw StateError('Receipt evidence already disposed');
    return ReceiptEvidence._(image.clone());
  }

  void dispose() {
    if (!_disposed) {
      image.dispose();
      _disposed = true;
    }
  }

  static const maxBytes = 20 * 1024 * 1024;
  static const maxPixels = 24 * 1000 * 1000;

  static Future<ReceiptEvidence> decode(Uint8List bytes) async {
    if (bytes.length > maxBytes) {
      throw const ReceiptImportException(ImportFailure.tooLarge);
    }
    final png =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!png && !jpeg) {
      throw const ReceiptImportException(ImportFailure.unsupported);
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > maxPixels ||
          descriptor.width > 12000 ||
          descriptor.height > 12000) {
        throw const ReceiptImportException(ImportFailure.tooLarge);
      }
      codec = await descriptor.instantiateCodec();
      if (codec.frameCount != 1) {
        throw const ReceiptImportException(ImportFailure.unsupported);
      }
      final frame = await codec.getNextFrame();
      return ReceiptEvidence._(frame.image);
    } on ReceiptImportException {
      rethrow;
    } catch (_) {
      throw const ReceiptImportException(ImportFailure.unreadable);
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

Future<ReceiptEvidence?> pickReceiptImage() async {
  try {
    Uint8List? bytes;
    if (Platform.isAndroid) {
      bytes = await const MethodChannel('receipt_reader/import')
          .invokeMethod<Uint8List>('pickImage');
    } else if (Platform.isWindows) {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'JPEG / PNG',
            extensions: ['jpg', 'jpeg', 'png'],
          ),
        ],
      );
      if (file == null) return null;
      if (await file.length() > ReceiptEvidence.maxBytes) {
        throw const ReceiptImportException(ImportFailure.tooLarge);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (builder.length + chunk.length > ReceiptEvidence.maxBytes) {
          throw const ReceiptImportException(ImportFailure.tooLarge);
        }
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    } else {
      throw const ReceiptImportException(ImportFailure.unsupported);
    }
    return bytes == null ? null : await ReceiptEvidence.decode(bytes);
  } on ReceiptImportException {
    rethrow;
  } on PlatformException catch (error) {
    throw ReceiptImportException(
      error.code == 'too_large'
          ? ImportFailure.tooLarge
          : ImportFailure.unreadable,
    );
  } catch (_) {
    throw const ReceiptImportException(ImportFailure.unreadable);
  }
}
