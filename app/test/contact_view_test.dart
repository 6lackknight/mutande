import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/daemon_client.dart';

void main() {
  test('ContactView reads display_name', () {
    final c = ContactView.fromJson({
      'handle': 'bob@acme',
      'kind': 'org',
      'display_name': '  Bob Builder  ',
      'avatar_url': 'https://cdn.example.test/bob.jpg',
      'devices': [],
    });
    expect(c.displayName, 'Bob Builder');
    expect(c.avatarUrl, 'https://cdn.example.test/bob.jpg');
  });

  test('ContactView drops blank display_name', () {
    final c = ContactView.fromJson({
      'handle': 'carol@acme',
      'display_name': '   ',
      'devices': [],
    });
    expect(c.displayName, isNull);
  });
}
