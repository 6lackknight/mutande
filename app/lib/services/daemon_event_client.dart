import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../platform/user_home.dart';
import 'daemon_client.dart';

/// Metadata-only inbox change from mutande-core WebSocket (`GET /ws`).
class InboxChangedEvent {
  const InboxChangedEvent({required this.revision, required this.at});

  final int revision;
  final String at;

  factory InboxChangedEvent.fromJson(Map<String, dynamic> json) {
    return InboxChangedEvent(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      at: json['at'] as String? ?? '',
    );
  }
}

/// Long-lived `ws://127.0.0.1:3847/ws` client — subscribe to `inbox_changed`.
///
/// Reconnects with exponential backoff. Does not block app bootstrap.
class DaemonEventClient {
  DaemonEventClient({
    this.httpBaseUrl = DaemonClient.defaultHttpBaseUrl,
    this.httpTokenPath = DaemonClient.defaultHttpTokenPath,
    String? httpToken,
    this.minBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 30),
  }) : _httpTokenOverride = httpToken;

  final String httpBaseUrl;
  final String httpTokenPath;
  final String? _httpTokenOverride;
  final Duration minBackoff;
  final Duration maxBackoff;

  final _events = StreamController<InboxChangedEvent>.broadcast();
  final ValueNotifier<bool> connected = ValueNotifier(false);

  WebSocket? _ws;
  StreamSubscription? _sub;
  bool _stopped = true;
  bool _loopRunning = false;
  Duration _backoff = const Duration(milliseconds: 500);

  Stream<InboxChangedEvent> get events => _events.stream;

  /// Start reconnect loop (idempotent). No-op in widget tests / web.
  void start() {
    if (kIsWeb) return;
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      return;
    }
    _stopped = false;
    if (_loopRunning) return;
    _loopRunning = true;
    unawaited(_runLoop());
  }

  Future<void> dispose() async {
    _stopped = true;
    await _closeSocket();
    connected.value = false;
    await _events.close();
    connected.dispose();
  }

  Future<void> _runLoop() async {
    while (!_stopped) {
      try {
        await _connectOnce();
        _backoff = minBackoff;
        // Stay until socket closes.
        while (!_stopped && _ws != null) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } catch (_) {
        connected.value = false;
      }
      if (_stopped) break;
      await Future<void>.delayed(_backoff);
      final nextMs = (_backoff.inMilliseconds * 2).clamp(
        minBackoff.inMilliseconds,
        maxBackoff.inMilliseconds,
      );
      _backoff = Duration(milliseconds: nextMs);
    }
    _loopRunning = false;
  }

  Future<void> _connectOnce() async {
    final token = _resolveHttpToken();
    if (token == null || token.isEmpty) {
      throw StateError('missing daemon HTTP token');
    }
    final base = Uri.parse(httpBaseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final uri = base.replace(scheme: scheme, path: '/ws');
    final ws = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    );
    await _closeSocket();
    _ws = ws;
    connected.value = true;
    ws.add(jsonEncode({'op': 'subscribe', 'channel': 'inbox'}));
    _sub = ws.listen(
      (data) {
        if (data is! String) return;
        try {
          final map = jsonDecode(data) as Map<String, dynamic>;
          final event = map['event'] as String?;
          if (event == 'inbox_changed') {
            if (!_events.isClosed) {
              _events.add(InboxChangedEvent.fromJson(map));
            }
          }
        } catch (_) {}
      },
      onDone: () {
        connected.value = false;
        _ws = null;
      },
      onError: (_) {
        connected.value = false;
        _ws = null;
      },
      cancelOnError: true,
    );
  }

  Future<void> _closeSocket() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  String? _resolveHttpToken() {
    if (_httpTokenOverride != null) return _httpTokenOverride;
    final path = expandUserPath(httpTokenPath);
    final file = File(path);
    if (!file.existsSync()) return null;
    final token = file.readAsStringSync().trim();
    return token.isEmpty ? null : token;
  }
}
