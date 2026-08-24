import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM helpers for media files (same Keychain key as the mailbox DB).
class MailboxCrypto {
  MailboxCrypto(this.key);

  final Uint8List key;

  static final _aes = AesGcm.with256bits();

  /// Encrypt [plain] → `nonce(12) || ciphertext || mac(16)`.
  Future<Uint8List> encrypt(Uint8List plain) async {
    final secret = SecretKey(key);
    final nonce = _randomNonce();
    final box = await _aes.encrypt(
      plain,
      secretKey: secret,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> decrypt(Uint8List sealed) async {
    if (sealed.length < 12 + 16) {
      throw StateError('mailbox ciphertext too short');
    }
    final nonce = sealed.sublist(0, 12);
    final mac = Mac(sealed.sublist(sealed.length - 16));
    final cipherText = sealed.sublist(12, sealed.length - 16);
    final secret = SecretKey(key);
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: secret,
    );
    return Uint8List.fromList(clear);
  }

  Future<Uint8List> encryptString(String plain) =>
      encrypt(Uint8List.fromList(utf8.encode(plain)));

  Future<String> decryptString(Uint8List sealed) async {
    final clear = await decrypt(sealed);
    return utf8.decode(clear);
  }

  /// Hex form for SQLCipher `PRAGMA key = "x'…'"`.
  String get sqlCipherHexKey {
    final buf = StringBuffer();
    for (final b in key) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static List<int> _randomNonce() {
    final rnd = Random.secure();
    return List<int>.generate(12, (_) => rnd.nextInt(256));
  }
}
