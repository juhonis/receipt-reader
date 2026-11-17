import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:receipt_storage/receipt_storage.dart';
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/protected_backup_v1.json').readAsStringSync(),
  ) as Map;
  final password = fixture['password'] as String;
  final encrypted = base64Decode(fixture['encrypted_base64'] as String);
  final plaintext = base64Decode(fixture['plaintext_base64'] as String);
  Matcher failure(String code) =>
      throwsA(isA<StorageFailure>().having((e) => e.code, 'code', code));

  test(
    'decrypts the independent Python Argon2id v19 / AES-256-GCM fixture',
    () async {
      expect(await ProtectedBackup.decrypt(encrypted, password), plaintext);
    },
  );
  test('fresh salt and nonce randomize encryption without changing the caller buffer', () async {
    final before = Uint8List.fromList(plaintext);
    final one = await ProtectedBackup.encrypt(plaintext, password);
    final two = await ProtectedBackup.encrypt(plaintext, password);
    expect(one, isNot(two));
    expect(one.sublist(10, 26), isNot(two.sublist(10, 26)));
    expect(one.sublist(26, 38), isNot(two.sublist(26, 38)));
    expect(await ProtectedBackup.decrypt(one, password), plaintext);
    expect(plaintext, before);
    expect(
      utf8.decode(one, allowMalformed: true),
      isNot(contains('receipt_reader_backup')),
    );
  });
  for (final offset in [10, 26, 38, encrypted.length - 1]) {
    test(
      'authenticates salt, nonce, ciphertext and tag at byte $offset',
      () async {
        final damaged = Uint8List.fromList(encrypted)..[offset] ^= 1;
        await expectLater(
          ProtectedBackup.decrypt(damaged, password),
          failure('backupAuthentication'),
        );
      },
    );
  }
  test('wrong password has the same sanitized failure as corruption', () async {
    await expectLater(
      ProtectedBackup.decrypt(encrypted, 'wrong synthetic password'),
      failure('backupAuthentication'),
    );
  });
  test('rejects unsupported suite/version, plaintext and truncation before derivation', () async {
    for (final offset in [0, 8, 9]) {
      final damaged = Uint8List.fromList(encrypted)..[offset] ^= 1;
      await expectLater(
        ProtectedBackup.decrypt(damaged, password),
        failure('invalidEncryptedBackup'),
      );
    }
    await expectLater(
      ProtectedBackup.decrypt(plaintext, password),
      failure('invalidEncryptedBackup'),
    );
    await expectLater(
      ProtectedBackup.decrypt(Uint8List(53), password),
      failure('invalidEncryptedBackup'),
    );
  });
  test('password Unicode and whitespace are preserved exactly', () async {
    const unicode = '  pitkä salasana 🔒  ';
    final bytes = await ProtectedBackup.encrypt(plaintext, unicode);
    expect(await ProtectedBackup.decrypt(bytes, unicode), plaintext);
    await expectLater(
      ProtectedBackup.decrypt(bytes, unicode.trim()),
      failure('backupAuthentication'),
    );
  });
  test('password and byte bounds fail before KDF allocation', () async {
    for (final password in ['short', '🔒' * 257]) {
      await expectLater(
        ProtectedBackup.encrypt(plaintext, password),
        failure('backupPassword'),
      );
    }
    await expectLater(
      ProtectedBackup.encrypt(
        Uint8List(ReceiptBackupLimits.maxBytes + 1),
        password,
      ),
      failure('backupTooLarge'),
    );
    await expectLater(
      ProtectedBackup.decrypt(
        Uint8List(ProtectedBackup.maxBytes + 1),
        password,
      ),
      failure('backupTooLarge'),
    );
  });
}
