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
import 'screens/search_screen.dart';
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
import 'widgets/home_chrome_strip.dart';
import 'widgets/home_search_field.dart';
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
    setState(() {
      _loading = true;
      _statusError = null;
      _mailReady = false;
      _loadingHint = bootstrap ? 'Starting' : null;
    });
    AppActions.sessionReady.value = false;
    _emitBootstrapPhase();

    Object? lastError;
    final maxAttempts = bootstrap
        ? (widget.startupRetryAttempts + 1).clamp(1, 999)
        : 1;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final status = await _daemon.getStatus();
        if (status.configured) {
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
      _mailReady = false;
      _loading = false;
      _loadingHint = null;
    });
    AppActions.sessionReady.value = false;
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
  late final DaemonEventClient _inboxEvents;

  bool _searchMode = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
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
    _searchFocus.addListener(_onSearchFocusChanged);
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
        if (_searchMode) _searchMode = false;
      });
    }
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    unawaited(_inboxEvents.dispose());
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus &&
        _searchController.text.trim().isNotEmpty &&
        !_searchMode) {
      setState(() => _searchMode = true);
    }
  }

  void _onSearchQueryChanged(String value) {
    final active = value.trim().isNotEmpty;
    setState(() {
      _searchMode = active;
    });
    // Threads list search unmounts when SearchScreen opens — keep focus on the
    // shared FocusNode after chrome/search surface remounts the field.
    if (active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_searchFocus.hasFocus) _searchFocus.requestFocus();
      });
    }
  }

  void _onSearchSubmit() {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searchMode = true;
      _rememberQuery(q);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchMode = false);
  }

  void _exitSearch() {
    if (!_searchMode) return;
    _searchFocus.unfocus();
    setState(() => _searchMode = false);
  }

  void _rememberQuery(String q) {
    _recentQueries.remove(q);
    _recentQueries.insert(0, q);
    if (_recentQueries.length > 8) {
      _recentQueries.removeRange(8, _recentQueries.length);
    }
  }

  void _pickRecent(String q) {
    _searchController.text = q;
    _searchController.selection = TextSelection.collapsed(offset: q.length);
    setState(() {
      _searchMode = true;
      _rememberQuery(q);
    });
  }

  void _openThreadFromSearch(String id) {
    final q = _searchController.text.trim();
    if (q.isNotEmpty) _rememberQuery(q);
    setState(() {
      _searchMode = false;
      _tab = 0;
      _openThreadId = id;
    });
    _searchFocus.unfocus();
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
    if (event.logicalKey == LogicalKeyboardKey.escape && _searchMode) {
      _exitSearch();
      return KeyEventResult.handled;
    }
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (meta && event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash && !_editableFocused) {
      _searchFocus.requestFocus();
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

  Future<void> _openSettings() async {
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
    setState(() {
      _tab = i;
      if (_searchMode) _searchMode = false;
    });
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
        searchController: _searchController,
        searchFocus: _searchFocus,
        onSearchQueryChanged: _onSearchQueryChanged,
        onSearchSubmit: _onSearchSubmit,
        onClearSearch: _clearSearch,
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
      );
    }
    return NetworkPanel(
      daemon: widget.daemon,
      handle: widget.status.handle,
      inviteWebUrl: widget.config.webAppUrl,
      appVersion: widget.appVersion,
      hostLinkStore: widget.hostLinkStore,
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

  Widget _contentBody() {
    if (_searchMode) {
      return SearchScreen(
        daemon: widget.daemon,
        query: _searchController.text,
        recentQueries: List.unmodifiable(_recentQueries),
        onPickRecent: _pickRecent,
        onOpenThread: _openThreadFromSearch,
        myHandle: widget.status.handle,
      );
    }
    return _tabBody();
  }

  /// On Threads, search sits beside Compose. Elsewhere / in search mode, it
  /// stays on the titlebar row so the field remains mounted.
  bool get _searchInChrome => _searchMode || _tab != 0;

  Widget _tabStrip({bool showGlyph = false}) {
    return HomeChromeStrip(tab: _tab, onTab: _selectTab, showGlyph: showGlyph);
  }

  Widget _titlebarSearch() {
    return SizedBox(
      width: 220,
      height: 32,
      child: HomeSearchField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: _onSearchQueryChanged,
        onSubmit: _onSearchSubmit,
        onClear: _clearSearch,
      ),
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
                            padding: const EdgeInsets.only(right: 8),
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
                          if (_searchInChrome)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _titlebarSearch(),
                            ),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                          ),
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
                      padding: _searchMode
                          ? EdgeInsets.zero
                          : (_tab == 0 || _tab == 1
                                ? const EdgeInsets.fromLTRB(0, 4, 0, 0)
                                : const EdgeInsets.fromLTRB(16, 8, 16, 12)),
                      child: _contentBody(),
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
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                automaticallyImplyLeading: false,
                dividerColor: MacosColors.transparent,
                title: _tabStrip(showGlyph: true),
                titleWidth: 380,
                actions: [
                  if (_searchInChrome)
                    CustomToolbarItem(
                      inToolbarBuilder: (context) => _titlebarSearch(),
                    ),
                  ToolBarIconButton(
                    label: 'Settings',
                    icon: const MacosIcon(CupertinoIcons.settings),
                    onPressed: _openSettings,
                    showLabel: false,
                    tooltipMessage: 'Settings',
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
                            padding: (!_searchMode && (_tab == 0 || _tab == 1))
                                ? const EdgeInsets.fromLTRB(0, 4, 0, 0)
                                : (!_searchMode
                                      ? const EdgeInsets.fromLTRB(16, 8, 16, 12)
                                      : EdgeInsets.zero),
                            child: _contentBody(),
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
