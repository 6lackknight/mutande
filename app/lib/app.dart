import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/agents_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/join_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/threads_screen.dart';
import 'services/app_actions.dart';
import 'services/daemon_client.dart';
import 'services/daemon_errors.dart';
import 'services/host_link_store.dart';
import 'widgets/daemon_error_screen.dart';
import 'widgets/thinking_orb.dart';
import 'widgets/welcome_splash.dart';

/// Stone/slate neutrals with a muted bronze accent — mythic, not flashy.
ThemeData mutandeTheme() {
  const stoneSurface = Color(0xFFFAFAF9);
  const stoneBackground = Color(0xFFF5F5F4);
  const bronzeAccent = Color(0xFF92400E);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: bronzeAccent,
      brightness: Brightness.light,
      surface: stoneSurface,
    ),
    scaffoldBackgroundColor: stoneBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: stoneSurface,
      foregroundColor: Color(0xFF44403C),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: stoneSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE7E5E4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF57534E),
        foregroundColor: stoneSurface,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: stoneSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFFA8A29E)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF92400E), width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
      ),
    ),
  );
}

class MutandeApp extends StatelessWidget {
  const MutandeApp({
    super.key,
    required this.config,
    this.daemon,
    this.seedStatus,
    this.hostLinkStore,
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

  /// Dark orb welcome hold. Pass [Duration.zero] to skip (tests).
  final Duration welcomeDuration;

  /// pubspec version (before `+`), overridable via `--dart-define=APP_VERSION=`.
  final String appVersion;

  /// Retries while mutande-core / Keychain may still be starting (× 2s apart).
  final int startupRetryAttempts;

  /// When set (macOS shell), error screen can restart the bundled sidecar.
  final Future<String?> Function()? onRestartCourier;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mutande',
      theme: mutandeTheme(),
      debugShowCheckedModeBanner: false,
      home: WelcomeSplash(
        duration: welcomeDuration,
        appVersion: appVersion,
        child: RootScreen(
          config: config,
          daemon: daemon,
          seedStatus: seedStatus,
          hostLinkStore: hostLinkStore,
          startupRetryAttempts: startupRetryAttempts,
          onRestartCourier: onRestartCourier,
        ),
      ),
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
    this.startupRetryAttempts = 15,
    this.onRestartCourier,
  });

  final AppConfig config;
  final DaemonClient? daemon;
  final DaemonStatusResult? seedStatus;
  final HostLinkStore? hostLinkStore;
  final int startupRetryAttempts;
  final Future<String?> Function()? onRestartCourier;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final DaemonClient _daemon;
  late final bool _ownsDaemon;
  bool _loading = true;
  String? _loadingHint;
  DaemonStatusResult? _status;
  String? _statusError;
  /// Set after a failed [getStatus] via local `health` ping (tray uses the same).
  bool _daemonReachable = false;

  int _lastConnectTick = 0;
  bool _pendingConnectHosts = false;
  bool _connecting = false;
  ConnectHostResult? _connectResult;
  String? _connectError;

  @override
  void initState() {
    super.initState();
    _ownsDaemon = widget.daemon == null;
    _daemon = widget.daemon ?? DaemonClient();
    _lastConnectTick = AppActions.connectHostsTick.value;
    AppActions.connectHostsTick.addListener(_onConnectHostsRequested);
    if (widget.seedStatus != null) {
      _status = widget.seedStatus;
      _loading = false;
    } else {
      _refreshStatus(bootstrap: true);
    }
  }

