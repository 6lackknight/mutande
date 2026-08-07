import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/daemon_errors.dart';

void main() {
  test('classifyDaemonError keychain vs session vs down', () {
    expect(
      classifyDaemonError(
        error: 'Connection refused',
        daemonReachable: false,
      ),
      DaemonErrorKind.keychainOrStarting,
    );
    expect(
      classifyDaemonError(
        error: 'TimeoutException',
        daemonReachable: true,
      ),
      DaemonErrorKind.sessionTimeout,
    );
    expect(
      classifyDaemonError(
        error: 'spawn failed',
        daemonReachable: false,
      ),
      DaemonErrorKind.courierDown,
    );
  });

  test('isLikelyStartingError detects connection refused', () {
    expect(isLikelyStartingError(Exception('connection refused')), isTrue);
    expect(isLikelyStartingError(Exception('HTTP 500')), isFalse);
  });

  test('isLocalCourierTransportFailure covers closed headers', () {
    expect(
      isLocalCourierTransportFailure(
        'clientexception: connection closed before full header was received, '
        'uri=http://127.0.0.1:3847/rpc',
      ),
      isTrue,
    );
    expect(
      classifyDaemonError(
        error:
            'ClientException: Connection closed before full header was received',
        daemonReachable: false,
      ),
      DaemonErrorKind.keychainOrStarting,
    );
  });
}
