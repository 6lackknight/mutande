import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/address_display.dart';
import 'app_actions.dart';
import 'daemon_client.dart';
import 'sentry_report.dart';
import 'notification_history_store.dart';
import 'notification_prefs_store.dart';

/// Polls hub threads and shows local macOS notifications for new pending mail.
class InboxWatchService {
  InboxWatchService({
    required DaemonClient daemon,
    NotificationPrefsStore? prefs,
    NotificationHistoryStore? history,
    this.pollInterval = const Duration(seconds: 30),
  })  : _daemon = daemon,
        _prefs = prefs ?? NotificationPrefsStore(),
        _history = history;

  final DaemonClient _daemon;
  final NotificationPrefsStore _prefs;
  final NotificationHistoryStore? _history;
  final Duration pollInterval;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Timer? _timer;
  bool _started = false;
  bool _tickInFlight = false;
  bool _initialized = false;
  bool _hasBaseline = false;

  /// thread_id → last notified signature.
  final Map<String, String> _notified = {};

  Future<void> start() async {
    if (_started || kIsWeb) return;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    _started = true;
    await _ensureInitialized();
    unawaited(_tick());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const init = InitializationSettings(
      macOS: darwin,
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    );
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload?.trim();
        if (id != null && id.isNotEmpty) {
          AppActions.requestOpenThread(id);
        }
      },
    );
    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: false);
    }
    _initialized = true;
  }

  Future<void> _tick() async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      final prefs = await _prefs.load();
      if (!prefs.enabled) return;

      final threads = await _daemon.listThreads();
      final openIds = <String>{};

      if (!_hasBaseline) {
        for (final t in threads) {
          if (t.status != 'open') continue;
          _notified[t.id] = _sig(t);
          openIds.add(t.id);
        }
        _hasBaseline = true;
        return;
      }

      for (final t in threads) {
        if (t.status != 'open') continue;
        openIds.add(t.id);
        if (prefs.isMuted(t.id)) {
          _notified[t.id] = _sig(t);
          continue;
        }

        final needsYou = t.yourStatus == 'pending';
        String? agentFromAwaiting;
        for (final e in t.awaiting) {
          if (e.actor != 'agent') continue;
          final slug = _audienceAgentSlug(e.address);
          if (slug != null) {
            agentFromAwaiting = slug;
            break;
          }
        }
        final agentSlug = agentFromAwaiting ?? _audienceAgentSlug(t.audience);
        final isGroup = t.audience.trim() == '@all';
        final forAgent = prefs.mailForAgents &&
            (isGroup ||
                (agentSlug != null && prefs.isAgentEnabled(agentSlug)));
        final forHuman = needsYou && prefs.needsYou;

        if (!forHuman && !forAgent) {
          _notified[t.id] = _sig(t);
          continue;
        }

        // Prefer agent-mail banners when audience is an agent/group;
        // Needs you when pending for the human.
        final humanBanner = forHuman && !forAgent;
        if (!humanBanner && !forAgent) continue;

        final sig = _sig(t);
        if (_notified[t.id] == sig) continue;
        _notified[t.id] = sig;

        await _show(
          t,
          agentSlug: isGroup ? 'all' : agentSlug,
          needsYou: humanBanner,
        );
      }

      _notified.removeWhere((id, _) => !openIds.contains(id));
    } catch (e, st) {
      reportHandledError(e, stackTrace: st, surface: 'inbox_watch');
      if (kDebugMode) {
        debugPrint('InboxWatchService tick failed: $e\n$st');
      }
    } finally {
      _tickInFlight = false;
    }
  }

  String _sig(ThreadSummary t) =>
      '${t.yourStatus}|${t.awaiting.map((e) => '${e.actor}:${e.address}').join(',')}|${t.updatedAt}|${t.replyCount}';

  Future<void> _show(
    ThreadSummary t, {
    String? agentSlug,
    required bool needsYou,
  }) async {
    await _ensureInitialized();
    final from = t.from.trim().isNotEmpty
        ? formatMailAddress(t.from)
        : 'someone';
    final String body;
    if (needsYou) {
      body = 'Needs you — from $from';
    } else {
      final agent = agentSlug != null ? '@$agentSlug' : 'an agent';
      body = 'new mail for $agent from $from';
    }
    await _plugin.show(
      t.id.hashCode & 0x7fffffff,
      'mutande',
      body,
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      ),
      payload: t.id,
    );
    await _history?.record(
      threadId: t.id,
      title: 'mutande',
      body: body,
      needsYou: needsYou,
      agentSlug: agentSlug,
    );
  }
}

String? _audienceAgentSlug(String audience) {
  final a = audience.trim();
  if (a.isEmpty) return null;
  if (a == '@all' || a.startsWith('@all@')) return null;
  if (a.startsWith('@') && !a.substring(1).contains('@') && !a.contains('/')) {
    return a.substring(1).toLowerCase();
  }
  final slash = a.lastIndexOf('/');
  if (slash > 0 && slash < a.length - 1) {
    return a.substring(slash + 1).toLowerCase();
  }
  return null;
}
