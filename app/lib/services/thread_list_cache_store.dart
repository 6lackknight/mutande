import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'daemon_client.dart';

/// Last-known thread list rows per filter — stale-while-revalidate for the UI.
///
/// Ciphertext stays on the hub; this only stores metadata the daemon already
/// returned from a prior successful `list_threads` (snippets, status, times).
class ThreadListCacheStore {
  ThreadListCacheStore({this.path});

  final String? path;

  static const _fileName = 'thread_list_cache.json';

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
    final snap = await _readFilter(filter);
    if (snap == null) return false;
    final saved = DateTime.tryParse(snap.savedAt);
    if (saved == null) return false;
    return DateTime.now().difference(saved) <= maxAge;
  }

  Future<List<ThreadSummary>?> load(String filter) async {
    final snap = await _readFilter(filter);
    if (snap == null) return null;
    return snap.threads;
  }

  Future<void> save(String filter, List<ThreadSummary> threads) async {
    if (kIsWeb) return;
    final root = await _readRoot();
    root[filter] = _FilterSnapshot(
      savedAt: DateTime.now().toUtc().toIso8601String(),
      threads: threads,
    );
    await _writeRoot(root);
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
