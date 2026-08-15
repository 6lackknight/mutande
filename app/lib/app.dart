import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'config/app_config.dart';
import 'analytics_events.dart';
import 'screens/collab_screen.dart';
import 'screens/network_screen.dart';
import 'screens/onboarding_flow_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/threads_screen.dart';
import 'services/app_actions.dart';
import 'services/analytics.dart';
import 'services/daemon_client.dart';
import 'services/daemon_errors.dart';
import 'services/daemon_event_client.dart';
import 'services/first_run_store.dart';
import 'services/host_link_store.dart';
import 'services/inbox_watch_service.dart';
import 'services/notification_prefs_store.dart';
import 'services/thread_list_cache_store.dart';
import 'services/transport_prefs_store.dart';
import 'theme/mutande_macos_theme.dart';
import 'widgets/daemon_error_screen.dart';
import 'widgets/home_chrome_pills.dart';
import 'widgets/home_chrome_strip.dart';
import 'widgets/search_dialog.dart';
import 'widgets/thinking_orb.dart';
import 'widgets/onboarding_stepper.dart';
import 'widgets/welcome_splash.dart';

/// Back-compat alias for content Material theme.
ThemeData mutandeTheme() => mutandeMaterialTheme();

class MutandeApp extends StatefulWidget {
  const MutandeApp({
    super.key,
    required this.config,
    this.daemon,
    this.seedStatus,
    this.hostLinkStore,
    this.firstRunStore,
    this.welcomeDuration = const Duration(seconds: 3),
    this.appVersion = AppConfig.appVersion,
    this.startupRetryAttempts = 15,
    this.onRestartCourier,
  });

  final AppConfig config;

  /// Injectable for tests; defaults to a live HTTP daemon client.
  final DaemonClient? daemon;

  /// When set, skips the initial `get_status` RPC (widget tests).
  final DaemonStatusResult? seedStatus;

  /// Injectable for tests; defaults to file-backed store.
  final HostLinkStore? hostLinkStore;

  /// Injectable for tests; defaults to file-backed first-run flags.
  final FirstRunStore? firstRunStore;

  /// Dark orb welcome hold. Pass [Duration.zero] to skip (tests).
  final Duration welcomeDuration;

  /// pubspec version (before `+`), overridable via `--dart-define=APP_VERSION=`.
  final String appVersion;

  /// Retries while mutande-core / Keychain may still be starting (× 2s apart).
  final int startupRetryAttempts;

  /// When set (macOS shell), error screen can restart the bundled sidecar.
  final Future<String?> Function()? onRestartCourier;

  @override
  State<MutandeApp> createState() => _MutandeAppState();
}

class _MutandeAppState extends State<MutandeApp> {
  /// Welcome splash stays up until bootstrap finishes (covers Keychain prompts).
  final ValueNotifier<bool> _sessionReady = ValueNotifier(false);
  final ValueNotifier<String?> _splashStatus = ValueNotifier(null);

