import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// First-run gate flags under `~/.mutande/first_run.json`.
class FirstRunStore {
  FirstRunStore({File? file, Map<String, dynamic>? memory})
      : _file = file,
        _memory = memory;

  factory FirstRunStore.memory({
    bool connectComplete = false,
    bool pingComplete = false,
  }) =>
      FirstRunStore(
        memory: {
          'connect_complete': connectComplete,
          'ping_complete': pingComplete,
        },
      );

  final File? _file;
  Map<String, dynamic>? _memory;

  bool _connectComplete = false;
  bool _pingComplete = false;
  bool _loaded = false;

  bool get connectComplete => _connectComplete;
  bool get pingComplete => _pingComplete;

  File _resolveFile() {
    if (_file != null) return _file!;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is not set');
    }
    return File('$home/.mutande/first_run.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    if (_memory != null) {
      _connectComplete = _memory!['connect_complete'] == true;
      _pingComplete = _memory!['ping_complete'] == true;
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
    _loaded = true;
  }

  Future<void> _persist() async {
    final payload = {
      'connect_complete': _connectComplete,
      'ping_complete': _pingComplete,
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
}
