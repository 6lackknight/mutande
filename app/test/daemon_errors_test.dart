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
}
