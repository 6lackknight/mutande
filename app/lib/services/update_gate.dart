import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'version_compare.dart';

/// Latest desktop alpha metadata from mutande.online.
class DesktopVersionInfo {
  const DesktopVersionInfo({
    required this.version,
    required this.channel,
    required this.downloadUrl,
    this.macArm64Url,
    this.macIntelUrl,
    this.winUrl,
  });

  factory DesktopVersionInfo.fromJson(Map<String, dynamic> json) {
    return DesktopVersionInfo(
      version: json['version'] as String? ?? '',
      channel: json['channel'] as String? ?? 'alpha',
      downloadUrl: json['download_url'] as String? ??
          'https://mutande.online/download',
      macArm64Url: json['mac_arm64_url'] as String?,
      macIntelUrl: json['mac_intel_url'] as String?,
      winUrl: json['win_url'] as String?,
    );
  }

  final String version;
  final String channel;
  final String downloadUrl;
  final String? macArm64Url;
  final String? macIntelUrl;
  final String? winUrl;

  /// Best direct installer URL for this platform, else the download picker page.
  String preferredDownloadUrl() {
    if (!kIsWeb && Platform.isWindows) {
      final win = winUrl?.trim();
      if (win != null && win.isNotEmpty) return win;
    }
    if (!kIsWeb && Platform.isMacOS) {
      final arm = macArm64Url?.trim();
      final intel = macIntelUrl?.trim();
      if (arm != null && arm.isNotEmpty) return arm;
      if (intel != null && intel.isNotEmpty) return intel;
    }
    return downloadUrl;
  }
}

/// Fetches the published alpha version from the web app.
class UpdateGateClient {
  UpdateGateClient({
    required this.webAppUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? http.Client();

  final String webAppUrl;
  final Duration timeout;
  final http.Client _http;

  Uri get _endpoint {
    final base = webAppUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/api/desktop-version');
  }

  Future<DesktopVersionInfo?> fetchLatest() async {
    final response = await _http.get(_endpoint).timeout(timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final version = VersionCompare.normalize(decoded['version'] as String?);
    if (version == null) return null;
    return DesktopVersionInfo.fromJson({...decoded, 'version': version});
  }

  /// When [latest] is newer than [currentVersion], returns [latest] to gate.
  DesktopVersionInfo? gateTarget({
    required String currentVersion,
    required DesktopVersionInfo latest,
  }) {
    final current = VersionCompare.normalize(currentVersion);
    final published = VersionCompare.normalize(latest.version);
    if (current == null || published == null) return null;
    if (VersionCompare.isOlder(current, published)) return latest;
    return null;
  }

  void close() => _http.close();
}