  @override
  void dispose() {
    AppActions.connectHostsTick.removeListener(_onConnectHostsRequested);
    if (_ownsDaemon) {
      _daemon.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshStatus({bool bootstrap = false}) async {
    setState(() {
      _loading = true;
      _statusError = null;
      _loadingHint = null;
    });

    Object? lastError;
    final maxAttempts =
        bootstrap ? (widget.startupRetryAttempts + 1).clamp(1, 999) : 1;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final status = await _daemon.getStatus();
        if (!mounted) return;
        setState(() {
          _status = status;
          _statusError = null;
          _daemonReachable = true;
          _loading = false;
          _loadingHint = null;
        });
        if (_pendingConnectHosts && status.configured) {
          _pendingConnectHosts = false;
          await _runConnectHosts();
        }
        return;
      } catch (e) {
        lastError = e;
        final canRetry = bootstrap &&
            attempt < maxAttempts - 1 &&
            isLikelyStartingError(e);
        if (!canRetry) break;
        if (mounted) {
          setState(() {
            _loadingHint = 'Waiting for Keychain…';
          });
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
      _loading = false;
      _loadingHint = null;
    });
  }

  Future<void> _restartCourier() async {
    final restart = widget.onRestartCourier;
    if (restart == null) return;
    setState(() {
      _loading = true;
      _loadingHint = 'Restarting courier…';
      _statusError = null;
    });
    final err = await restart();
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _statusError = err;
        _daemonReachable = false;
        _loading = false;
        _loadingHint = null;
      });
      return;
    }
    await _refreshStatus(bootstrap: true);
  }

  void _onOnboarded(DaemonStatusResult status) {
    setState(() {
      _status = status;
      _statusError = null;
    });
    if (_pendingConnectHosts) {
      _pendingConnectHosts = false;
      _runConnectHosts();
    }
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

    // Transport/RPC failure with no prior status → error UI, not Join.
    if (_statusError != null && _status == null) {
      return DaemonErrorScreen(
        error: _statusError!,
        endpoint: _daemon.httpBaseUrl,
        daemonReachable: _daemonReachable,
        onRetry: _refreshStatus,
        onRestartCourier:
            widget.onRestartCourier != null ? _restartCourier : null,
      );
    }

    // Had status before; daemon blipped — keep showing last-known route,
    // but surface a banner when we know about the error.
    final status = _status;
    final configured = status?.configured ?? false;
    if (!configured) {
      return OnboardingScreen(
        config: widget.config,
        daemon: _daemon,
        status: status,
        onOnboarded: _onOnboarded,
      );
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
      hostLinkStore: widget.hostLinkStore,
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
    this.hostLinkStore,
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
  final HostLinkStore? hostLinkStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = false;
  DaemonHealthResult? _health;
  int _tab = 0; // 0 threads · 1 agents · 2 contacts
  VoidCallback? _reloadThreads;
  VoidCallback? _reloadAgents;
  VoidCallback? _reloadContacts;
  String? _composeRecipient;

  void _registerAgentsReload(VoidCallback? reload) {
    _reloadAgents = reload;
  }

  void _registerThreadsReload(VoidCallback? reload) {
    _reloadThreads = reload;
  }

  void _registerContactsReload(VoidCallback? reload) {
    _reloadContacts = reload;
  }

  @override
  void initState() {
    super.initState();
    _checkDaemon();
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
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => SettingsScreen(
          daemon: widget.daemon,
          checking: _checking,
          connecting: widget.connecting,
          health: _health,
          connectError: widget.connectError,
          onCheckDaemon: _checkDaemon,
          onConnectHosts: widget.onConnectHosts,
          handle: widget.status.handle,
          hostLinkStore: widget.hostLinkStore,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            )),
            child: child,
          );
        },
      ),
    );
    if (_tab == 1) _reloadAgents?.call();
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.status.handle ?? 'Agent-to-agent mail';

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeHeader(
              handle: handle,
              tab: _tab,
              onTab: (i) {
                setState(() => _tab = i);
                if (i == 2) _reloadContacts?.call();
              },
              onSettings: _openSettings,
            ),
            if (widget.statusError != null)
              Material(
                color: const Color(0xFFFEF3C7),
                child: InkWell(
                  onTap: widget.onRetryStatus,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Daemon blip — tap to retry status',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _tab == 0
                    ? ThreadsPanel(
                        daemon: widget.daemon,
                        myHandle: widget.status.handle,
                        onReloadReady: _registerThreadsReload,
                        composeRecipient: _composeRecipient,
                        onComposeRecipientHandled: () {
                          if (_composeRecipient != null) {
                            setState(() => _composeRecipient = null);
                          }
                        },
                      )
                    : _tab == 1
                        ? AgentsPanel(
                            daemon: widget.daemon,
                            handle: widget.status.handle,
                            onViewThreads: () => setState(() => _tab = 0),
                            hostLinkStore: widget.hostLinkStore,
                            onReloadReady: _registerAgentsReload,
                          )
                            : ContactsPanel(
                                daemon: widget.daemon,
                                handle: widget.status.handle,
                                inviteWebUrl: widget.config.webAppUrl,
                                onReloadReady: _registerContactsReload,
                                onStartThread: (handle) {
                                  setState(() {
                                    _tab = 0;
                                    _composeRecipient = handle;
                                  });
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented primary nav — quiet brand whisper, capsule tabs, utilities right.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.handle,
    required this.tab,
    required this.onTab,
    required this.onSettings,
  });

  final String handle;
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final initial = handle.isNotEmpty && handle != 'Agent-to-agent mail'
        ? handle[0].toUpperCase()
        : 'M';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Tooltip(
            message: 'mutande',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/tray_icon.png',
                width: 32,
                height: 32,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'mutande',
              ),
            ),
          ),
          const SizedBox(width: 12),
          _SegmentedTabs(tab: tab, onTab: onTab),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.settings_outlined, size: 18),
            color: const Color(0xFF78716C),
          ),
          Tooltip(
            message: handle,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFFE7E5E4),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF57534E),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, int i) {
      final selected = tab == i;
      return InkWell(
        onTap: () => onTab(i),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFAFAF9) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? const Color(0xFF292524)
                      : const Color(0xFF78716C),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7E5E4),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Threads', 0),
          seg('Agents', 1),
          seg('Contacts', 2),
        ],
      ),
    );
  }
}
