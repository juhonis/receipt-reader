import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:receipt_storage/receipt_storage.dart';

abstract interface class BackupFiles {
  Future<Uint8List?> read();
  Future<bool> save(Uint8List encrypted);
}

final class NativeBackupFiles implements BackupFiles {
  const NativeBackupFiles();
  static const channel = MethodChannel('receipt_reader/backup');
  @override
  Future<Uint8List?> read() async {
    try {
      if (Platform.isAndroid) {
        return await channel.invokeMethod<Uint8List>('read');
      }
      final picked = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Receipt Reader', extensions: ['rrbackup']),
        ],
      );
      if (picked == null) return null;
      if (await picked.length() > ProtectedBackup.maxBytes) {
        throw const StorageFailure('backupTooLarge');
      }
      final result = BytesBuilder(copy: false);
      await for (final part in picked.openRead()) {
        if (result.length + part.length > ProtectedBackup.maxBytes) {
          throw const StorageFailure('backupTooLarge');
        }
        result.add(part);
      }
      return result.takeBytes();
    } on StorageFailure {
      rethrow;
    } catch (_) {
      throw const StorageFailure('backupFile');
    }
  }

  @override
  Future<bool> save(Uint8List encrypted) async {
    try {
      if (Platform.isAndroid) {
        return await channel.invokeMethod<bool>('write', encrypted) ?? false;
      }
      final target = await getSaveLocation(
        suggestedName:
            'receipts-${DateTime.now().toUtc().millisecondsSinceEpoch}.rrbackup',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Receipt Reader', extensions: ['rrbackup']),
        ],
      );
      if (target == null) return false;
      await writeNewBackup(File(target.path), encrypted);
      return true;
    } on StorageFailure {
      rethrow;
    } catch (_) {
      throw const StorageFailure('backupFile');
    }
  }
}

/// Existing backups are never truncated. A failed/crashed new export may leave a
/// partial encrypted file; authentication rejects it on import.
Future<void> writeNewBackup(File target, Uint8List bytes) async {
  if (bytes.length > ProtectedBackup.maxBytes) {
    throw const StorageFailure('backupTooLarge');
  }
  try {
    await target.create(exclusive: true);
  } catch (_) {
    if (await target.exists()) {
      throw const StorageFailure('backupFileExists');
    }
    throw const StorageFailure('backupFile');
  }
  try {
    await target.writeAsBytes(bytes, flush: true);
  } catch (_) {
    try {
      await target.delete();
    } catch (_) {}
    throw const StorageFailure('backupFile');
  }
}
