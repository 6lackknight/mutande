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
  if (lower.contains('connection refused') ||
      lower.contains('missing http token') ||
      lower.contains('failed host lookup') ||
      lower.contains('socketexception')) {
    return DaemonErrorKind.keychainOrStarting;
  }
  return DaemonErrorKind.courierDown;
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
        title: "Couldn't load session",
        body:
            'The local courier is running. Loading your account timed out — '
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
  return lower.contains('connection refused') ||
      lower.contains('missing http token') ||
      lower.contains('failed host lookup') ||
      lower.contains('socketexception');
}
