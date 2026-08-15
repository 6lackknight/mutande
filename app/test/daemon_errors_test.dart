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
      DaemonErrorKind.hubTimeout,
    );
    expect(
      classifyDaemonError(
        error: 'spawn failed',
        daemonReachable: false,
      ),
      DaemonErrorKind.courierDown,
    );
  });

  test('classifyDaemonError hub 401 is session not courier starting', () {
    expect(
      classifyDaemonError(
        error: 'GET /v1/me for status: hub error 401 Unauthorized',
        daemonReachable: true,
      ),
      DaemonErrorKind.sessionExpired,
    );
    expect(
      classifyDaemonError(
        error: 'GET /v1/me for status',
        daemonReachable: true,
      ),
      DaemonErrorKind.sessionExpired,
    );
    expect(
      daemonErrorCopy(
        DaemonErrorKind.sessionExpired,
        daemonReachable: true,
      ).title,
      'Sign in again',
    );
    expect(
      daemonErrorCopy(
        DaemonErrorKind.sessionExpired,
        daemonReachable: true,
        handle: 'alice@acme',
      ).body,
      contains('alice@acme'),
    );
    expect(
      daemonErrorOffersSignIn(DaemonErrorKind.sessionExpired),
      isTrue,
    );
    expect(
      daemonErrorOffersRestart(DaemonErrorKind.sessionExpired),
      isFalse,
    );
  });

  test('classifyDaemonError hub network vs timeout while health ok', () {
    expect(
      classifyDaemonError(
        error: 'GET /v1/me for status: error sending request for url',
        daemonReachable: true,
      ),
      DaemonErrorKind.hubUnreachable,
    );
    expect(
      classifyDaemonError(
        error: 'GET /v1/me for status: TimeoutException after 0:00:10',
        daemonReachable: true,
      ),
      DaemonErrorKind.hubTimeout,
    );
    expect(daemonErrorOffersSignIn(DaemonErrorKind.hubTimeout), isTrue);
    expect(daemonErrorOffersRestart(DaemonErrorKind.hubTimeout), isFalse);
    expect(daemonErrorOffersSignIn(DaemonErrorKind.hubUnreachable), isTrue);
  });

  test('isLikelyStartingError detects connection refused not hub 401', () {
    expect(isLikelyStartingError(Exception('connection refused')), isTrue);
    expect(isLikelyStartingError(Exception('HTTP 500')), isFalse);
    expect(
      isLikelyStartingError(
        Exception('GET /v1/me for status: hub error 401 Unauthorized'),
      ),
      isFalse,
    );
    expect(
      isLikelyStartingError(Exception('TimeoutException after 0:00:15')),
      isFalse,
    );
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
    expect(
      isLocalCourierTransportFailure(
        'get /v1/me for status: connection refused',
      ),
      isFalse,
    );
  });

  test('local daemon 401 is not hub sign-in', () {
    expect(
      isHubAuthFailure(
        'http 401 unauthorized — check ~/.mutande/daemon_http_token '
        'matches the running daemon',
      ),
      isFalse,
    );
  });

  test('hub 404 and method not found are unimplemented, not sign-in', () {
    expect(
      isHubUnimplemented(
        'hub error 404 Not Found: {"error":"not_found"}',
      ),
      isTrue,
    );
    expect(isHubUnimplemented('method not found: create_collab'), isTrue);
    expect(
      isHubUnimplemented(
        'hub error 404 Not Found: {"error":"not_found","message":"User not found"}',
      ),
      isFalse,
    );
    expect(isHubAuthFailure('hub error 404 Not Found'), isFalse);
  });
}
