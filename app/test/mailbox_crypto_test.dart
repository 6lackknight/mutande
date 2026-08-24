import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/mailbox/mailbox_crypto.dart';
import 'package:app/services/mailbox/mailbox_key_store.dart';

void main() {
  test('AES-GCM round-trip', () async {
    final key = await MailboxKeyStore(testMode: true).getOrCreateKey('u1');
    final crypto = MailboxCrypto(key);
    final sealed = await crypto.encryptString('hello mailbox');
    expect(await crypto.decryptString(sealed), 'hello mailbox');
  });

  test('wrong key fails decrypt', () async {
    final a = MailboxCrypto(await MailboxKeyStore(testMode: true).getOrCreateKey('a'));
    final b = MailboxCrypto(Uint8List.fromList(List.filled(32, 1)));
    final sealed = await a.encryptString('nope');
    expect(() => b.decrypt(sealed), throwsA(isA<Object>()));
  });
}
