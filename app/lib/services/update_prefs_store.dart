import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/user_home.dart';
import 'sentry_report.dart';
import 'version_compare.dart';

/// Remembers which published alpha the user skipped (`~/.mutande/update_prefs.json`).
class UpdatePrefsStore {
  UpdatePrefsStore({File? file, Map<String, dynamic>? memory})
      : _file = file,
        _memory = memory;

  factory UpdatePrefsStore.memory({String? skippedVersion}) =>
      UpdatePrefsStore(
        memory: {
          if (skippedVersion != null) 'skipped_version': skippedVersion,
        },
      );

  final File? _file;
  Map<String, dynamic>? _memory;
  String? _skippedVersion;
  bool _loaded = false;

  String? get skippedVersion => _skippedVersion;

  File _resolveFile() {
    if (_file != null) return _file;
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      throw StateError('home directory is not set');
    }
    return File('$home/.mutande/update_prefs.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    if (_memory != null) {
      _skippedVersion = VersionCompare.normalize(
        _memory!['skipped_version'] as String?,
      );
      _loaded = true;
      return;
    }
    try {
      final file = _resolveFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          _skippedVersion = VersionCompare.normalize(
            raw['skipped_version'] as String?,
          );
        }
      }
    } catch (e, st) {
      reportHandledError(e, stackTrace: st, surface: 'update_prefs_store');
      if (kDebugMode) {
        debugPrint('UpdatePrefsStore.load failed: $e\n$st');
      }
    }
    _loaded = true;
  }

  Future<void> skipVersion(String version) async {
    final normalized = VersionCompare.normalize(version);
    _skippedVersion = normalized;
    if (_memory != null) {
      _memory!['skipped_version'] = normalized;
      return;
    }
    try {
      final file = _resolveFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'skipped_version': normalized}),
      );
    } catch (e, st) {
      reportHandledError(e, stackTrace: st, surface: 'update_prefs_store');
    }
  }
}
