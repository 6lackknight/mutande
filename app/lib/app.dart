import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/agents_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/join_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/threads_screen.dart';
import 'services/app_actions.dart';
import 'services/daemon_client.dart';
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
    this.welcomeDuration = const Duration(seconds: 3),
  });

  final AppConfig config;

  /// Injectable for tests; defaults to a live HTTP daemon client.
  final DaemonClient? daemon;

  /// When set, skips the initial `get_status` RPC (widget tests).
  final DaemonStatusResult? seedStatus;

  /// Dark orb welcome hold. Pass [Duration.zero] to skip (tests).
  final Duration welcomeDuration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mutande',
      theme: mutandeTheme(),
      debugShowCheckedModeBanner: false,
      home: WelcomeSplash(
        duration: welcomeDuration,
        child: RootScreen(
          config: config,
          daemon: daemon,
          seedStatus: seedStatus,
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
  });

  final AppConfig config;
  final DaemonClient? daemon;
  final DaemonStatusResult? seedStatus;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final DaemonClient _daemon;
  late final bool _ownsDaemon;
  bool _loading = true;
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
      _refreshStatus();
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

  Future<void> _refreshStatus() async {
    setState(() {
      _loading = true;
      _statusError = null;
    });
    try {
      final status = await _daemon.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusError = null;
        _daemonReachable = true;
        _loading = false;
      });
      if (_pendingConnectHosts && status.configured) {
        _pendingConnectHosts = false;
        await _runConnectHosts();
      }
    } catch (e) {
      if (!mounted) return;
      // Distinguish hung/slow hub-backed get_status from a dead daemon.
      // Tray "Daemon: up" uses pingHealth; do not call that "unreachable".
      final health = await _daemon.pingHealth();
      if (!mounted) return;
      // Keep last-known status; transport failure ≠ unconfigured.
      setState(() {
        _statusError = e.toString();
        _daemonReachable = health.connected;
        _loading = false;
      });
    }
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
      return const Scaffold(
        body: Center(child: MutandeOrb.standard()),
      );
    }

    // Transport/RPC failure with no prior status → error UI, not Join.
    if (_statusError != null && _status == null) {
      return DaemonErrorScreen(
        error: _statusError!,
        endpoint: _daemon.httpBaseUrl,
        daemonReachable: _daemonReachable,
        onRetry: _refreshStatus,
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
    );
  }
}

/// Shown when get_status/transport fails and we have no last-known status.
class DaemonErrorScreen extends StatelessWidget {
  const DaemonErrorScreen({
    super.key,
    required this.error,
    required this.endpoint,
    this.daemonReachable = false,
    required this.onRetry,
  });

  final String error;
  final String endpoint;
  final bool daemonReachable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title =
        daemonReachable ? "Couldn't load session" : 'Daemon unreachable';
    final detail = daemonReachable
        ? 'mutande-core is up, but session status timed out or failed '
            '(usually a slow hub). Retry in a moment.\n'
            'HTTP: $endpoint'
        : 'The app starts mutande-core automatically; if this persists, '
            'set MUTANDE_CORE_PATH or build core/target/release/mutande-core.\n'
            'HTTP: $endpoint';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'mutande',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF78716C),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA8A29E),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = false;
  DaemonHealthResult? _health;
  int _tab = 0; // 0 threads · 1 agents · 2 contacts
  VoidCallback? _reloadThreads;

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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsScreen(
          daemon: widget.daemon,
          checking: _checking,
          connecting: widget.connecting,
          health: _health,
          connectResult: widget.connectResult,
          connectError: widget.connectError,
          onCheckDaemon: _checkDaemon,
          onConnectHosts: widget.onConnectHosts,
          handle: widget.status.handle,
        ),
      ),
    );
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
                if (i == 0) _reloadThreads?.call();
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
                        onReloadReady: (reload) => _reloadThreads = reload,
                      )
                    : _tab == 1
                        ? AgentsPanel(
                            daemon: widget.daemon,
                            handle: widget.status.handle,
                            onViewThreads: () => setState(() => _tab = 0),
                          )
                        : SingleChildScrollView(
                            child: ContactsPanel(
                              handle: widget.status.handle,
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              'mutande',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _NavTab(
                  label: 'Threads',
                  selected: tab == 0,
                  onTap: () => onTab(0),
                ),
                _NavTab(
                  label: 'Agents',
                  selected: tab == 1,
                  onTap: () => onTab(1),
                ),
                _NavTab(
                  label: 'Contacts',
                  selected: tab == 2,
                  onTap: () => onTab(2),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, size: 20),
            color: const Color(0xFF57534E),
          ),
          Tooltip(
            message: handle,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFE7E5E4),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF57534E),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? const Color(0xFF92400E)
                        : const Color(0xFF78716C),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 2,
              width: selected ? 22 : 0,
              decoration: BoxDecoration(
                color: const Color(0xFF92400E),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
