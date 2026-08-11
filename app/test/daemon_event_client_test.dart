import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/daemon_event_client.dart';

void main() {
  test('InboxChangedEvent.fromJson', () {
    final ev = InboxChangedEvent.fromJson({
      'event': 'inbox_changed',
      'revision': 7,
      'at': '1710000000',
    });
    expect(ev.revision, 7);
    expect(ev.at, '1710000000');
  });
}
