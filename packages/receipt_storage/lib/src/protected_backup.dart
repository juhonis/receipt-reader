import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'repository.dart';

/// Binary v1: RRBACKUP, version=1, suite=1, salt[16], nonce[12], ciphertext,
/// GCM tag[16]. Suite 1 fixes Argon2id v19 (19 MiB, t=2, p=1) and AES-256-GCM.
/// The entire 38-byte header is authenticated as AAD; no input KDF parameters.
abstract final class ProtectedBackup {
  static const maxBytes = ReceiptBackupLimits.maxBytes + 54;
  static final _prefix = [...ascii.encode('RRBACKUP'), 1, 1];

  static void checkPassword(String password) {
    if (password.runes.length < 12 || utf8.encode(password).length > 1024) {
      throw const StorageFailure('backupPassword');
    }
  }

  static Future<Uint8List> encrypt(Uint8List plaintext, String password) async {
    checkPassword(password);
    if (plaintext.length > ReceiptBackupLimits.maxBytes) {
      throw const StorageFailure('backupTooLarge');
    }
    final copy = Uint8List.fromList(plaintext);
    try {
      return await Isolate.run(() => _encrypt(copy, password));
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  static Future<Uint8List> decrypt(Uint8List file, String password) async {
    checkPassword(password);
    if (file.length > maxBytes) throw const StorageFailure('backupTooLarge');
    if (file.length < 54 ||
        !_prefix.asMap().entries.every((e) => file[e.key] == e.value)) {
      throw const StorageFailure('invalidEncryptedBackup');
    }
    final copy = Uint8List.fromList(file);
    return Isolate.run(() => _decrypt(copy, password));
  }

  static Future<SecretKey> _key(String password, List<int> salt) async {
    final secret = SecretKey(utf8.encode(password));
    try {
      return await Argon2id(
        parallelism: 1,
        memory: 19456,
        iterations: 2,
        hashLength: 32,
      ).deriveKey(secretKey: secret, nonce: salt);
    } finally {
      secret.destroy();
    }
  }

  static Future<Uint8List> _encrypt(
    Uint8List plaintext,
    String password,
  ) async {
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    final cipher = AesGcm.with256bits();
    final nonce = cipher.newNonce();
    final header = Uint8List.fromList([..._prefix, ...salt, ...nonce]);
    final key = await _key(password, salt);
    try {
      final box = await cipher.encrypt(
        plaintext,
        secretKey: key,
        nonce: nonce,
        aad: header,
      );
      return Uint8List.fromList([
        ...header,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } finally {
      key.destroy();
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  static Future<Uint8List> _decrypt(Uint8List file, String password) async {
    final header = Uint8List.sublistView(file, 0, 38);
    final salt = Uint8List.sublistView(file, 10, 26);
    final nonce = Uint8List.sublistView(file, 26, 38);
    final key = await _key(password, salt);
    try {
      final box = SecretBox(
        Uint8List.sublistView(file, 38, file.length - 16),
        nonce: nonce,
        mac: Mac(Uint8List.sublistView(file, file.length - 16)),
      );
      return Uint8List.fromList(
        await AesGcm.with256bits().decrypt(box, secretKey: key, aad: header),
      );
    } on SecretBoxAuthenticationError {
      throw const StorageFailure('backupAuthentication');
    } finally {
      key.destroy();
    }
  }
}
