import 'package:flutter/foundation.dart';

/// Load-path timing for mailbox / sync / open. Look for `[mutande.mail]` in
/// the Flutter console (debug / profile).
class MailTrace {
  MailTrace._();

  static const enabled = true;

  static Stopwatch start(String label) {
    final sw = Stopwatch()..start();
    _log('→ $label');
    return sw;
  }

  static void end(
    Stopwatch sw,
    String label, {
    Map<String, Object?>? fields,
  }) {
    sw.stop();
    final buf = StringBuffer('← $label ${sw.elapsedMilliseconds}ms');
    if (fields != null && fields.isNotEmpty) {
      for (final e in fields.entries) {
        buf.write(' ${e.key}=${e.value}');
      }
    }
    _log(buf.toString());
  }

  static void event(String message, {Map<String, Object?>? fields}) {
    final buf = StringBuffer(message);
    if (fields != null && fields.isNotEmpty) {
      for (final e in fields.entries) {
        buf.write(' ${e.key}=${e.value}');
      }
    }
    _log(buf.toString());
  }

  static void _log(String message) {
    if (!enabled) return;
    // Always print in debug/profile so load times are visible without flags.
    if (kReleaseMode) return;
    debugPrint('[mutande.mail] $message');
  }
}
