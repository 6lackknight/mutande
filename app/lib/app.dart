import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'services/app_actions.dart';
import 'services/daemon_client.dart';

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
        borderSide: const BorderSide(color: Color(0xFF92400E)),
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
  });

  final AppConfig config;

  /// Injectable for tests; defaults to a live HTTP daemon client.
  final DaemonClient? daemon;

  /// When set, skips the initial `get_status` RPC (widget tests).
  final DaemonStatusResult? seedStatus;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mutande',
      theme: mutandeTheme(),
      home: RootScreen(
        config: config,
        daemon: daemon,
        seedStatus: seedStatus,
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

  int _lastConnectTick = 0;
  bool _pendingConnectHosts = false;
  bool _connecting = false;
  String? _connectMessage;
  bool _connectIsWarning = false;

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
        _loading = false;
      });
      if (_pendingConnectHosts && status.configured) {
        _pendingConnectHosts = false;
        await _runConnectHosts();
      }
    } catch (e) {
      if (!mounted) return;
      // Keep last-known status; transport failure ≠ unconfigured.
      setState(() {
        _statusError = e.toString();
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
      _connectMessage = null;
      _connectIsWarning = false;
    });
    try {
      final result = await _daemon.connectHost('all');
      if (!mounted) return;
      final okHosts = result.hosts.where((h) => h.ok).toList();
      final badHosts = result.hosts.where((h) => !h.ok).toList();
      final lines = <String>[
        'Wrote ${okHosts.length}/${result.hosts.length} configs',
        'command: ${result.command} mcp',
      ];
      for (final h in result.hosts) {
        final status = h.ok ? 'ok' : 'failed';
        final note = (h.note != null && h.note!.isNotEmpty) ? ' — ${h.note}' : '';
        lines.add('${h.host}: ${h.path} ($status)$note');
      }
      setState(() {
        _connecting = false;
        _connectMessage = lines.join('\n');
        _connectIsWarning = badHosts.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectMessage = e.toString();
        _connectIsWarning = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Transport/RPC failure with no prior status → error UI, not Join.
    if (_statusError != null && _status == null) {
      return DaemonErrorScreen(
        error: _statusError!,
        endpoint: _daemon.httpBaseUrl,
        onRetry: _refreshStatus,
      );
    }

    // Had status before; daemon blipped — keep showing last-known route,
    // but surface a banner when we know about the error.
    final configured = _status?.configured ?? false;
    if (!configured) {
      return OnboardingScreen(
        config: widget.config,
        daemon: _daemon,
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
      connectMessage: _connectMessage,
      connectIsWarning: _connectIsWarning,
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
    required this.onRetry,
  });

  final String error;
  final String endpoint;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
                  'Mutande',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Daemon unreachable',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start mutande-core serve, then retry.\n'
                  'HTTP: $endpoint',
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

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.config,
    required this.daemon,
    required this.onOnboarded,
  });

  final AppConfig config;
  final DaemonClient daemon;
  final void Function(DaemonStatusResult status) onOnboarded;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _invite;
  late final TextEditingController _handle;
  late final TextEditingController _hubUrl;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invite = TextEditingController();
    _handle = TextEditingController();
    _hubUrl = TextEditingController(text: widget.config.hubUrl);
  }

  @override
  void dispose() {
    _invite.dispose();
    _handle.dispose();
    _hubUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final invite = _invite.text.trim();
    final handle = _handle.text.trim();
    final hubUrl = _hubUrl.text.trim();
    if (invite.isEmpty) {
      setState(() => _error = 'Invite code is required.');
      return;
    }
    final handleErr = validateHandle(handle);
    if (handleErr != null) {
      setState(() => _error = handleErr);
      return;
    }
    final hubErr = validateHubUrl(hubUrl);
    if (hubErr != null) {
      setState(() => _error = hubErr);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.daemon.register(
        inviteCode: invite,
        handle: handle,
        hubUrl: hubUrl,
      );
      final status = await widget.daemon.getStatus();
      if (!mounted) return;
      widget.onOnboarded(status);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mutande',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join with an invite.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF78716C),
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _invite,
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _handle,
                  decoration: const InputDecoration(
                    labelText: 'Handle',
                    hintText: 'alice@acme',
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hubUrl,
                  decoration: const InputDecoration(
                    labelText: 'Hub URL',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  enabled: !_submitting,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join'),
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
    this.connectMessage,
    this.connectIsWarning = false,
    required this.onConnectHosts,
  });

  final AppConfig config;
  final DaemonClient daemon;
  final DaemonStatusResult status;
  final String? statusError;
  final VoidCallback? onRetryStatus;
  final bool connecting;
  final String? connectMessage;
  final bool connectIsWarning;
  final VoidCallback onConnectHosts;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = false;
  DaemonHealthResult? _health;

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

  @override
  Widget build(BuildContext context) {
    final connected = _health?.connected ?? false;
    final statusLabel = _health == null
        ? 'Unknown'
        : connected
        ? 'Connected'
        : 'Disconnected';
    final statusColor = _health == null
        ? const Color(0xFF78716C)
        : connected
        ? const Color(0xFF166534)
        : const Color(0xFF991B1B);
    final hubDisplay = widget.status.hubUrl ?? widget.config.hubUrl;
    final handle = widget.status.handle;
    final endpoint = _health?.endpoint ?? widget.daemon.httpBaseUrl;
    final transport = _health?.transport ?? 'http';

    return Scaffold(
      appBar: AppBar(title: const Text('Mutande')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Agent-to-agent mail',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF78716C),
                ),
              ),
              if (widget.statusError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Status refresh failed — showing last known session.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF92400E),
                  ),
                ),
                TextButton(
                  onPressed: widget.onRetryStatus,
                  child: const Text('Retry status'),
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusRow(
                        label: 'Daemon',
                        value: statusLabel,
                        valueColor: statusColor,
                      ),
                      if (handle != null) ...[
                        const SizedBox(height: 12),
                        _StatusRow(label: 'Handle', value: handle),
                      ],
                      const SizedBox(height: 12),
                      _StatusRow(label: 'Hub', value: hubDisplay),
                      if (_health?.service != null) ...[
                        const SizedBox(height: 12),
                        _StatusRow(
                          label: 'Service',
                          value: _health!.service!,
                        ),
                      ],
                      if (_health?.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _health!.error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF991B1B)),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Transport: $transport · $endpoint',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFA8A29E),
                        ),
                      ),
                      Text(
                        'Daemon socket (native): ${DaemonClient.defaultSocketPath}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFA8A29E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _checking ? null : _checkDaemon,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_checking ? 'Checking…' : 'Check daemon'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.connecting ? null : widget.onConnectHosts,
                icon: widget.connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  widget.connecting ? 'Connecting…' : 'Connect AI hosts',
                ),
              ),
              if (widget.connectMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.connectMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: widget.connectIsWarning
                        ? const Color(0xFF92400E)
                        : const Color(0xFF44403C),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF78716C),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: valueColor ?? const Color(0xFF292524),
            ),
          ),
        ),
      ],
    );
  }
}
