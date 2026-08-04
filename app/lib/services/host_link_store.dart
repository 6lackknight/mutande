import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'daemon_client.dart';

/// Last-known MCP link outcome per AI host (`cursor`, `claude`, `chatgpt`).
class HostLinkRecord {
  const HostLinkRecord({
    required this.ok,
    this.path,
    this.note,
    required this.updatedAt,
  });

  factory HostLinkRecord.fromJson(Map<String, dynamic> map) {
    return HostLinkRecord(
      ok: map['ok'] == true,
      path: map['path'] as String?,
      note: map['note'] as String?,
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory HostLinkRecord.fromWrite(HostWriteResult write) {
    return HostLinkRecord(
      ok: write.ok,
      path: write.path,
      note: write.note,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (path != null) 'path': path,
        if (note != null) 'note': note,
        'updated_at': updatedAt.toIso8601String(),
      };

  final bool ok;
  final String? path;
  final String? note;
  final DateTime updatedAt;
}

/// Persists host link results under `~/.mutande/host_links.json`.
class HostLinkStore {
  HostLinkStore({File? file, Map<String, HostLinkRecord>? memory})
      : _file = file,
        _memory = memory;

  factory HostLinkStore.memory() => HostLinkStore(memory: {});

  final File? _file;
  Map<String, HostLinkRecord>? _memory;

  static const _knownHosts = ['cursor', 'claude', 'chatgpt'];

  File _resolveFile() {
    if (_file != null) return _file!;
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      throw StateError('home directory is not set');
    }
    return File('$home/.mutande/host_links.json');
  }

  Future<Map<String, HostLinkRecord>> load() async {
    if (_memory != null) {
      return Map<String, HostLinkRecord>.from(_memory!);
    }
    try {
      final file = _resolveFile();
      if (!await file.exists()) return {};
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return {};
      final out = <String, HostLinkRecord>{};
      for (final entry in raw.entries) {
        if (entry.value is Map<String, dynamic>) {
          out[entry.key.toLowerCase()] =
              HostLinkRecord.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      return out;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('HostLinkStore.load failed: $e\n$st');
      }
      return {};
    }
  }

  Future<void> record(HostWriteResult write) async {
    final slug = write.host.toLowerCase();
    final next = HostLinkRecord.fromWrite(write);
    if (_memory != null) {
      _memory![slug] = next;
      return;
    }
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    final current = await load();
    current[slug] = next;
    final encoded = <String, dynamic>{
      for (final h in _knownHosts)
        if (current[h] != null) h: current[h]!.toJson(),
      for (final e in current.entries)
        if (!_knownHosts.contains(e.key)) e.key: e.value.toJson(),
    };
    await file.writeAsString(jsonEncode(encoded));
  }
}
