import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'daemon_client.dart';

/// Skill install outcome persisted next to MCP link.
enum SkillLinkStatus {
  /// Not attempted / unknown.
  none,

  /// Auto-written successfully.
  installed,

  /// Manual steps required (e.g. Claude ZIP) or auto write failed.
  needsSetup,

  /// User skipped skill step.
  skipped,
}

SkillLinkStatus skillLinkStatusFromString(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'installed':
      return SkillLinkStatus.installed;
    case 'needs_setup':
      return SkillLinkStatus.needsSetup;
    case 'skipped':
      return SkillLinkStatus.skipped;
    default:
      return SkillLinkStatus.none;
  }
}

String skillLinkStatusToString(SkillLinkStatus s) {
  switch (s) {
    case SkillLinkStatus.installed:
      return 'installed';
    case SkillLinkStatus.needsSetup:
      return 'needs_setup';
    case SkillLinkStatus.skipped:
      return 'skipped';
    case SkillLinkStatus.none:
      return 'none';
  }
}

/// Last-known MCP + skill link outcome per AI host (`cursor`, `claude`, `chatgpt`).
class HostLinkRecord {
  const HostLinkRecord({
    required this.ok,
    this.path,
    this.command,
    this.note,
    required this.updatedAt,
    this.skillStatus = SkillLinkStatus.none,
    this.skillPath,
    this.skillZipPath,
    this.skillHint,
  });

  factory HostLinkRecord.fromJson(Map<String, dynamic> map) {
    return HostLinkRecord(
      ok: map['ok'] == true,
      path: map['path'] as String?,
      command: map['command'] as String?,
      note: map['note'] as String?,
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      skillStatus: skillLinkStatusFromString(map['skill_status'] as String?),
      skillPath: map['skill_path'] as String?,
      skillZipPath: map['skill_zip_path'] as String?,
      skillHint: map['skill_hint'] as String?,
    );
  }

  factory HostLinkRecord.fromWrite(HostWriteResult write) {
    return HostLinkRecord(
      ok: write.ok,
      path: write.path,
      command: write.command,
      note: write.note,
      updatedAt: DateTime.now(),
    );
  }

  HostLinkRecord copyWith({
    bool? ok,
    String? path,
    String? command,
    String? note,
    DateTime? updatedAt,
    SkillLinkStatus? skillStatus,
    String? skillPath,
    String? skillZipPath,
    String? skillHint,
  }) {
    return HostLinkRecord(
      ok: ok ?? this.ok,
      path: path ?? this.path,
      command: command ?? this.command,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
      skillStatus: skillStatus ?? this.skillStatus,
      skillPath: skillPath ?? this.skillPath,
      skillZipPath: skillZipPath ?? this.skillZipPath,
      skillHint: skillHint ?? this.skillHint,
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (path != null) 'path': path,
        if (command != null) 'command': command,
        if (note != null) 'note': note,
        'updated_at': updatedAt.toIso8601String(),
        'skill_status': skillLinkStatusToString(skillStatus),
        if (skillPath != null) 'skill_path': skillPath,
        if (skillZipPath != null) 'skill_zip_path': skillZipPath,
        if (skillHint != null) 'skill_hint': skillHint,
      };

  final bool ok;
  /// Host MCP config file path (e.g. claude_desktop_config.json).
  final String? path;
  /// Absolute `mutande-core` path written into that config.
  final String? command;
  final String? note;
  final DateTime updatedAt;
  final SkillLinkStatus skillStatus;
  final String? skillPath;
  final String? skillZipPath;
  final String? skillHint;
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

  Future<void> _persist(Map<String, HostLinkRecord> current) async {
    if (_memory != null) {
      _memory!
        ..clear()
        ..addAll(current);
      return;
    }
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    final encoded = <String, dynamic>{
      for (final h in _knownHosts)
        if (current[h] != null) h: current[h]!.toJson(),
      for (final e in current.entries)
        if (!_knownHosts.contains(e.key)) e.key: e.value.toJson(),
    };
    await file.writeAsString(jsonEncode(encoded));
  }

  Future<void> record(HostWriteResult write) async {
    final slug = write.host.toLowerCase();
    final current = await load();
    final prev = current[slug];
    final next = HostLinkRecord.fromWrite(write).copyWith(
      skillStatus: prev?.skillStatus ?? SkillLinkStatus.none,
      skillPath: prev?.skillPath,
      skillZipPath: prev?.skillZipPath,
      skillHint: prev?.skillHint,
    );
    current[slug] = next;
    await _persist(current);
  }

  Future<void> recordSkill({
    required String host,
    required SkillLinkStatus status,
    String? path,
    String? zipPath,
    String? hint,
  }) async {
    final slug = host.toLowerCase();
    final current = await load();
    final prev = current[slug];
    if (prev == null) {
      current[slug] = HostLinkRecord(
        ok: false,
        updatedAt: DateTime.now(),
        skillStatus: status,
        skillPath: path,
        skillZipPath: zipPath,
        skillHint: hint,
      );
    } else {
      current[slug] = prev.copyWith(
        skillStatus: status,
        skillPath: path,
        skillZipPath: zipPath,
        skillHint: hint,
        updatedAt: DateTime.now(),
      );
    }
    await _persist(current);
  }
}