  @override
  void dispose() {
    _sessionReady.dispose();
    _splashStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = WelcomeSplash(
      duration: widget.welcomeDuration,
      appVersion: widget.appVersion,
      dismissWhen: _sessionReady,
      statusLabel: _splashStatus,
      child: RootScreen(
        config: widget.config,
        daemon: widget.daemon,
        seedStatus: widget.seedStatus,
        hostLinkStore: widget.hostLinkStore,
        firstRunStore: widget.firstRunStore,
        startupRetryAttempts: widget.startupRetryAttempts,
        appVersion: widget.appVersion,
        onRestartCourier: widget.onRestartCourier,
        onBootstrapPhase: (ready, status) {
          // Defer — RootScreen may emit from initState while splash is mounting.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _sessionReady.value = ready;
            _splashStatus.value = status;
          });
        },
      ),
    );

    // Windows alpha: Material shell (macos_ui is macOS-only).
    final useMaterial = !kIsWeb && Platform.isWindows;
    if (useMaterial) {
      return MaterialApp(
        title: 'mutande',
        theme: mutandeMaterialTheme(),
        debugShowCheckedModeBanner: false,
        home: home,
      );
    }

    return MacosApp(
      title: 'mutande',
      theme: mutandeMacosTheme(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      builder: (context, child) {
        return mutandeThemeBridge(child: child ?? const SizedBox.shrink());
      },
      home: home,
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({
    super.key,
    required this.config,
    this.daemon,
    this.seedStatus,
    this.hostLinkStore,
    this.firstRunStore,
    this.startupRetryAttempts = 15,
    this.appVersion = AppConfig.appVersion,
    this.onRestartCourier,
    this.onBootstrapPhase,
  });

  final AppConfig config;
  final DaemonClient? daemon;
  final DaemonStatusResult? seedStatus;
  final HostLinkStore? hostLinkStore;
  final FirstRunStore? firstRunStore;
  final int startupRetryAttempts;
  final String appVersion;
  final Future<String?> Function()? onRestartCourier;

  /// Reports bootstrap readiness + splash status (Keychain wait, etc.).
  final void Function(bool ready, String? status)? onBootstrapPhase;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  /// Debug: replay onboarding on launch (`--dart-define=FORCE_ONBOARDING=false` to disable).
  static const _forceOnboardingFlag = bool.fromEnvironment(
    'FORCE_ONBOARDING',
    defaultValue: true,
  );

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  late final DaemonClient _daemon;
  late final bool _ownsDaemon;
  late final HostLinkStore _hostLinkStore;
  late final FirstRunStore _firstRunStore;
  late final NotificationPrefsStore _notificationPrefs;
  late final TransportPrefsStore _transportPrefs;
  InboxWatchService? _inboxWatch;
  bool _loading = true;
  String? _loadingHint;
  DaemonStatusResult? _status;
  String? _statusError;

  /// Hub-backed mail path verified (`list_threads`) — gates Home after configure.
  bool _mailReady = false;

  /// Set after a failed [getStatus] via local `health` ping (tray uses the same).
  bool _daemonReachable = false;

  int _lastConnectTick = 0;
  bool _pendingConnectHosts = false;
  bool _connecting = false;
  ConnectHostResult? _connectResult;
  String? _connectError;

  bool _firstRunReady = false;
  bool _hasLinkedHost = false;
  String? _openThreadId;
  bool _trackedHomeReady = false;

  bool get _forceOnboardingActive =>
      !_inWidgetTest && kDebugMode && _forceOnboardingFlag;

  bool _notificationsGateDone() {
    if (_firstRunStore.notificationsComplete) return true;
    // Grandfather users who finished ping before the notifications step shipped.
    if (_firstRunStore.pingComplete && !_forceOnboardingActive) return true;
    return false;
  }

  bool _needsOnboardingFlow() {
    final connectDone = _firstRunStore.connectComplete || _hasLinkedHost;
    if (!connectDone) return true;
    if (!_notificationsGateDone()) return true;
    if (_firstRunStore.connectComplete && !_firstRunStore.pingComplete) {
      return true;
    }
    return false;
  }

  OnboardingStep? _onboardingStartStep(bool configured) {
    if (_forceOnboardingActive && configured) return OnboardingStep.team;
    if (!configured) return null;
    if (!(_firstRunStore.connectComplete || _hasLinkedHost)) {
      return OnboardingStep.team;
    }
    if (!_notificationsGateDone()) return OnboardingStep.notifications;
    if (_firstRunStore.connectComplete && !_firstRunStore.pingComplete) {
      return OnboardingStep.ping;
    }
    return OnboardingStep.team;
  }

  @override
  void initState() {
    super.initState();
    _ownsDaemon = widget.daemon == null;
    _daemon = widget.daemon ?? DaemonClient();
    _hostLinkStore = widget.hostLinkStore ?? HostLinkStore();
    _notificationPrefs = NotificationPrefsStore();
    _transportPrefs = TransportPrefsStore(daemon: _daemon);
    // Widget tests that seed status skip the gate unless they inject a store.
    _firstRunStore =
        widget.firstRunStore ??
        (widget.seedStatus != null
            ? FirstRunStore.memory(
                connectComplete: true,
                pingComplete: true,
                notificationsComplete: true,
              )
            : FirstRunStore());
    _lastConnectTick = AppActions.connectHostsTick.value;
    AppActions.connectHostsTick.addListener(_onConnectHostsRequested);
    AppActions.openThreadRequest.addListener(_onOpenThreadRequested);
    // Memory / seeded stores: sync-ready so animated orb never blocks pumpAndSettle.
    _firstRunStore.loadMemorySync();
    if (_firstRunStore.connectComplete ||
        _firstRunStore.pingComplete ||
        widget.firstRunStore != null ||
        widget.seedStatus != null) {
      _firstRunReady = true;
    }
    _bootstrapFirstRun();
    if (_forceOnboardingActive &&
        widget.firstRunStore == null &&
        widget.seedStatus == null) {
      unawaited(_firstRunStore.resetForDebug());
    }
    AppActions.sessionReady.value = false;
    if (widget.seedStatus != null) {
      _status = widget.seedStatus;
      _mailReady = true;
      _loading = false;
      AppActions.sessionReady.value = true;
      _emitBootstrapPhase();
    } else {
      _emitBootstrapPhase();
      unawaited(_refreshStatus(bootstrap: true));
    }
  }

  void _emitBootstrapPhase() {
    widget.onBootstrapPhase?.call(
      !_loading,
      _loading ? (_loadingHint ?? 'Starting') : null,
    );
  }

  Future<void> _bootstrapFirstRun() async {
    await _firstRunStore.load();
    final links = await _hostLinkStore.load();
    if (!mounted) return;
    setState(() {
      _hasLinkedHost = links.values.any((r) => r.ok);
      _firstRunReady = true;
    });
  }

  Future<void> _refreshFirstRunGate() async {
    await _firstRunStore.load();
    final links = await _hostLinkStore.load();
    if (!mounted) return;
    setState(() {
      _hasLinkedHost = links.values.any((r) => r.ok);
    });
  }

  @override
  void dispose() {
    AppActions.connectHostsTick.removeListener(_onConnectHostsRequested);
    AppActions.openThreadRequest.removeListener(_onOpenThreadRequested);
    unawaited(_inboxWatch?.dispose());
    if (_ownsDaemon) {
      _daemon.dispose();
    }
    super.dispose();
  }

  void _onOpenThreadRequested() {
    final id = AppActions.openThreadRequest.value?.trim();
    if (id == null || id.isEmpty) return;
    AppActions.openThreadRequest.value = null;
    setState(() => _openThreadId = id);
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
      unawaited(() async {
        await windowManager.show();
        await windowManager.focus();
      }());
    }
  }

  void _ensureInboxWatch() {
    if (_inboxWatch != null) return;
    if (widget.seedStatus != null) return; // tests
    _inboxWatch = InboxWatchService(daemon: _daemon, prefs: _notificationPrefs);
    unawaited(_inboxWatch!.start());
  }

  Future<void> _verifyMailReady({required bool bootstrap}) async {
    if (bootstrap && widget.seedStatus == null && !_inWidgetTest) {
      final cache = ThreadListCacheStore();
      if (await cache.hasRecentSnapshot()) {
        return;
      }
    }

    final maxAttempts = bootstrap
        ? (widget.startupRetryAttempts + 1).clamp(1, 999)
        : 1;
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _daemon.listThreads();
        return;
      } catch (e) {
        lastError = e;
        final canRetry =
            bootstrap && attempt < maxAttempts - 1 && isLikelyStartingError(e);
        if (!canRetry) break;
        if (mounted) {
          setState(() {
            _loadingHint = 'Waiting for mail';
          });
          _emitBootstrapPhase();
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
      }
    }
    throw lastError ?? Exception('Mail not ready');
  }

  Future<void> _refreshStatus({bool bootstrap = false}) async {
    // Already on Home: keep last-known UI. Pane errors (Collab, Threads)
    // stay inline — don't eject to the courier splash.
    final keepLastKnown = _status?.configured == true && _mailReady;
    setState(() {
      if (!keepLastKnown) {
        _loading = true;
        _mailReady = false;
      }
      _statusError = null;
      _loadingHint = bootstrap ? 'Starting' : null;
    });
    if (!keepLastKnown) {
      AppActions.sessionReady.value = false;
    }
    _emitBootstrapPhase();

    Object? lastError;
    final maxAttempts = bootstrap
        ? (widget.startupRetryAttempts + 1).clamp(1, 999)
        : 1;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final status = await _daemon.getStatus();
        if (status.configured && !keepLastKnown) {
          await _verifyMailReady(bootstrap: bootstrap);
        }
        if (!mounted) return;
        setState(() {
          _status = status;
          _statusError = null;
          _mailReady = true;
          _daemonReachable = true;
          _loading = false;
          _loadingHint = null;
        });
        Analytics.syncIdentityFromStatus(status);
        AppActions.sessionReady.value = true;
        _emitBootstrapPhase();
        if (_pendingConnectHosts && status.configured) {
          _pendingConnectHosts = false;
          await _runConnectHosts();
        }
        return;
      } catch (e) {
        lastError = e;
        final canRetry =
            bootstrap && attempt < maxAttempts - 1 && isLikelyStartingError(e);
        if (!canRetry) break;
        if (mounted) {
          setState(() {
            _loadingHint =
                isLocalCourierTransportFailure(e.toString().toLowerCase())
                ? 'Waiting for Keychain'
                : 'Waiting for mail';
          });
          _emitBootstrapPhase();
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
      }
    }

    if (lastError == null) return;
    // Distinguish hung/slow hub-backed get_status from a dead daemon.
    // Tray "Daemon: up" uses pingHealth; do not call that "unreachable".
    final health = await _daemon.pingHealth();
    if (!mounted) return;
    // Keep last-known status; transport failure ≠ unconfigured.
    setState(() {
      _statusError = lastError.toString();
      _daemonReachable = health.connected;
      if (!keepLastKnown) {
        _mailReady = false;
      }
      _loading = false;
      _loadingHint = null;
    });
    if (!keepLastKnown) {
      AppActions.sessionReady.value = false;
    }
    _emitBootstrapPhase();
  }

  Future<void> _restartCourier() async {
    final restart = widget.onRestartCourier;
    if (restart == null) return;
    setState(() {
      _loading = true;
      _loadingHint = 'Restarting courier';
      _statusError = null;
      _mailReady = false;
    });
    AppActions.sessionReady.value = false;
    _emitBootstrapPhase();
    final err = await restart();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _statusError = err;
        _daemonReachable = false;
        _mailReady = false;
        _loading = false;
        _loadingHint = null;
      });
      AppActions.sessionReady.value = false;
      _emitBootstrapPhase();
      return;
    }
    await _refreshStatus(bootstrap: true);
  }

  void _onOnboarded(DaemonStatusResult status) {
    Analytics.syncIdentityFromStatus(status);
    setState(() {
      _status = status;
      _statusError = null;
    });
    if (_pendingConnectHosts) {
      _pendingConnectHosts = false;
      _runConnectHosts();
    }
  }

  void _onSignedOut(DaemonStatusResult status) {
    Analytics.track(AnalyticsEvent.signOut);
    Analytics.reset();
    setState(() {
      _status = status;
      _statusError = null;
      _pendingConnectHosts = false;
      _connectResult = null;
      _connectError = null;
    });
  }

  void _onConnectHostsRequested() {
    final tick = AppActions.connectHostsTick.value;
    if (tick == _lastConnectTick) return;
    _lastConnectTick = tick;

    if (_status?.configured == true) {
      if (!_connecting) {
        _runConnectHosts();
      }
      return;
    }

    // Not on Home yet — queue until configured; window show is tray-side.
    _pendingConnectHosts = true;
    if (mounted && !_loading && _statusError == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Join an org first, then Connect AI hosts will run.'),
        ),
      );
    }
  }

  Future<void> _runConnectHosts() async {
    setState(() {
      _connecting = true;
      _connectResult = null;
      _connectError = null;
    });
    try {
      final result = await _daemon.connectHost('all');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectResult = result;
        _connectError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectResult = null;
        _connectError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MutandeOrb.standard(semanticLabel: 'Loading…'),
              if (_loadingHint != null) ...[
                const SizedBox(height: 20),
                Text(
                  _loadingHint!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF78716C),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Bootstrap/session gate failure — block Home until mail path is ready.
    if (_statusError != null && !_mailReady) {
      return DaemonErrorScreen(
        error: _statusError!,
        endpoint: _daemon.httpBaseUrl,
        daemonReachable: _daemonReachable,
        onRetry: _refreshStatus,
        onRestartCourier: widget.onRestartCourier != null
            ? _restartCourier
            : null,
      );
    }

    // Had status before; daemon blipped — keep showing last-known route,
    // but surface a banner when we know about the error.
    final status = _status;
    final configured = status?.configured ?? false;

    if (!_firstRunReady) {
      return const Scaffold(
        body: Center(child: MutandeOrb.standard(semanticLabel: 'Loading…')),
      );
    }

    if (!configured || _needsOnboardingFlow()) {
      return OnboardingFlowScreen(
        config: widget.config,
        daemon: _daemon,
        firstRunStore: _firstRunStore,
        hostLinkStore: _hostLinkStore,
        initialStatus: status,
        forceDebug: _forceOnboardingActive,
        initialStep: _onboardingStartStep(configured),
        onComplete: (updated, threadId) {
          _onOnboarded(updated);
          if (threadId != null) {
            setState(() => _openThreadId = threadId);
          }
          _refreshFirstRunGate();
        },
      );
    }

    _ensureInboxWatch();
    if (!_trackedHomeReady) {
      _trackedHomeReady = true;
      Analytics.track(AnalyticsEvent.homeReady);
    }
    return HomeScreen(
      config: widget.config,
      daemon: _daemon,
      status: _status!,
      statusError: _statusError,
      onRetryStatus: _refreshStatus,
      connecting: _connecting,
      connectResult: _connectResult,
      connectError: _connectError,
      onConnectHosts: _runConnectHosts,
      onSignedOut: _onSignedOut,
      hostLinkStore: _hostLinkStore,
      notificationPrefs: _notificationPrefs,
      transportPrefs: _transportPrefs,
      initialThreadId: _openThreadId,
      appVersion: widget.appVersion,
      onRestartCourier: widget.onRestartCourier,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.config,
    required this.daemon,
    required this.status,
    this.statusError,
    this.onRetryStatus,
    required this.connecting,
    this.connectResult,
    this.connectError,
    required this.onConnectHosts,
    this.onSignedOut,
    this.hostLinkStore,
    this.notificationPrefs,
    this.transportPrefs,
    this.initialThreadId,
    this.appVersion = AppConfig.appVersion,
    this.onRestartCourier,
  });

  final AppConfig config;
  final DaemonClient daemon;
  final DaemonStatusResult status;
  final String? statusError;
  final VoidCallback? onRetryStatus;
  final bool connecting;
  final ConnectHostResult? connectResult;
  final String? connectError;
  final VoidCallback onConnectHosts;
  final ValueChanged<DaemonStatusResult>? onSignedOut;
  final HostLinkStore? hostLinkStore;
  final NotificationPrefsStore? notificationPrefs;
  final TransportPrefsStore? transportPrefs;
  final String? initialThreadId;
  final String appVersion;
  final Future<String?> Function()? onRestartCourier;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = false;
  DaemonHealthResult? _health;
  int _tab = 0; // 0 threads · 1 collab · 2 network
  VoidCallback? _reloadThreads;
  VoidCallback? _reloadCollab;
  VoidCallback? _reloadAgents;
  VoidCallback? _reloadContacts;
  String? _composeRecipient;
  String? _openThreadId;
  String? _openCollabId;
  int _networkSegment = 0;
  int _networkReset = 0;
  late final DaemonEventClient _inboxEvents;

  bool _searchOpen = false;
  final List<String> _recentQueries = [];

  void _registerThreadsReload(VoidCallback? reload) {
    _reloadThreads = reload;
  }

  void _registerCollabReload(VoidCallback? reload) {
    _reloadCollab = reload;
  }

  void _registerAgentsReload(VoidCallback? reload) {
    _reloadAgents = reload;
  }

  void _registerContactsReload(VoidCallback? reload) {
    _reloadContacts = reload;
  }

  @override
  void initState() {
    super.initState();
    _openThreadId = widget.initialThreadId;
    _inboxEvents = DaemonEventClient(
      httpBaseUrl: widget.daemon.httpBaseUrl,
      httpTokenPath: widget.daemon.httpTokenPath,
    );
    _inboxEvents.start();
    _checkDaemon();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialThreadId?.trim();
    final prev = oldWidget.initialThreadId?.trim();
    if (next != null && next.isNotEmpty && next != prev) {
      setState(() {
        _openThreadId = next;
        _tab = 0;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_inboxEvents.dispose());
    super.dispose();
  }

  void _rememberQuery(String q) {
    _recentQueries.remove(q);
    _recentQueries.insert(0, q);
    if (_recentQueries.length > 8) {
      _recentQueries.removeRange(8, _recentQueries.length);
    }
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    _searchOpen = true;
    try {
      final hit = await showSearchDialog(
        context: context,
        daemon: widget.daemon,
        myHandle: widget.status.handle,
        recentQueries: List.unmodifiable(_recentQueries),
        onRememberQuery: _rememberQuery,
      );
      if (!mounted || hit == null) return;
      setState(() {
        switch (hit.kind) {
          case SearchHitKind.thread:
            _tab = 0;
            _openThreadId = hit.id;
          case SearchHitKind.collab:
            _tab = 1;
            _openCollabId = hit.id;
          case SearchHitKind.contact:
            _tab = 2;
            _networkSegment = 0;
            _networkReset++;
        }
      });
    } finally {
      _searchOpen = false;
    }
  }

  bool get _editableFocused {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
        ctx.findAncestorWidgetOfExactType<TextField>() != null ||
        ctx.findAncestorWidgetOfExactType<MacosTextField>() != null;
  }

  KeyEventResult _onHomeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_searchOpen) return KeyEventResult.ignored;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (meta &&
        (event.logicalKey == LogicalKeyboardKey.keyF ||
            event.logicalKey == LogicalKeyboardKey.keyK)) {
      unawaited(_openSearch());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash && !_editableFocused) {
      unawaited(_openSearch());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _checkDaemon() async {
    setState(() => _checking = true);
    final result = await widget.daemon.pingHealth();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _health = result;
    });
  }

  Future<void> _openSettings({SettingsOpenTarget? openTo}) async {
    await showMacosSheet<void>(
      context: context,
      barrierDismissible: true,
      builder: (sheetContext) {
        return MacosSheet(
          child: SizedBox(
            width: 720,
            height: 720,
            child: SettingsScreen(
              daemon: widget.daemon,
              checking: _checking,
              connecting: widget.connecting,
              health: _health,
              connectError: widget.connectError,
              onCheckDaemon: _checkDaemon,
              handle: widget.status.handle,
              appVersion: widget.appVersion,
              onRestartCourier: widget.onRestartCourier,
              hostLinkStore: widget.hostLinkStore,
              notificationPrefs: widget.notificationPrefs,
              transportPrefs: widget.transportPrefs,
              openTo: openTo,
              onOpenThreads: () {
                Navigator.of(sheetContext).pop();
                _selectTab(0);
              },
              onOpenAgents: () {
                Navigator.of(sheetContext).pop();
                _selectTab(2);
              },
              onSignedOut: widget.onSignedOut == null
                  ? null
                  : (status) {
                      Navigator.of(sheetContext).pop();
                      widget.onSignedOut!(status);
                    },
            ),
          ),
        );
      },
    );
  }

  void _selectTab(int i) {
    const tabs = ['threads', 'collab', 'network'];
    Analytics.track(AnalyticsEvent.tabSelect, {'tab': tabs[i]});
    setState(() => _tab = i);
    if (i == 0) _reloadThreads?.call();
    if (i == 1) _reloadCollab?.call();
    if (i == 2) {
      _reloadContacts?.call();
      _reloadAgents?.call();
    }
  }

  Widget _tabBody() {
    if (_tab == 0) {
      return ThreadsPanel(
        daemon: widget.daemon,
        inboxEvents: _inboxEvents,
        myHandle: widget.status.handle,
        onReloadReady: _registerThreadsReload,
        composeRecipient: _composeRecipient,
        notificationPrefs: widget.notificationPrefs,
        onComposeRecipientHandled: () {
          if (_composeRecipient != null) {
            setState(() => _composeRecipient = null);
          }
        },
        initialThreadId: _openThreadId,
        onInitialThreadHandled: () {
          if (_openThreadId != null) {
            setState(() => _openThreadId = null);
          }
        },
      );
    }
    if (_tab == 1) {
      return CollabPanel(
        daemon: widget.daemon,
        handle: widget.status.handle,
        onReloadReady: _registerCollabReload,
        initialCollabId: _openCollabId,
        onInitialCollabHandled: () {
          if (_openCollabId != null) {
            setState(() => _openCollabId = null);
          }
        },
      );
    }
    return NetworkPanel(
      key: ValueKey(_networkReset),
      daemon: widget.daemon,
      handle: widget.status.handle,
      inviteWebUrl: widget.config.webAppUrl,
      appVersion: widget.appVersion,
      hostLinkStore: widget.hostLinkStore,
      initialSegment: _networkSegment,
      onReloadPeople: _registerContactsReload,
      onReloadAgents: _registerAgentsReload,
      onViewThreads: () => _selectTab(0),
      onStartThread: (handle) {
        setState(() {
          _tab = 0;
          _composeRecipient = handle;
        });
      },
    );
  }

  Widget _tabStrip({bool showGlyph = false}) {
    return HomeChromeStrip(tab: _tab, onTab: _selectTab, showGlyph: showGlyph);
  }

  Widget _titlebarActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeChromeIconButton(
          key: const Key('home-search'),
          icon: CupertinoIcons.search,
          tooltip: 'Search',
          onPressed: () => unawaited(_openSearch()),
        ),
        const SizedBox(width: HomeChrome.pillGap),
        HomeChromeIconButton(
          icon: CupertinoIcons.bell,
          tooltip: 'Notifications',
          onPressed: () =>
              _openSettings(openTo: SettingsOpenTarget.notifications),
        ),
        const SizedBox(width: HomeChrome.pillGap),
        HomeChromeIconCluster(
          actions: [
            HomeChromeIconAction(
              icon: CupertinoIcons.question_circle,
              tooltip: 'Support',
              onPressed: () =>
                  _openSettings(openTo: SettingsOpenTarget.feedback),
            ),
            HomeChromeIconAction(
              icon: CupertinoIcons.settings,
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
          ],
        ),
      ],
    );
  }

  Widget? _statusBanner() {
    if (widget.statusError == null) return null;
    return Material(
      color: const Color(0xFFFEF3C7),
      child: InkWell(
        onTap: widget.onRetryStatus,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Daemon blip — tap to retry status',
            style: TextStyle(
              color: MutandeColors.bronze,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// True only under `flutter test` (TestWidgetsFlutterBinding), not debug runs.
  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Material chrome for Windows (+ widget tests); macos_ui on macOS.
  bool get _useMaterialShell =>
      _inWidgetTest || (!kIsWeb && Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    final handle = widget.status.handle ?? 'mutande';
    final initial = handle.isNotEmpty ? handle[0].toUpperCase() : 'M';
    final banner = _statusBanner();

    final shell = _useMaterialShell
        ? Scaffold(
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: MutandeColors.stone100,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              left: HomeChrome.glyphLeading,
                              right: 12,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.asset(
                                'assets/tray_icon.png',
                                width: 28,
                                height: 28,
                                semanticLabel: 'mutande',
                              ),
                            ),
                          ),
                          _tabStrip(),
                          const Spacer(),
                          _titlebarActions(),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: handle,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: MutandeColors.stone200,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: MutandeColors.stone600,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (banner != null) banner,
                  Expanded(
                    child: Padding(
                      padding: _tab == 0 || _tab == 1
                          ? const EdgeInsets.fromLTRB(0, 10, 0, 0)
                          : const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _tabBody(),
                    ),
                  ),
                ],
              ),
            ),
          )
        : MacosWindow(
            backgroundColor: MutandeColors.stone100,
            disableWallpaperTinting: true,
            child: MacosScaffold(
              backgroundColor: MutandeColors.stone100,
              toolBar: ToolBar(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
                automaticallyImplyLeading: false,
                dividerColor: MacosColors.transparent,
                title: _tabStrip(showGlyph: true),
                titleWidth: 440,
                actions: [
                  CustomToolbarItem(
                    inToolbarBuilder: (context) => _titlebarActions(),
                    inOverflowedBuilder: (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ToolbarOverflowMenuItem(
                          label: 'Search',
                          onPressed: () => unawaited(_openSearch()),
                        ),
                        ToolbarOverflowMenuItem(
                          label: 'Notifications',
                          onPressed: () => _openSettings(
                            openTo: SettingsOpenTarget.notifications,
                          ),
                        ),
                        ToolbarOverflowMenuItem(
                          label: 'Support',
                          onPressed: () => _openSettings(
                            openTo: SettingsOpenTarget.feedback,
                          ),
                        ),
                        ToolbarOverflowMenuItem(
                          label: 'Settings',
                          onPressed: _openSettings,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              children: [
                ContentArea(
                  builder: (context, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (banner != null) banner,
                        Expanded(
                          child: Padding(
                            padding: (_tab == 0 || _tab == 1)
                                ? const EdgeInsets.fromLTRB(0, 10, 0, 0)
                                : const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: _tabBody(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );

    return Focus(autofocus: true, onKeyEvent: _onHomeKey, child: shell);
  }
}
