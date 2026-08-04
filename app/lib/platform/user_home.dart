import 'dart:io';

/// Login home directory across macOS / Windows / Linux.
String? userHomeDir() {
  final home = Platform.environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) return home;
  final profile = Platform.environment['USERPROFILE']?.trim();
  if (profile != null && profile.isNotEmpty) return profile;
  final homeDrive = Platform.environment['HOMEDRIVE']?.trim();
  final homePath = Platform.environment['HOMEPATH']?.trim();
  if (homeDrive != null &&
      homeDrive.isNotEmpty &&
      homePath != null &&
      homePath.isNotEmpty) {
    return '$homeDrive$homePath';
  }
  return null;
}

/// Expand a `~/…` path using [userHomeDir].
String expandUserPath(String path) {
  if (path == '~') {
    return userHomeDir() ?? path;
  }
  if (path.startsWith('~/')) {
    final home = userHomeDir();
    if (home == null || home.isEmpty) return path;
    return '$home/${path.substring(2)}';
  }
  return path;
}
