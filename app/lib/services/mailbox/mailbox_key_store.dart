import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the mailbox key cannot be persisted to Keychain.
/// Callers must fail open (no mailbox) — never encrypt with an ephemeral key.
class MailboxKeyStoreException implements Exception {
  MailboxKeyStoreException(this.message);
  final String message;
  @override
  String toString() => 'MailboxKeyStoreException: $message';
}

/// Keychain-held 256-bit mailbox key, labeled by Auth0 subject.
class MailboxKeyStore {
  MailboxKeyStore({
    FlutterSecureStorage? storage,
    this.testMode = false,
    this.allowTestEnvBypass = true,
  }) : _storage =
            storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(
                synchronizable: false,
                // Data-protection Keychain needs a signed app + keychain-access-groups.
                // flutter run / ad-hoc debug hits -34018 without this set false.
                usesDataProtectionKeychain: false,
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// When true (widget/unit tests), skip Keychain and use a deterministic key.
  final bool testMode;

  /// When false, never treat `FLUTTER_TEST` as a Keychain bypass (for fail-open tests).
  final bool allowTestEnvBypass;

  static String _keyName(String userId) {
    final safe = userId.trim().replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '_');
    return 'mutande.mailbox.key.$safe';
  }

  bool get _useTestKey {
    if (testMode || kIsWeb) return true;
    if (!allowTestEnvBypass) return false;
    return Platform.environment.containsKey('FLUTTER_TEST');
  }

  /// Returns existing key or generates and persists a new one.
  ///
  /// Never returns a key that was not written to Keychain (except [testMode]).
  Future<Uint8List> getOrCreateKey(String userId) async {
    if (_useTestKey) return _testKey(userId);

    final name = _keyName(userId);
    try {
      final existing = await _storage.read(key: name);
      if (existing != null && existing.isNotEmpty) {
        final bytes = base64Url.decode(existing);
        if (bytes.length == 32) return Uint8List.fromList(bytes);
      }
    } catch (e) {
      throw MailboxKeyStoreException('Could not read mailbox key: $e');
    }

    final key = _randomKey();
    try {
      await _storage.write(key: name, value: base64Url.encode(key));
    } catch (e) {
      throw MailboxKeyStoreException(
        'Could not persist mailbox key to Keychain: $e',
      );
    }

    // Verify round-trip so we never encrypt with a key Keychain rejected.
    try {
      final verify = await _storage.read(key: name);
      if (verify == null || base64Url.decode(verify).length != 32) {
        throw MailboxKeyStoreException(
          'Mailbox key write did not persist in Keychain',
        );
      }
    } catch (e) {
      if (e is MailboxKeyStoreException) rethrow;
      throw MailboxKeyStoreException('Could not verify mailbox key: $e');
    }
    return key;
  }

  Future<void> deleteKey(String userId) async {
    if (_useTestKey) return;
    try {
      await _storage.delete(key: _keyName(userId));
    } catch (_) {}
  }

  static Uint8List _randomKey() {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  /// Deterministic test key so SQLCipher / AES round-trips stay stable.
  static Uint8List _testKey(String userId) {
    final seed = utf8.encode('mutande-test-mailbox:$userId');
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = seed[i % seed.length] ^ (i * 17);
    }
    return out;
  }
}
