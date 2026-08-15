import 'package:app/services/daemon_client.dart';
import 'package:app/widgets/thread_status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThreadStatusKind.resolve', () {
    test('Needs you when awaiting has human for my handle', () {
      expect(
        ThreadStatusKindX.resolve(
          status: 'open',
          yourStatus: 'replied',
          awaiting: const [
            AwaitingEntry(address: 'alice@acme', actor: 'human'),
          ],
          myHandle: 'alice@acme/cursor',
        ),
        ThreadStatusKind.needsYou,
      );
    });

    test('Waiting when awaiting is agents only', () {
      expect(
        ThreadStatusKindX.resolve(
          status: 'open',
          yourStatus: 'pending',
          awaiting: const [
            AwaitingEntry(address: 'alice@acme/claude', actor: 'agent'),
          ],
          myHandle: 'alice@acme',
        ),
        ThreadStatusKind.waiting,
      );
    });

    test('legacy your_status when awaiting empty', () {
      expect(
        ThreadStatusKindX.resolve(
          status: 'open',
          yourStatus: 'pending',
          awaiting: const [],
          myHandle: 'alice@acme',
        ),
        ThreadStatusKind.needsYou,
      );
    });
  });
}
