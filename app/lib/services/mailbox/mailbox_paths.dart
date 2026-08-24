import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../platform/user_home.dart';

/// Application Support / Caches paths for the local mailbox (not `~/.mutande/`).
class MailboxPaths {
  MailboxPaths({this.userId, this.rootOverride});

  /// Auth0 subject / hub user id — isolates mailboxes across accounts.
  final String? userId;

  /// Tests inject a temp directory.
  final String? rootOverride;

  static const appSupportName = 'ai.mutande.app';

  String get _userSegment {
    final raw = (userId ?? 'anonymous').trim();
    if (raw.isEmpty) return 'anonymous';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '_');
  }

  String get supportRoot {
    if (rootOverride != null) return rootOverride!;
    if (kIsWeb) {
      return Directory.systemTemp.createTempSync('mutande-mailbox-').path;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return p.join(Directory.systemTemp.path, 'mutande-test-mailbox');
    }
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      return Directory.systemTemp.createTempSync('mutande-mailbox-').path;
    }
    if (Platform.isMacOS) {
      return p.join(home, 'Library', 'Application Support', appSupportName);
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, appSupportName);
      }
    }
    return p.join(home, '.local', 'share', appSupportName);
  }

  String get cacheRoot {
    if (rootOverride != null) return p.join(rootOverride!, 'cache');
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return p.join(supportRoot, 'cache');
    }
    final home = userHomeDir();
    if (home == null || home.isEmpty) {
      return p.join(supportRoot, 'cache');
    }
    if (Platform.isMacOS) {
      return p.join(home, 'Library', 'Caches', appSupportName);
    }
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA']?.trim();
      if (local != null && local.isNotEmpty) {
        return p.join(local, appSupportName, 'Cache');
      }
    }
    return p.join(home, '.cache', appSupportName);
  }

  String get mailboxDir => p.join(supportRoot, 'mailbox', _userSegment);

  String get dbPath => p.join(mailboxDir, 'mailbox.db');

  String get mediaDir => p.join(mailboxDir, 'media');

  String get previewDir => p.join(cacheRoot, 'preview', _userSegment);

  Future<void> ensureDirs() async {
    for (final dir in [mailboxDir, mediaDir, previewDir]) {
      final d = Directory(dir);
      if (!await d.exists()) {
        await d.create(recursive: true);
      }
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['700', dir]);
        } catch (_) {}
      }
    }
  }
}
