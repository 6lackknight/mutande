import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';

/// First-run gate flags under `~/.mutande/first_run.json`.
class FirstRunStore {
  FirstRunStore({File? file, Map<String, dynamic>? memory})
      : _file = file,
        _memory = memory;

  factory FirstRunStore.memory({
    bool connectComplete = false,
    bool pingComplete = false,
    bool notificationsComplete = false,
  }) =>
      FirstRunStore(
        memory: {
          'connect_complete': connectComplete,
          'ping_complete': pingComplete,
          'notifications_complete': notificationsComplete,
        },
      );

  final File? _file;
  Map<String, dynamic>? _memory;

  bool _connectComplete = false;
  bool _pingComplete = false;
  bool _notificationsComplete = false;
  bool _notificationsSkipped = false;
  bool _loaded = false;

  bool get connectComplete => _connectComplete;
  bool get pingComplete => _pingComplete;
  bool get notificationsComplete => _notificationsComplete;

  /// True when the banners ask was declined — support can tell a skip from a
  /// grant.
  bool get notificationsSkipped => _notificationsSkipped;

  /// True when all onboarding gates are satisfied. Notifications ride along
  /// with the ping step, so they don't gate on their own.
  bool get onboardingComplete => _connectComplete && _pingComplete;

  File _resolveFile() {
    if (_file != null) return _file!;
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      throw StateError('home directory is not set');
    }
    return File('$home/.mutande/first_run.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    if (_memory != null) {
      _connectComplete = _memory!['connect_complete'] == true;
      _pingComplete = _memory!['ping_complete'] == true;
      _notificationsComplete = _memory!['notifications_complete'] == true;
      _loaded = true;
      return;
    }
    try {
      final file = _resolveFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          _connectComplete = raw['connect_complete'] == true;
          _pingComplete = raw['ping_complete'] == true;
          _notificationsComplete = raw['notifications_complete'] == true;
          _notificationsSkipped = raw['notifications_skipped'] == true;
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('FirstRunStore.load failed: $e\n$st');
      }
    }
    _loaded = true;
  }

  /// Sync path for in-memory stores (widget tests / injectables).
  void loadMemorySync() {
    if (_memory == null) return;
    _connectComplete = _memory!['connect_complete'] == true;
    _pingComplete = _memory!['ping_complete'] == true;
    _notificationsComplete = _memory!['notifications_complete'] == true;
    _loaded = true;
  }

  Future<void> _persist() async {
    final payload = {
      'connect_complete': _connectComplete,
      'ping_complete': _pingComplete,
      'notifications_complete': _notificationsComplete,
      'notifications_skipped': _notificationsSkipped,
    };
    if (_memory != null) {
      _memory!
        ..clear()
        ..addAll(payload);
      return;
    }
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }

  Future<void> markConnectComplete() async {
    await load();
    _connectComplete = true;
    await _persist();
  }

  Future<void> markPingComplete() async {
    await load();
    _pingComplete = true;
    await _persist();
  }

  Future<void> markNotificationsComplete({bool skipped = false}) async {
    await load();
    _notificationsComplete = true;
    _notificationsSkipped = skipped;
    await _persist();
  }

  /// Debug-only: clear first-run gates so onboarding replays.
  Future<void> resetForDebug() async {
    _connectComplete = false;
    _pingComplete = false;
    _notificationsComplete = false;
    _notificationsSkipped = false;
    _loaded = true;
    await _persist();
  }
}
