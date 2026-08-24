import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'daemon_client.dart';
import 'mailbox/mailbox_store.dart';

/// Last-known thread list rows per filter — stale-while-revalidate for the UI.
///
/// Prefers [MailboxStore] when open; falls back to plaintext JSON for bootstrap
/// before the mailbox is ready (and for older installs).
class ThreadListCacheStore {
  ThreadListCacheStore({this.path, this.mailbox});

  final String? path;

  /// Optional injected mailbox (tests). Defaults to [MailboxStore.instance].
  final MailboxStore? mailbox;

  static const _fileName = 'thread_list_cache.json';

  MailboxStore? get _box => mailbox ?? MailboxStore.instance;

  String get _filePath {
    if (path != null) return path!;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return '${Directory.systemTemp.path}/mutande-test-$_fileName';
    }
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      return Directory.systemTemp.createTempSync('mutande-cache-').path;
    }
    return '$home/.mutande/$_fileName';
  }

  /// True when we have a recent successful snapshot (including empty inbox).
  Future<bool> hasRecentSnapshot({
    String filter = 'all',
    Duration maxAge = const Duration(days: 7),
  }) async {
    final box = _box;
    if (box != null) {
      return box.hasRecentThreadList(filter: filter, maxAge: maxAge);
    }
    final snap = await _readFilter(filter);
    if (snap == null) return false;
    final saved = DateTime.tryParse(snap.savedAt);
    if (saved == null) return false;
    return DateTime.now().difference(saved) <= maxAge;
  }

  Future<List<ThreadSummary>?> load(String filter) async {
    final box = _box;
    if (box != null) {
      return box.loadThreadList(filter);
    }
    final snap = await _readFilter(filter);
    if (snap == null) return null;
    return snap.threads;
  }

  Future<void> save(String filter, List<ThreadSummary> threads) async {
    if (kIsWeb) return;
    final box = _box;
    if (box != null) {
      await box.saveThreadList(filter, threads);
      // Drop plaintext fallback once mailbox owns the list.
      await _deleteLegacyFile();
      return;
    }
    final root = await _readRoot();
    root[filter] = _FilterSnapshot(
      savedAt: DateTime.now().toUtc().toIso8601String(),
      threads: threads,
    );
    await _writeRoot(root);
  }

  Future<void> _deleteLegacyFile() async {
    try {
      final file = File(_filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<_FilterSnapshot?> _readFilter(String filter) async {
    final root = await _readRoot();
    return root[filter];
  }

  Future<Map<String, _FilterSnapshot>> _readRoot() async {
    if (kIsWeb) return {};
    try {
      final file = File(_filePath);
      if (!await file.exists()) return {};
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return {};
      final out = <String, _FilterSnapshot>{};
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          out[entry.key.toString()] =
              _FilterSnapshot.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeRoot(Map<String, _FilterSnapshot> root) async {
    if (kIsWeb) return;
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['700', file.parent.path]);
      } catch (_) {}
    }
    final encoded = <String, dynamic>{
      for (final e in root.entries) e.key: e.value.toJson(),
    };
    await file.writeAsString(jsonEncode(encoded));
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }
}

class _FilterSnapshot {
  const _FilterSnapshot({required this.savedAt, required this.threads});

  final String savedAt;
  final List<ThreadSummary> threads;

  factory _FilterSnapshot.fromJson(Map<String, dynamic> map) {
    final raw = map['threads'];
    final threads = <ThreadSummary>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          threads.add(ThreadSummary.fromJson(item));
        }
      }
    }
    return _FilterSnapshot(
      savedAt: map['saved_at'] as String? ?? '',
      threads: threads,
    );
  }

  Map<String, dynamic> toJson() => {
        'saved_at': savedAt,
        'threads': [for (final t in threads) t.toJson()],
      };
}
