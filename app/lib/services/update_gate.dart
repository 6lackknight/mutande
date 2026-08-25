import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'version_compare.dart';

/// Machine we should fetch an installer for (hardware, not Rosetta ABI).
enum DesktopCpu {
  macArm64,
  macX64,
  windows,
  other;

  /// Apple Silicon via `sysctl` even when the process is x86_64 under Rosetta.
  static DesktopCpu detect() {
    if (kIsWeb) return other;
    if (Platform.isWindows) return windows;
    if (!Platform.isMacOS) return other;
    if (_appleSiliconHardware()) return macArm64;
    return switch (Abi.current()) {
      Abi.macosArm64 => macArm64,
      Abi.macosX64 => macX64,
      _ => other,
    };
  }

  static bool _appleSiliconHardware() {
    try {
      final result = Process.runSync('sysctl', ['-n', 'hw.optional.arm64']);
      return result.exitCode == 0 && result.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }
}

/// Soft vs blocking prompt when the published alpha is newer.
class UpdatePrompt {
  const UpdatePrompt({required this.latest, required this.skippable});

  final DesktopVersionInfo latest;
  final bool skippable;
}

/// Latest desktop alpha metadata from mutande.online.
class DesktopVersionInfo {
  const DesktopVersionInfo({
    required this.version,
    required this.channel,
    required this.downloadUrl,
    this.minVersion,
    this.macArm64Url,
    this.macIntelUrl,
    this.winUrl,
    this.macIntelPublished = true,
    this.winPublished = true,
  });

  factory DesktopVersionInfo.fromJson(Map<String, dynamic> json) {
    final published =
        VersionCompare.normalize(json['version'] as String?) ??
        publishedVersionFromJson(json) ??
        '';
    return DesktopVersionInfo(
      version: published,
      channel: json['channel'] as String? ?? 'alpha',
      downloadUrl: json['download_url'] as String? ??
          'https://mutande.online/download',
      minVersion: VersionCompare.normalize(json['min_version'] as String?),
      macArm64Url: json['mac_arm64_url'] as String?,
      macIntelUrl: json['mac_intel_url'] as String?,
      winUrl: json['win_url'] as String?,
      macIntelPublished: json['mac_intel_published'] != false,
      winPublished: json['win_published'] != false,
    );
  }

  /// Platform-specific semver from `/api/desktop-version`.
  static String? publishedVersionFromJson(Map<String, dynamic> json) {
    if (!kIsWeb && Platform.isWindows) {
      return VersionCompare.normalize(json['windows_version'] as String?) ??
          VersionCompare.normalize(json['version'] as String?);
    }
    return VersionCompare.normalize(json['version'] as String?);
  }

  final String version;
  final String channel;
  final String downloadUrl;

  /// When set, builds older than this cannot skip — they must reinstall.
  final String? minVersion;
  final String? macArm64Url;
  final String? macIntelUrl;
  final String? winUrl;
  final bool macIntelPublished;
  final bool winPublished;

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Direct installer for this CPU, else the waitlist download page.
  String preferredDownloadUrl({DesktopCpu? cpu}) {
    cpu ??= DesktopCpu.detect();
    switch (cpu) {
      case DesktopCpu.windows:
        if (winPublished) {
          final win = _nonEmpty(winUrl);
          if (win != null) return win;
        }
        return downloadUrl;
      case DesktopCpu.macArm64:
        return _nonEmpty(macArm64Url) ?? downloadUrl;
      case DesktopCpu.macX64:
        if (macIntelPublished) {
          final intel = _nonEmpty(macIntelUrl);
          if (intel != null) return intel;
        }
        return downloadUrl;
      case DesktopCpu.other:
        return downloadUrl;
    }
  }

  String downloadButtonLabel({DesktopCpu? cpu}) {
    cpu ??= DesktopCpu.detect();
    return switch (cpu) {
      DesktopCpu.macArm64 => 'Download Silicon update',
      DesktopCpu.macX64
          when macIntelPublished && _nonEmpty(macIntelUrl) != null =>
        'Download Intel update',
      DesktopCpu.windows when winPublished && _nonEmpty(winUrl) != null =>
        'Download Windows update',
      _ => 'Download update',
    };
  }
}

/// Fetches the published alpha version from the web app.
class UpdateGateClient {
  UpdateGateClient({
    required this.webAppUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 5),
  }) : _http = httpClient ?? http.Client();

  final String webAppUrl;
  final Duration timeout;
  final http.Client _http;

  Uri get _endpoint {
    final base = webAppUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/api/desktop-version');
  }

  Future<DesktopVersionInfo?> fetchLatest() async {
    try {
      final response = await _http.get(_endpoint).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('desktop-version timed out'),
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final version = DesktopVersionInfo.publishedVersionFromJson(decoded);
      if (version == null) return null;
      return DesktopVersionInfo.fromJson({...decoded, 'version': version});
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// When [latest] is newer than [currentVersion], returns [latest] to gate.
  DesktopVersionInfo? gateTarget({
    required String currentVersion,
    required DesktopVersionInfo latest,
  }) {
    return prompt(
      currentVersion: currentVersion,
      latest: latest,
    )?.latest;
  }

  /// Newer published alpha: skippable unless [latest.minVersion] is above us.
  UpdatePrompt? prompt({
    required String currentVersion,
    required DesktopVersionInfo latest,
    String? skippedVersion,
  }) {
    if (!VersionCompare.isOlder(currentVersion, latest.version)) return null;

    final min = latest.minVersion;
    final required = min != null && VersionCompare.isOlder(currentVersion, min);
    if (!required) {
      final skipped = VersionCompare.normalize(skippedVersion);
      final published = VersionCompare.normalize(latest.version);
      if (skipped != null && skipped == published) return null;
    }
    return UpdatePrompt(latest: latest, skippable: !required);
  }

  void close() => _http.close();
}
