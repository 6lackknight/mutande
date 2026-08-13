import 'package:flutter_test/flutter_test.dart';

import 'package:app/util/thread_peer.dart';

void main() {
  test('threadPeerHandle prefers the other human', () {
    expect(
      threadPeerHandle('alice@acme/cursor', 'bob@acme/claude', myHandle: 'alice@acme'),
      'bob@acme',
    );
    expect(
      threadPeerHandle('bob@acme', 'alice@acme', myHandle: 'alice@acme'),
      'bob@acme',
    );
  });

  test('threadPeerHandle is null for self-collab and broadcast', () {
    expect(
      threadPeerHandle('alice@acme/cursor', 'alice@acme/claude', myHandle: 'alice@acme'),
      isNull,
    );
    expect(
      threadPeerHandle('alice@acme', '@all@acme', myHandle: 'alice@acme'),
      isNull,
    );
    expect(
      threadPeerHandle('alice@acme/cursor', '@all', myHandle: 'alice@acme'),
      isNull,
    );
  });

  test('avatarUrlsByHandle keys bare lowercase handles', () {
    final map = avatarUrlsByHandle([
      (handle: 'Bob@Acme', avatarUrl: 'https://cdn.example.test/bob.jpg'),
      (handle: '@all@acme', avatarUrl: 'https://cdn.example.test/skip.jpg'),
      (handle: 'carol@acme', avatarUrl: '  '),
    ]);
    expect(map['bob@acme'], 'https://cdn.example.test/bob.jpg');
    expect(map.containsKey('@all@acme'), isFalse);
    expect(map.containsKey('carol@acme'), isFalse);
  });
}
