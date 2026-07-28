import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/daemon_client.dart';
import 'package:app/widgets/thread_message_tree.dart';

void main() {
  test('flattenThreadMessages nests by parent id', () {
    const a = ThreadMessageView(
      id: 'a',
      fromHandle: 'alice@acme/claude',
      createdAt: '2026-01-01T00:00:00Z',
    );
    const b = ThreadMessageView(
      id: 'b',
      fromHandle: 'alice@acme/cursor',
      createdAt: '2026-01-01T00:01:00Z',
      parentMessageId: 'a',
    );
    const c = ThreadMessageView(
      id: 'c',
      fromHandle: 'alice@acme/claude',
      createdAt: '2026-01-01T00:02:00Z',
      parentMessageId: 'b',
    );

    final flat = flattenThreadMessages([b, c, a]);
    expect(flat.map((n) => n.message.id).toList(), ['a', 'b', 'c']);
    expect(flat.map((n) => n.depth).toList(), [0, 1, 2]);
  });
}
