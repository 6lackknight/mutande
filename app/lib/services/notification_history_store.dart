import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'sentry_report.dart';

class NotificationEntry {
  const NotificationEntry({
    required this.id,
    required this.threadId,
    required this.title,
    required this.body,
    required this.at,
    this.read = false,
    this.needsYou = false,
    this.agentSlug,
  });

  factory NotificationEntry.fromJson(Map<String, dynamic> map) {
    return NotificationEntry(
      id: map['id'] as String? ?? '',
      threadId: map['thread_id'] as String? ?? '',
      title: map['title'] as String? ?? 'mutande',
      body: map['body'] as String? ?? '',
      at: DateTime.tryParse(map['at'] as String? ?? '') ?? DateTime.now(),
      read: map['read'] == true,
      needsYou: map['needs_you'] == true,
      agentSlug: map['agent_slug'] as String?,
    );
  }

  final String id;
  final String threadId;
  final String title;
  final String body;
  final DateTime at;
  final bool read;
  final bool needsYou;
  final String? agentSlug;

  NotificationEntry copyWith({bool? read}) {
    return NotificationEntry(
      id: id,
      threadId: threadId,
      title: title,
      body: body,
      at: at,
      read: read ?? this.read,
      needsYou: needsYou,
      agentSlug: agentSlug,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'thread_id': threadId,
    'title': title,
    'body': body,
    'at': at.toUtc().toIso8601String(),
    'read': read,
    'needs_you': needsYou,
    if (agentSlug != null) 'agent_slug': agentSlug,
  };
}

/// Recent in-app notification log under `~/.mutande/notification_history.json`.
class NotificationHistoryStore extends ChangeNotifier {
  NotificationHistoryStore({File? file, List<NotificationEntry>? memory})
    : _file = file,
      _memory = memory;

  factory NotificationHistoryStore.memory([List<NotificationEntry>? entries]) =>
      NotificationHistoryStore(memory: entries ?? const []);

  static const _maxEntries = 50;

  final File? _file;
  List<NotificationEntry>? _memory;
  List<NotificationEntry> _entries = const [];
  bool _loaded = false;

  List<NotificationEntry> get entries => List.unmodifiable(_entries);

  int get unreadCount => _entries.where((e) => !e.read).length;

  File _resolveFile() {
    if (_file != null) return _file;
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      throw StateError('home directory is not set');
    }
    return File('$home/.mutande/notification_history.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    if (_memory != null) {
      _entries = List.of(_memory!);
      _loaded = true;
      return;
    }
    try {
      final file = _resolveFile();
      if (!await file.exists()) {
        _entries = const [];
        _loaded = true;
        return;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        _entries = const [];
        _loaded = true;
        return;
      }
      _entries = [
        for (final e in raw)
          if (e is Map<String, dynamic>) NotificationEntry.fromJson(e),
      ];
      _loaded = true;
    } catch (e, st) {
      reportHandledError(e, stackTrace: st, surface: 'notification_history_store');
      if (kDebugMode) {
        debugPrint('NotificationHistoryStore.load failed: $e\n$st');
      }
      _entries = const [];
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    if (_memory != null) {
      _memory = List.of(_entries);
      notifyListeners();
      return;
    }
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> record({
    required String threadId,
    required String title,
    required String body,
    bool needsYou = false,
    String? agentSlug,
  }) async {
    await load();
    final now = DateTime.now();
    final next = [
      NotificationEntry(
        id: '${now.microsecondsSinceEpoch}-$threadId',
        threadId: threadId,
        title: title,
        body: body,
        at: now,
        needsYou: needsYou,
        agentSlug: agentSlug,
      ),
      ..._entries.where((e) => e.threadId != threadId || e.body != body),
    ];
    _entries = next.take(_maxEntries).toList();
    await _persist();
  }

  Future<void> markRead(String id) async {
    await load();
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0 || _entries[i].read) return;
    _entries = [
      for (var j = 0; j < _entries.length; j++)
        j == i ? _entries[j].copyWith(read: true) : _entries[j],
    ];
    await _persist();
  }

  Future<void> markAllRead() async {
    await load();
    if (_entries.every((e) => e.read)) return;
    _entries = [for (final e in _entries) e.copyWith(read: true)];
    await _persist();
  }
}
