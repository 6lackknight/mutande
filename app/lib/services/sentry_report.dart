import 'package:sentry_flutter/sentry_flutter.dart';

import 'daemon_errors.dart';

/// Whether a daemon RPC failure should reach GlitchTip (testable filter).
///
/// Skips only `health` — sidecar polls it every ~200ms during Keychain boot.
bool shouldReportDaemonRpcError(Object error, {required String method}) {
  if (method == 'health') return false;
  return true;
}

String daemonRpcErrorKind(Object error) {
  final lower = error.toString().toLowerCase();
  if (isTimeoutError(lower)) return 'timeout';
  if (isHubAuthFailure(lower)) return 'auth';
  if (isLocalCourierTransportFailure(lower)) return 'courier';
  if (isHubNetworkFailure(lower)) return 'hub_network';
  if (isHubUnimplemented(lower)) return 'unimplemented';
  if (isLikelyStartingError(error)) return 'starting';
  return 'other';
}

void _capture(
  Object error, {
  StackTrace? stackTrace,
  required void Function(Scope scope) configure,
}) {
  if (!Sentry.isEnabled) return;
  Sentry.captureException(
    error,
    stackTrace: stackTrace,
    withScope: configure,
  );
}

/// Report handled daemon RPC failures (timeouts, hub blips, etc.).
void reportDaemonRpcError(
  Object error, {
  StackTrace? stackTrace,
  required String method,
}) {
  if (!shouldReportDaemonRpcError(error, method: method)) return;
  final kind = daemonRpcErrorKind(error);
  _capture(
    error,
    stackTrace: stackTrace,
    configure: (scope) {
      scope.setTag('rpc.method', method);
      scope.setTag('rpc.error_kind', kind);
      scope.setTag('handled', 'rpc');
      scope.fingerprint = ['daemon-rpc', method, kind];
    },
  );
}

/// Report any other handled failure (local I/O, WebSocket, widget build, etc.).
void reportHandledError(
  Object error, {
  StackTrace? stackTrace,
  String? surface,
  Map<String, String>? tags,
}) {
  _capture(
    error,
    stackTrace: stackTrace,
    configure: (scope) {
      scope.setTag('handled', 'true');
      if (surface != null && surface.isNotEmpty) {
        scope.setTag('surface', surface);
      }
      tags?.forEach(scope.setTag);
      final fp = <String>['handled', surface ?? 'unknown', error.runtimeType.toString()];
      if (surface != null) {
        scope.fingerprint = fp;
      }
    },
  );
}
