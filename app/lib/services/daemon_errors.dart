/// User-facing classification for daemon startup / transport failures.
enum DaemonErrorKind {
  /// Connection refused, missing token — often Keychain or cold start.
  keychainOrStarting,

  /// `health` ok but `get_status` failed (hub slowness, etc.).
  sessionTimeout,

  /// Daemon not responding and unlikely to be a transient unlock wait.
  courierDown,
}

DaemonErrorKind classifyDaemonError({
  required String error,
  required bool daemonReachable,
}) {
  if (daemonReachable) return DaemonErrorKind.sessionTimeout;
  final lower = error.toLowerCase();
  if (isLocalCourierTransportFailure(lower)) {
    return DaemonErrorKind.keychainOrStarting;
  }
  return DaemonErrorKind.courierDown;
}

/// True when the failure looks like a local HTTP/RPC transport blip.
bool isLocalCourierTransportFailure(String lowerError) {
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
}) {
  switch (kind) {
    case DaemonErrorKind.keychainOrStarting:
      return (
        title: 'Waiting for Keychain',
        body:
            'macOS may be asking for your login password so mutande-core can '
            'start. Choose Allow, then tap Retry.',
      );
    case DaemonErrorKind.sessionTimeout:
      return (
        title: 'Courier still starting',
        body:
            'Mail took too long to load. The courier may still be starting — '
            'try again in a moment.',
      );
    case DaemonErrorKind.courierDown:
      return (
        title: 'Courier not ready',
        body:
            'mutande-core did not respond. If you just allowed Keychain access, '
            'tap Retry. Otherwise check Settings → Local courier.',
      );
  }
}

bool isLikelyStartingError(Object error) {
  final lower = error.toString().toLowerCase();
  if (isLocalCourierTransportFailure(lower)) return true;
  return lower.contains('timeout') || lower.contains('timed out');
}
