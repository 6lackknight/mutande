import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/sentry_report.dart';

void main() {
  test('shouldReportDaemonRpcError skips health probes only', () {
    expect(
      shouldReportDaemonRpcError(
        TimeoutException('probe'),
        method: 'health',
      ),
      isFalse,
    );
    expect(
      shouldReportDaemonRpcError(
        Exception('GET /v1/me for status: hub error 401 Unauthorized'),
        method: 'get_collab',
      ),
      isTrue,
    );
    expect(
      shouldReportDaemonRpcError(
        Exception('Connection refused'),
        method: 'get_status',
      ),
      isTrue,
    );
    expect(
      shouldReportDaemonRpcError(
        Exception('hub error 404: collab not found'),
        method: 'get_collab',
      ),
      isTrue,
    );
  });

  test('shouldReportDaemonRpcError reports collab timeouts', () {
    expect(
      shouldReportDaemonRpcError(
        TimeoutException('request timed out'),
        method: 'get_collab',
      ),
      isTrue,
    );
    expect(
      shouldReportDaemonRpcError(
        Exception('GET /v1/collabs/abc timed out'),
        method: 'list_collabs',
      ),
      isTrue,
    );
  });

  test('daemonRpcErrorKind classifies failures', () {
    expect(
      daemonRpcErrorKind(TimeoutException('x')),
      'timeout',
    );
    expect(
      daemonRpcErrorKind(Exception('connection refused')),
      'courier',
    );
    expect(
      daemonRpcErrorKind(
        Exception('GET /v1/me for status: hub error 401 Unauthorized'),
      ),
      'auth',
    );
  });
}
