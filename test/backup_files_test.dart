import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_reader/backup_files.dart';
import 'package:receipt_storage/receipt_storage.dart';

void main() {
  test(
    'new backup writes are flushed and an existing file is never truncated',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'backup-file-test-',
      );
      try {
        final file = File('${directory.path}/test.rrbackup');
        final bytes = Uint8List.fromList([1, 2, 3]);
        await writeNewBackup(file, bytes);
        expect(await file.readAsBytes(), bytes);
        await expectLater(
          writeNewBackup(file, Uint8List.fromList([4])),
          throwsA(
            isA<StorageFailure>().having(
              (e) => e.code,
              'code',
              'backupFileExists',
            ),
          ),
        );
        expect(await file.readAsBytes(), bytes);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'oversized exports are rejected before creating a destination',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'backup-file-test-',
      );
      try {
        final file = File('${directory.path}/large.rrbackup');
        await expectLater(
          writeNewBackup(file, Uint8List(ProtectedBackup.maxBytes + 1)),
          throwsA(isA<StorageFailure>()),
        );
        expect(await file.exists(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
