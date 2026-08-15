/// User-facing classification for daemon startup / hub session failures.
enum DaemonErrorKind {
  /// Connection refused, missing token — often Keychain or cold start.
  keychainOrStarting,

  /// Access token expired / hub 401. Courier is up; session is not.
  sessionExpired,

  /// `health` ok but hub RTT timed out (`get_status` / `/v1/me`).
  hubTimeout,

  /// `health` ok but hub DNS/TLS/5xx or other `/v1/me` transport failure.
  hubUnreachable,

  /// Daemon not responding and unlikely to be a transient unlock wait.
  courierDown,
}

DaemonErrorKind classifyDaemonError({
  required String error,
  required bool daemonReachable,
}) {
  final lower = error.toLowerCase();
  if (!daemonReachable) {
    if (isLocalCourierTransportFailure(lower)) {
      return DaemonErrorKind.keychainOrStarting;
    }
    return DaemonErrorKind.courierDown;
  }
  if (isTimeoutError(lower)) return DaemonErrorKind.hubTimeout;
  if (isHubAuthFailure(lower)) return DaemonErrorKind.sessionExpired;
  return DaemonErrorKind.hubUnreachable;
}

/// Hub session / `/v1/me` failures must not look like sidecar boot.
bool isHubAuthFailure(String lowerError) {
  if (isLocalDaemonUnauthorized(lowerError)) return false;
  if (lowerError.contains('hub error 401')) return true;
  if (lowerError.contains('unauthorized')) return true;
  if (lowerError.contains('expired') &&
      (lowerError.contains('token') || lowerError.contains('401'))) {
    return true;
  }
  if (lowerError.contains('401') && lowerError.contains('/v1/me')) return true;
  // Bare `GET /v1/me for status` — refresh already failed; treat as session.
  if (lowerError.contains('get /v1/me') &&
      !isTimeoutError(lowerError) &&
      !isHubNetworkFailure(lowerError)) {
    return true;
  }
  return false;
}

bool isTimeoutError(String lowerError) {
  return lowerError.contains('timeout') || lowerError.contains('timed out');
}

/// Missing RPC/route (404, method not found). Not a sign-in failure.
///
/// `User not found` is a missing handle, not an unimplemented hub feature.
bool isHubUnimplemented(String lowerError) {
  final lower = lowerError.toLowerCase();
  if (lower.contains('user not found')) return false;
  if (lower.contains('method not found')) return true;
  if (lower.contains('unimplemented') || lower.contains('not implemented')) {
    return true;
  }
  if (RegExp(r'\b501\b').hasMatch(lower)) return true;
  if (lower.contains('hub error 404')) return true;
  if (lower.contains('404') &&
      (lower.contains('not found') || lower.contains('not_found'))) {
    return true;
  }
  return false;
}

bool isHubNetworkFailure(String lowerError) {
  return lowerError.contains('error sending request') ||
      lowerError.contains('dns error') ||
      lowerError.contains('certificate') ||
      lowerError.contains('tls handshake') ||
      lowerError.contains('502') ||
      lowerError.contains('503') ||
      lowerError.contains('500') ||
      (lowerError.contains('get /v1/me') &&
          lowerError.contains('connection refused'));
}

bool isLocalDaemonUnauthorized(String lowerError) {
  return lowerError.contains('daemon_http_token') ||
      lowerError.contains('matches the running daemon');
}

/// True when Retry + Restart courier are the recovery path (sidecar, not hub).
bool daemonErrorOffersRestart(DaemonErrorKind kind) {
  return kind == DaemonErrorKind.keychainOrStarting ||
      kind == DaemonErrorKind.courierDown;
}

/// Sign in is for hub session failures while the local courier is up.
bool daemonErrorOffersSignIn(DaemonErrorKind kind) {
  return kind == DaemonErrorKind.sessionExpired ||
      kind == DaemonErrorKind.hubTimeout ||
      kind == DaemonErrorKind.hubUnreachable;
}

/// True when the failure looks like a local HTTP/RPC transport blip.
bool isLocalCourierTransportFailure(String lowerError) {
  if (lowerError.contains('get /v1/me') || lowerError.contains('hub error')) {
    return false;
  }
  return lowerError.contains('connection refused') ||
      lowerError.contains('connection closed') ||
      lowerError.contains('connection reset') ||
      lowerError.contains('broken pipe') ||
      lowerError.contains('missing http token') ||
      lowerError.contains('failed host lookup') ||
      lowerError.contains('socketexception') ||
      lowerError.contains('clientexception') ||
      lowerError.contains('httpexception') ||
      lowerError.contains('matches the running daemon');
}

/// Plain-language title + body for [DaemonErrorScreen].
({String title, String body}) daemonErrorCopy(
  DaemonErrorKind kind, {
  required bool daemonReachable,
  String? handle,
}) {
  final who = _handleCaption(handle);
  switch (kind) {
    case DaemonErrorKind.keychainOrStarting:
      return (
        title: 'Waiting for Keychain',
        body:
            'macOS may be asking for your login password so mutande can start. '
            'Choose Allow, then tap Retry.',
      );
    case DaemonErrorKind.sessionExpired:
      return (
        title: 'Sign in again',
        body: who != null
            ? 'Your session for $who expired. Sign in with the same account as '
                'the web. Your browser will open.'
            : 'Your session with the hub expired. Sign in with the same account '
                'as the web. Your browser will open.',
      );
    case DaemonErrorKind.hubTimeout:
      return (
        title: 'Hub is taking too long',
        body:
            'The courier is running, but the hub did not answer in time. '
            'Retry, or sign in again if this keeps happening.',
      );
    case DaemonErrorKind.hubUnreachable:
      return (
        title: 'Can\'t reach the hub',
        body:
            'The courier is running, but mutande could not reach the hub. '
            'Check your network, then retry — or sign in again if your '
            'session expired.',
      );
    case DaemonErrorKind.courierDown:
      return (
        title: 'Courier not ready',
        body:
            'mutande-core did not respond. If you just allowed Keychain access, '
            'tap Retry. Otherwise restart the courier.',
      );
  }
}

String? _handleCaption(String? handle) {
  final trimmed = handle?.trim().toLowerCase();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

bool isLikelyStartingError(Object error) {
  final lower = error.toString().toLowerCase();
  if (isTimeoutError(lower)) return false;
  if (lower.contains('get /v1/me') || lower.contains('hub error')) return false;
  if (isHubAuthFailure(lower)) return false;
  return isLocalCourierTransportFailure(lower);
}
