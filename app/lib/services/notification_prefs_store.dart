import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'sentry_report.dart';

/// Local notification + mute prefs under `~/.mutande/notification_prefs.json`.
class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.mailForAgents = true,
    this.needsYou = true,
    this.mutedThreadIds = const {},
    this.agentSlugsEnabled = const {
      'cursor': true,
      'claude': true,
      'chatgpt': true,
    },
    this.threadInspectorVisible = true,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> map) {
    final muted = <String>{};
    final rawMuted = map['muted_thread_ids'];
    if (rawMuted is List) {
      for (final e in rawMuted) {
        final id = e.toString().trim();
        if (id.isNotEmpty) muted.add(id);
      }
    }
    final agents = <String, bool>{
      'cursor': true,
      'claude': true,
      'chatgpt': true,
    };
    final rawAgents = map['agent_slugs_enabled'];
    if (rawAgents is Map) {
      for (final e in rawAgents.entries) {
        agents[e.key.toString().toLowerCase()] = e.value == true;
      }
    }
    return NotificationPrefs(
      enabled: map['enabled'] != false,
      mailForAgents: map['mail_for_agents'] != false,
      needsYou: map['needs_you'] != false,
      mutedThreadIds: muted,
      agentSlugsEnabled: agents,
      threadInspectorVisible: map['thread_inspector_visible'] != false,
    );
  }

  final bool enabled;
  final bool mailForAgents;
  final bool needsYou;
  final Set<String> mutedThreadIds;
  final Map<String, bool> agentSlugsEnabled;
  final bool threadInspectorVisible;

  bool isAgentEnabled(String slug) =>
      agentSlugsEnabled[slug.toLowerCase()] ?? true;

  bool isMuted(String threadId) => mutedThreadIds.contains(threadId);

  NotificationPrefs copyWith({
    bool? enabled,
    bool? mailForAgents,
    bool? needsYou,
    Set<String>? mutedThreadIds,
    Map<String, bool>? agentSlugsEnabled,
    bool? threadInspectorVisible,
  }) {
    return NotificationPrefs(
      enabled: enabled ?? this.enabled,
      mailForAgents: mailForAgents ?? this.mailForAgents,
      needsYou: needsYou ?? this.needsYou,
      mutedThreadIds: mutedThreadIds ?? this.mutedThreadIds,
      agentSlugsEnabled: agentSlugsEnabled ?? this.agentSlugsEnabled,
      threadInspectorVisible:
          threadInspectorVisible ?? this.threadInspectorVisible,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mail_for_agents': mailForAgents,
    'needs_you': needsYou,
    'muted_thread_ids': mutedThreadIds.toList()..sort(),
    'agent_slugs_enabled': agentSlugsEnabled,
    'thread_inspector_visible': threadInspectorVisible,
  };
}

class NotificationPrefsStore {
  NotificationPrefsStore({File? file, NotificationPrefs? memory})
    : _file = file,
      _memory = memory;

  factory NotificationPrefsStore.memory([NotificationPrefs? prefs]) =>
      NotificationPrefsStore(memory: prefs ?? const NotificationPrefs());

  final File? _file;
  NotificationPrefs? _memory;
  NotificationPrefs _cached = const NotificationPrefs();

  NotificationPrefs get current => _memory ?? _cached;

  File _resolveFile() {
    if (_file != null) return _file!;
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      throw StateError('home directory is not set');
    }
    return File('$home/.mutande/notification_prefs.json');
  }

  Future<NotificationPrefs> load() async {
    if (_memory != null) return _memory!;
    try {
      final file = _resolveFile();
      if (!await file.exists()) {
        _cached = const NotificationPrefs();
        return _cached;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        _cached = const NotificationPrefs();
        return _cached;
      }
      _cached = NotificationPrefs.fromJson(raw);
      return _cached;
    } catch (e, st) {
      reportHandledError(e, stackTrace: st, surface: 'notification_prefs_store');
      if (kDebugMode) {
        debugPrint('NotificationPrefsStore.load failed: $e\n$st');
      }
      _cached = const NotificationPrefs();
      return _cached;
    }
  }

  Future<void> save(NotificationPrefs prefs) async {
    if (_memory != null) {
      _memory = prefs;
      return;
    }
    _cached = prefs;
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(prefs.toJson()));
  }

  Future<NotificationPrefs> update(
    NotificationPrefs Function(NotificationPrefs) fn,
  ) async {
    final next = fn(await load());
    await save(next);
    return next;
  }

  Future<void> setMuted(String threadId, bool muted) async {
    await update((p) {
      final ids = Set<String>.from(p.mutedThreadIds);
      if (muted) {
        ids.add(threadId);
      } else {
        ids.remove(threadId);
      }
      return p.copyWith(mutedThreadIds: ids);
    });
  }
}
