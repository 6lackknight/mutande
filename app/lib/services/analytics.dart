import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import '../config/app_config.dart';
import 'daemon_client.dart';

/// Product analytics (desktop). No mail content. Identify with Auth0 `sub` only.
class Analytics {
  Analytics._();

  static Mixpanel? _client;
  static bool _ready = false;
  static String? _identifiedSub;
  static final List<({String event, Map<String, dynamic>? props})> _pending =
      [];

  static bool get _enabled =>
      !WidgetsBinding.instance.runtimeType.toString().contains('Test');

  static Future<void> init({
    required AppConfig config,
    required String appVersion,
  }) async {
    if (!_enabled) return;
    final token = config.mixpanelToken.trim();
    if (token.isEmpty || _ready) return;

    try {
      _client = await Mixpanel.init(
        token,
        trackAutomaticEvents: false,
      );
      await _client!.registerSuperProperties({
        'app_version': appVersion,
        'platform': _platform,
        'surface': 'desktop',
      });
      _ready = true;
      if (_identifiedSub != null) {
        _client?.identify(_identifiedSub!);
      }
      for (final item in List<({String event, Map<String, dynamic>? props})>.from(
        _pending,
      )) {
        track(item.event, item.props);
      }
      _pending.clear();
    } catch (_) {
      // Analytics must never block app startup.
    }
  }

  static void track(String event, [Map<String, dynamic>? props]) {
    if (!_enabled) return;
    final clean = _cleanProps(props);
    if (!_ready) {
      _pending.add((event: event, props: clean));
      return;
    }
    _client?.track(event, properties: clean);
  }

  /// Stable Auth0 subject only — do not pass email.
  static void identifyAuth0Sub(String? sub) {
    if (!_enabled || sub == null || sub.isEmpty) return;
    if (_identifiedSub == sub) return;
    _identifiedSub = sub;
    if (!_ready) return;
    _client?.identify(sub);
  }

  static void syncIdentityFromStatus(DaemonStatusResult? status) {
    identifyAuth0Sub(status?.auth0Sub);
  }

  static void reset() {
    _identifiedSub = null;
    if (!_ready) return;
    _client?.reset();
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static Map<String, dynamic>? _cleanProps(Map<String, dynamic>? props) {
    if (props == null || props.isEmpty) return null;
    final blocked = RegExp(r'email|handle|password|token', caseSensitive: false);
    final clean = <String, dynamic>{};
    for (final entry in props.entries) {
      if (blocked.hasMatch(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is String || value is num || value is bool) {
        clean[entry.key] = value;
      }
    }
    return clean.isEmpty ? null : clean;
  }
}
