import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/agent_transport.dart';
import '../platform/user_home.dart';
import 'daemon_client.dart';

/// Default-transport prefs per display slug.
///
/// Local file is a cache/offline fallback; when a [DaemonClient] is attached,
/// Settings syncs with hub `GET`/`PUT /v1/agents/transport-defaults` via the
/// courier (`get_transport_defaults` / `set_transport_default` RPCs).
class TransportPrefs {
  const TransportPrefs({this.defaultBySlug = const {}});

  factory TransportPrefs.fromJson(Map<String, dynamic> map) {
    final defaults = <String, AgentTransport>{};
    // Hub wire: `{ defaults: { slug: transport } }`; local cache: `default_by_slug`.
    final raw = map['defaults'] ?? map['default_by_slug'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final t = AgentTransport.tryParse(e.value?.toString());
        if (t == null) continue;
        final slug = e.key.toString().trim().toLowerCase();
        if (slug.isEmpty) continue;
        defaults[slug] = t;
      }
    }
    return TransportPrefs(defaultBySlug: defaults);
  }

  /// Preferred transport for bare `@slug` resolution.
  final Map<String, AgentTransport> defaultBySlug;

  AgentTransport? defaultFor(String slug) =>
      defaultBySlug[slug.trim().toLowerCase()];

  TransportPrefs copyWith({Map<String, AgentTransport>? defaultBySlug}) {
    return TransportPrefs(defaultBySlug: defaultBySlug ?? this.defaultBySlug);
  }

  TransportPrefs withDefault(String slug, AgentTransport transport) {
    final next = Map<String, AgentTransport>.from(defaultBySlug);
    next[slug.trim().toLowerCase()] = transport;
    return copyWith(defaultBySlug: next);
  }

  Map<String, dynamic> toJson() => {
        'default_by_slug': {
          for (final e in defaultBySlug.entries) e.key: e.value.wireValue,
        },
      };

  /// Hub RPC body shape (`{ defaults: … }`).
  Map<String, dynamic> toHubJson() => {
        'defaults': {
          for (final e in defaultBySlug.entries) e.key: e.value.wireValue,
        },
      };
}

class TransportPrefsStore {
  TransportPrefsStore({
    this.file,
    TransportPrefs? memory,
    DaemonClient? daemon,
  })  : _memory = memory,
        daemon = daemon;

  factory TransportPrefsStore.memory([TransportPrefs? prefs]) =>
      TransportPrefsStore(memory: prefs ?? const TransportPrefs());

  final File? file;
  TransportPrefs? _memory;

  /// Courier used for hub sync; null keeps prefs local-only.
  DaemonClient? daemon;
  TransportPrefs _cached = const TransportPrefs();

  TransportPrefs get current => _memory ?? _cached;

  File _resolveFile() {
    final override = file;
    if (override != null) return override;
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      throw StateError('home directory is not set');
    }
    return File('$home/.mutande/transport_prefs.json');
  }

  Future<TransportPrefs> _loadLocal() async {
    if (_memory != null) return _memory!;
    try {
      final file = _resolveFile();
      if (!await file.exists()) {
        _cached = const TransportPrefs();
        return _cached;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        _cached = const TransportPrefs();
        return _cached;
      }
      _cached = TransportPrefs.fromJson(raw);
      return _cached;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TransportPrefsStore.load failed: $e\n$st');
      }
      _cached = const TransportPrefs();
      return _cached;
    }
  }

  Future<void> _saveLocal(TransportPrefs prefs) async {
    if (_memory != null) {
      _memory = prefs;
      return;
    }
    _cached = prefs;
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(prefs.toJson()));
  }

  /// Load local cache. Does not hit the hub — use [syncFromHub] when courier
  /// is healthy (Settings).
  Future<TransportPrefs> load() => _loadLocal();

  /// Pull hub transport-defaults when [daemon] is set; write through to local
  /// cache. On hub/courier failure, returns the last local prefs unchanged.
  Future<TransportPrefs> syncFromHub() async {
    final local = await _loadLocal();
    final client = daemon;
    if (client == null) return local;
    try {
      final remote = TransportPrefs.fromJson(await client.getTransportDefaults());
      await _saveLocal(remote);
      return remote;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TransportPrefsStore.syncFromHub failed: $e\n$st');
      }
      return local;
    }
  }

  Future<void> save(TransportPrefs prefs) async {
    await _saveLocal(prefs);
  }

  /// Persist preferred transport for [slug] locally, then push to hub when
  /// the courier is available. Local wins if hub PUT fails.
  Future<TransportPrefs> setDefault(String slug, AgentTransport transport) async {
    final next = (await _loadLocal()).withDefault(slug, transport);
    await _saveLocal(next);
    final client = daemon;
    if (client != null) {
      try {
        final remote = TransportPrefs.fromJson(
          await client.setTransportDefault(
            slug: slug,
            transport: transport,
          ),
        );
        await _saveLocal(remote);
        return remote;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('TransportPrefsStore.setDefault hub push failed: $e\n$st');
        }
      }
    }
    return next;
  }

  Future<TransportPrefs> update(
    TransportPrefs Function(TransportPrefs) fn,
  ) async {
    final next = fn(await load());
    await save(next);
    return next;
  }
}
