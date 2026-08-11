import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/agent_transport.dart';
import '../services/core_sidecar.dart';
import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../services/notification_prefs_store.dart';
import '../services/transport_prefs_store.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_flow.dart';
import '../widgets/connect_host_picker.dart';
import '../widgets/host_link_status.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/transport_chip.dart';

// Compact tray settings — stone surfaces, tight-within / air-between sections.
const Color _kStone50 = Color(0xFFFAFAF9);
const Color _kStone100 = Color(0xFFF5F5F4);
const Color _kStone200 = Color(0xFFE7E5E4);
const Color _kStone300 = Color(0xFFD6D3D1);
const Color _kStone400 = Color(0xFFA8A29E);
const Color _kStone500 = Color(0xFF78716C);
const Color _kStone700 = Color(0xFF44403C);
const Color _kStone800 = Color(0xFF292524);
const Color _kStone900 = Color(0xFF1C1917);
const Color _kBronze = Color(0xFF8B6914);
const Color _kBronzeSoft = Color(0xFFF5F0E6);
const Color _kGreen = Color(0xFF166534);
const Color _kRed = Color(0xFF991B1B);
const Color _kRose = Color(0xFF9F1239);
const double _kSectionGap = 28;
const double _kHeaderGap = 8;
const double _kCardRadius = 12;
const EdgeInsets _kCardPad = EdgeInsets.fromLTRB(14, 14, 14, 14);

BoxDecoration _settingsCardDecoration({Color? borderColor, Color? fill}) {
  return BoxDecoration(
    color: fill ?? Colors.white,
    borderRadius: BorderRadius.circular(_kCardRadius),
    border: Border.all(color: borderColor ?? _kStone200),
  );
}

/// Plumbing + trust — pushed from the home gear (Stitch Settings hub).
class SettingsScreen extends StatefulWidget {
  SettingsScreen({
    super.key,
    required this.daemon,
    required this.checking,
    required this.connecting,
    required this.health,
    this.connectError,
    required this.onCheckDaemon,
    this.handle,
    this.appVersion = AppConfig.appVersion,
    this.onRestartCourier,
    this.onOpenThreads,
    this.onOpenAgents,
    this.onSignedOut,
    HostLinkStore? hostLinkStore,
    NotificationPrefsStore? notificationPrefs,
    TransportPrefsStore? transportPrefs,
  }) : hostLinkStore = hostLinkStore ?? HostLinkStore(),
       notificationPrefs = notificationPrefs ?? NotificationPrefsStore(),
       transportPrefs =
           transportPrefs ?? TransportPrefsStore(daemon: daemon);

  final DaemonClient daemon;
  final bool checking;
  final bool connecting;
  final DaemonHealthResult? health;
  final String? connectError;
  final VoidCallback onCheckDaemon;
  final String? handle;
  final String appVersion;
  /// Kill stale courier + spawn bundled sidecar (macOS shell).
  final Future<String?> Function()? onRestartCourier;
  /// Close settings and jump home Threads (e.g. from agent inspector).
  final VoidCallback? onOpenThreads;
  /// Close settings and jump home Agents graph.
  final VoidCallback? onOpenAgents;
  /// After local Auth0 logout — parent should leave Home for Sign in.
  final ValueChanged<DaemonStatusResult>? onSignedOut;
  final HostLinkStore hostLinkStore;
  final NotificationPrefsStore notificationPrefs;
  final TransportPrefsStore transportPrefs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _checking = widget.checking;
  late bool _connecting = widget.connecting;
  late DaemonHealthResult? _health = widget.health;
  late String? _connectError = widget.connectError;
  DateTime? _lastPingAt;
  bool _restartingCourier = false;
  String? _restartError;
  String? _bundledCoreVersion;
  /// Soft status (Keychain wait) — not an error.
  String? _courierHint;
  SafetyNumberResult? _ours;
  bool _loadingSafety = true;
  bool _registeringDevice = false;
  bool _signingOut = false;
  Map<String, HostLinkRecord> _hostLinks = const {};
  bool _loadingLinks = true;
  NotificationPrefs _notifPrefs = const NotificationPrefs();
  /// Starts false so the card paints immediately with defaults (orb loaders
  /// never settle in widget tests). Fresh prefs still replace via [_loadNotifPrefs].
  bool _loadingNotif = false;
  TransportPrefs _transportPrefs = const TransportPrefs();
  List<AgentInfo> _agents = const [];
  bool _loadingTransport = false;

  @override
  void initState() {
    super.initState();
    if (_health?.connected == true) {
      _lastPingAt = DateTime.now();
    }
    unawaited(_refreshBundledCoreVersion());
    _loadSafety();
    _loadHostLinks();
    _loadNotifPrefs();
    _loadTransportPrefs();
  }

  Future<void> _refreshBundledCoreVersion() async {
    final version = await CoreSidecar.bundledCoreVersion();
    if (!mounted) return;
    setState(() => _bundledCoreVersion = version);
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking != widget.checking) {
      _checking = widget.checking;
    }
    if (oldWidget.connecting != widget.connecting) {
      _connecting = widget.connecting;
    }
    if (oldWidget.health != widget.health) {
      _health = widget.health;
    }
    if (oldWidget.connectError != widget.connectError) {
      _connectError = widget.connectError;
    }
  }

  Future<void> _loadNotifPrefs() async {
    final prefs = await widget.notificationPrefs.load();
    if (!mounted) return;
    setState(() {
      _notifPrefs = prefs;
      _loadingNotif = false;
    });
  }

  Future<void> _saveNotif(NotificationPrefs prefs) async {
    await widget.notificationPrefs.save(prefs);
    if (!mounted) return;
    setState(() => _notifPrefs = prefs);
  }

  Future<void> _loadTransportPrefs() async {
    setState(() => _loadingTransport = true);
    try {
      // Store already has daemon when constructed via Settings/app; keep attached.
      widget.transportPrefs.daemon ??= widget.daemon;
      // Prefer hub when courier is up; local file remains offline fallback.
      final prefs = _health?.connected == true
          ? await widget.transportPrefs.syncFromHub()
          : await widget.transportPrefs.load();
      List<AgentInfo> agents = const [];
      try {
        final list = await widget.daemon.listAgents();
        agents = list.agents;
      } catch (_) {
        // Prefs still useful; dual-slot section stays empty until agents load.
      }
      if (!mounted) return;
      setState(() {
        _transportPrefs = prefs;
        _agents = agents;
        _loadingTransport = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTransport = false);
    }
  }

  Future<void> _setDefaultTransport(String slug, AgentTransport transport) async {
    final prefs = await widget.transportPrefs.setDefault(slug, transport);
    if (!mounted) return;
    setState(() => _transportPrefs = prefs);
  }

  Future<void> _loadHostLinks() async {
    final links = await widget.hostLinkStore.load();
    if (!mounted) return;
    setState(() {
      _hostLinks = links;
      _loadingLinks = false;
    });
  }

  Future<void> _loadSafety() async {
    try {
      final ours = await widget.daemon.getSafetyNumber();
      if (!mounted) return;
      setState(() {
        _ours = ours;
        _loadingSafety = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSafety = false);
    }
  }

  Future<void> _forceRegisterDevice() async {
    if (_registeringDevice) return;
    setState(() => _registeringDevice = true);
    try {
      await widget.daemon.registerDevice();
      final ours = await widget.daemon.getSafetyNumber();
      if (!mounted) return;
      setState(() {
        _ours = ours;
        _registeringDevice = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Device pubkey registered with the hub.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _registeringDevice = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(friendlyDaemonError(e, what: 'Register device')),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You’ll need to sign in again to use mutande on this Mac. '
          'Your device keys stay on this machine.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _kRose),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      final status = await widget.daemon.authLogout();
      if (!mounted) return;
      widget.onSignedOut?.call(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(friendlyDaemonError(e, what: 'Sign out')),
        ),
      );
    }
  }

  Future<void> _check() async {
    if (_checking || _restartingCourier) return;
    setState(() {
      _checking = true;
      _restartError = null;
      _courierHint = null;
    });
    widget.onCheckDaemon();
    final result = await widget.daemon.pingHealth();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _health = result;
      _lastPingAt = DateTime.now();
      if (result.connected) _courierHint = null;
    });
    await _refreshBundledCoreVersion();
  }

  Future<void> _restartCourier() async {
    final restart = widget.onRestartCourier;
    if (restart == null || _checking || _restartingCourier) return;
    setState(() {
      _restartingCourier = true;
      _restartError = null;
      _courierHint = null;
    });
    final err = await restart();
    if (!mounted) return;
    final result = await widget.daemon.pingHealth();
    if (!mounted) return;
    setState(() {
      _restartingCourier = false;
      _health = result;
      _lastPingAt = DateTime.now();
      _restartError = err;
      // Keychain unlock can outlast the restart call — don't treat as hard fail.
      if (err == null && !result.connected) {
        _courierHint =
            'If Keychain asks, unlock to finish starting the courier.';
      } else {
        _courierHint = null;
      }
    });
    await _refreshBundledCoreVersion();
  }

  Future<void> _pickAndConnect() async {
    final host = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x660C0A09),
      builder: (context) => const ConnectHostPicker(
        title: 'Connect AI host',
        subtitle: 'Links MCP and the collaboration skill for the host you choose.',
      ),
    );
    if (host == null || !mounted) return;
    await _connectHost(host);
  }

  Future<void> _connectHost(String host, {Rect? morphOrigin}) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      final result = await showConnectHostFlow(
        context: context,
        daemon: widget.daemon,
        hostLinkStore: widget.hostLinkStore,
        host: host,
        morphOrigin: morphOrigin,
      );
      if (!mounted) return;
      await _loadHostLinks();
      if (!mounted) return;
      setState(() => _connecting = false);

      final label = AiHostIcon.displayName(host);
      if (result == null || !result.mcpOk) {
        if (result == null) return; // dismissed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not link $label.')),
        );
      } else {
        final skill = switch (result.skillStatus) {
          SkillLinkStatus.installed => 'Skill ready.',
          SkillLinkStatus.needsSetup => 'Skill needs a quick setup step.',
          SkillLinkStatus.skipped => 'Skill skipped — finish anytime here.',
          SkillLinkStatus.none => '',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skill.isEmpty ? 'Linked $label' : 'Linked $label. $skill',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = friendlyDaemonError(e, what: 'Connect');
      });
    }
  }

  void _openCompare() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kStone50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _CompareSheet(daemon: widget.daemon, ours: _ours),
      ),
    );
  }

  bool get _showDefaultTransportSection {
    if (_loadingTransport) return false;
    return dualTransportSlugs(
      _agents.map((a) => (slug: a.slug, transport: a.transport)),
    ).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final connected = _health?.connected == true;
    final agentsEnabled = widget.onOpenAgents != null;

    return Scaffold(
      backgroundColor: _kStone50,
      appBar: AppBar(
        backgroundColor: _kStone50,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 22),
        ),
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(
              context,
              label: 'DAEMON',
              trailing: Text(
                connected ? 'Connected' : 'Unreachable',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: connected ? _kGreen : _kRed,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              child: _DaemonCard(
                health: _health,
                checking: _checking,
                restarting: _restartingCourier,
                lastPingAt: _lastPingAt,
                connected: connected,
                appVersion: widget.appVersion,
                bundledCoreVersion: _bundledCoreVersion,
                restartError: _restartError,
                courierHint: _courierHint,
                onCheck: _check,
                onRestartCourier:
                    widget.onRestartCourier == null ? null : _restartCourier,
              ),
            ),
            _section(
              context,
              label: 'AGENTS',
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  side: const BorderSide(color: _kStone200),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: agentsEnabled ? widget.onOpenAgents : null,
                  child: Padding(
                    padding: _kCardPad,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Agents & routing',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: agentsEnabled
                                      ? _kStone800
                                      : _kStone400,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                agentsEnabled
                                    ? 'Open the Agents graph tab'
                                    : 'Unavailable in this window',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _kStone400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: agentsEnabled ? _kStone400 : _kStone300,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _section(
              context,
              label: 'AI HOSTS',
              trailing: TextButton(
                onPressed: _connecting ? null : _pickAndConnect,
                style: TextButton.styleFrom(
                  foregroundColor: _kBronze,
                  disabledForegroundColor: _kStone400,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _connecting ? 'Connecting…' : 'Connect new host',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HostsCard(
                    links: _hostLinks,
                    loading: _loadingLinks,
                    enabled: !_connecting,
                    onHostTap: (host, origin) =>
                        _connectHost(host, morphOrigin: origin),
                  ),
                  if (_connectError != null) ...[
                    const SizedBox(height: 10),
                    _ErrorBanner(
                      message: _connectError!,
                      onDismiss: () => setState(() => _connectError = null),
                    ),
                  ],
                ],
              ),
            ),
            _section(
              context,
              label: 'NOTIFICATIONS',
              child: _NotificationsCard(
                prefs: _notifPrefs,
                loading: _loadingNotif,
                onChanged: _saveNotif,
              ),
            ),
            if (_showDefaultTransportSection)
              _section(
                context,
                label: 'DEFAULT TRANSPORT',
                child: _DefaultTransportCard(
                  agents: _agents,
                  prefs: _transportPrefs,
                  loading: _loadingTransport,
                  onChanged: _setDefaultTransport,
                ),
              ),
            _section(
              context,
              label: 'SECURITY VERIFICATION',
              child: _SafetyCard(
                ours: _ours,
                loading: _loadingSafety,
                registering: _registeringDevice,
                onCompare: _openCompare,
                onRegisterDevice: _forceRegisterDevice,
              ),
            ),
            _section(
              context,
              label: 'EXTERNAL CONTACTS',
              child: Container(
                width: double.infinity,
                padding: _kCardPad,
                decoration: _settingsCardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pair external contact',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _kStone800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Share a 6-digit PIN from Contacts → External, or add someone else’s handle + PIN. Cross-org mail uses app envelope (not E2E).',
                      style: TextStyle(fontSize: 12, color: _kStone500, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
            _section(
              context,
              label: 'ACCOUNT',
              child: _AccountCard(
                handle: widget.handle,
                signingOut: _signingOut,
                onSignOut: widget.onSignedOut == null ? null : _signOut,
              ),
            ),
            _section(
              context,
              label: 'FEEDBACK',
              child: _FeedbackCard(
                daemon: widget.daemon,
                appVersion: widget.appVersion,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String label,
    required Widget child,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _kSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context, label, trailing: trailing),
          const SizedBox(height: _kHeaderGap),
          child,
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String label, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _kStone400,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  fontSize: 11,
                ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _DaemonCard extends StatelessWidget {
  const _DaemonCard({
    required this.health,
    required this.checking,
    required this.restarting,
    required this.lastPingAt,
    required this.connected,
    required this.appVersion,
    this.bundledCoreVersion,
    this.restartError,
    this.courierHint,
    required this.onCheck,
    this.onRestartCourier,
  });

  final DaemonHealthResult? health;
  final bool checking;
  final bool restarting;
  final DateTime? lastPingAt;
  final bool connected;
  final String appVersion;
  final String? bundledCoreVersion;
  final String? restartError;
  final String? courierHint;
  final VoidCallback onCheck;
  final VoidCallback? onRestartCourier;

  bool get _busy => checking || restarting;

  bool get _versionMismatch {
    if (!connected) return false;
    final app = CoreSidecar.normalizeVersion(appVersion);
    if (app == null) return false;
    return !CoreSidecar.versionsMatch(health?.version, app);
  }

  /// Bundled Resources binary differs from this app — restart cannot fix.
  bool get _bundledStale {
    final bundled = CoreSidecar.normalizeVersion(bundledCoreVersion);
    final app = CoreSidecar.normalizeVersion(appVersion);
    if (bundled == null || app == null) return false;
    return bundled != app;
  }

  @override
  Widget build(BuildContext context) {
    final version = CoreSidecar.normalizeVersion(health?.version);
    final appVer = CoreSidecar.normalizeVersion(appVersion) ?? appVersion;
    final detail = !connected
        ? (health?.error?.trim().isNotEmpty == true
            ? health!.error!.trim()
            : 'Courier unreachable')
        : version != null
            ? 'mutande-core v$version'
            : 'mutande-core · version unknown';
    final ping = lastPingAt == null
        ? 'Last check: —'
        : 'Last check: ${_relativePing(lastPingAt!)}';
    final showRestart = onRestartCourier != null && !_bundledStale;

    return Container(
      padding: _kCardPad,
      decoration: _settingsCardDecoration(
        borderColor: _versionMismatch ? const Color(0xFFD6C4A1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Local courier',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _kStone800,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            checking
                ? 'Checking…'
                : (restarting ? 'Restarting courier…' : detail),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: connected ? _kStone500 : _kStone700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            ping,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _kStone400,
                  fontSize: 11,
                ),
          ),
          if (connected && !_versionMismatch && version != null) ...[
            const SizedBox(height: 2),
            Text(
              'Matches app v$appVer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kStone400,
                    fontSize: 11,
                  ),
            ),
          ],
          if (_versionMismatch) ...[
            const SizedBox(height: 10),
            _DaemonMismatchBanner(
              appVersion: appVer,
              courierVersion: version,
              bundledCoreVersion: bundledCoreVersion,
            ),
          ],
          if (courierHint != null && courierHint!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              courierHint!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kStone500,
                    fontSize: 12,
                    height: 1.35,
                  ),
            ),
          ],
          if (restartError != null && restartError!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              restartError!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kRose,
                    fontSize: 12,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : onCheck,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kStone700,
                    side: const BorderSide(color: _kStone300),
                    backgroundColor: _kStone100,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: checking
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MutandeOrb.loading(
                              semanticLabel: 'Checking daemon',
                            ),
                            SizedBox(width: 8),
                            Text('Checking…'),
                          ],
                        )
                      : const Text('Check daemon'),
                ),
              ),
              if (showRestart) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : onRestartCourier,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBronze,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kBronze.withValues(alpha: 0.45),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: restarting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MutandeOrb.loading(
                                dark: true,
                                semanticLabel: 'Restarting courier',
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Restarting…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Restart courier',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _relativePing(DateTime at) {
    final ms = DateTime.now().difference(at).inMilliseconds;
    if (ms < 1000) return '${ms.clamp(1, 999)}ms ago';
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 60) return '${s}s ago';
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
}

class _DaemonMismatchBanner extends StatelessWidget {
  const _DaemonMismatchBanner({
    required this.appVersion,
    required this.courierVersion,
    this.bundledCoreVersion,
  });

  final String appVersion;
  final String? courierVersion;
  final String? bundledCoreVersion;

  @override
  Widget build(BuildContext context) {
    final courier = courierVersion == null || courierVersion!.isEmpty
        ? 'unknown'
        : 'v$courierVersion';
    final bundled = CoreSidecar.normalizeVersion(bundledCoreVersion);
    final app = CoreSidecar.normalizeVersion(appVersion);
    final bundledStale =
        bundled != null && app != null && bundled != app;
    final message = bundledStale
        ? 'Sidecar mismatch — app v$appVersion, courier $courier '
            '(bundled v$bundled). Restart cannot fix this — reinstall mutande '
            'from mutande.online/download so app and courier versions match.'
        : 'Sidecar mismatch — app v$appVersion, courier $courier. '
            'Restart courier to replace a stale external daemon. '
            'If this persists after restart, reinstall mutande.';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _kBronzeSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6C4A1)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _kBronze,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

class _HostsCard extends StatelessWidget {
  const _HostsCard({
    required this.links,
    required this.loading,
    required this.enabled,
    required this.onHostTap,
  });

  final Map<String, HostLinkRecord> links;
  final bool loading;
  final bool enabled;
  final void Function(String host, Rect? morphOrigin) onHostTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        decoration: _settingsCardDecoration(),
        child: Text(
          'Loading hosts…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _kStone400,
              ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < AiHostCatalog.hosts.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _HostTile(
              host: AiHostCatalog.hosts[i].$1,
              label: AiHostCatalog.hosts[i].$2,
              link: links[AiHostCatalog.hosts[i].$1],
              enabled: enabled,
              onTap: onHostTap,
            ),
          ),
        ],
      ],
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({
    required this.host,
    required this.label,
    required this.link,
    required this.enabled,
    required this.onTap,
  });

  final String host;
  final String label;
  final HostLinkRecord? link;
  final bool enabled;
  final void Function(String host, Rect? morphOrigin) onTap;

  String get _compactLabel {
    switch (host) {
      case 'claude':
        return 'Claude';
      default:
        return label;
    }
  }

  String _skillLabel(SkillLinkStatus? s) {
    if (s == null) return 'Tap to connect';
    switch (s) {
      case SkillLinkStatus.installed:
        return 'Skill · installed';
      case SkillLinkStatus.needsSetup:
        return 'Skill · needs setup';
      case SkillLinkStatus.skipped:
        return 'Skill · skipped';
      case SkillLinkStatus.none:
        return link?.ok == true ? 'Skill · —' : 'Tap to connect';
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = link?.ok == true;
    final failed = link != null && !link!.ok;
    final skillLine = linked
        ? _skillLabel(link!.skillStatus)
        : (failed ? 'Tap to retry' : 'Tap to connect');

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$_compactLabel, ${linked ? 'linked' : failed ? 'failed' : 'not linked'}. $skillLine',
      child: Material(
        color: linked ? const Color(0xFFF7FDF9) : Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kCardRadius),
          onTap: !enabled
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox?;
                  final origin = (box != null && box.hasSize)
                      ? box.localToGlobal(Offset.zero) & box.size
                      : null;
                  onTap(host, origin);
                },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kCardRadius),
              border: Border.all(
                color: linked
                    ? const Color(0xFF86EFAC)
                    : failed
                        ? const Color(0xFFFECACA)
                        : _kStone200,
                width: linked || failed ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: connectHostIconHeroTag(host),
                    child: Material(
                      type: MaterialType.transparency,
                      child: AiHostIcon(host, size: 40),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _compactLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _kStone800,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: 8),
                  HostLinkStatusBadge(
                    link: link,
                    style: HostLinkStatusStyle.settings,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 28,
                    child: Text(
                      skillLine,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: linked ? _kStone500 : _kBronze,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultTransportCard extends StatelessWidget {
  const _DefaultTransportCard({
    required this.agents,
    required this.prefs,
    required this.loading,
    required this.onChanged,
  });

  final List<AgentInfo> agents;
  final TransportPrefs prefs;
  final bool loading;
  final void Function(String slug, AgentTransport transport) onChanged;

  @override
  Widget build(BuildContext context) {
    final dual = dualTransportSlugs(
      agents.map((a) => (slug: a.slug, transport: a.transport)),
    );

    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        decoration: _settingsCardDecoration(),
        child: Text(
          'Loading…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _kStone400,
              ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kCardRadius),
        side: const BorderSide(color: _kStone200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              'When an agent has both sidecar and web, bare @slug uses this default.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kStone500,
                    height: 1.35,
                  ),
            ),
          ),
          for (var i = 0; i < dual.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: _kStone100),
            _DefaultTransportRow(
              slug: dual[i],
              value: prefs.defaultFor(dual[i]) ?? AgentTransport.sidecar,
              onChanged: (t) => onChanged(dual[i], t),
            ),
          ],
        ],
      ),
    );
  }
}

class _DefaultTransportRow extends StatelessWidget {
  const _DefaultTransportRow({
    required this.slug,
    required this.value,
    required this.onChanged,
  });

  final String slug;
  final AgentTransport value;
  final ValueChanged<AgentTransport> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          AiHostIcon(slug, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slug,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _kStone800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    TransportChip(transport: value, compact: true),
                  ],
                ),
              ],
            ),
          ),
          SegmentedButton<AgentTransport>(
            segments: const [
              ButtonSegment(
                value: AgentTransport.sidecar,
                label: Text('Sidecar'),
              ),
              ButtonSegment(
                value: AgentTransport.mcp,
                label: Text('Web'),
              ),
            ],
            selected: {value},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              onChanged(next.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({
    required this.prefs,
    required this.loading,
    required this.onChanged,
  });

  final NotificationPrefs prefs;
  final bool loading;
  final ValueChanged<NotificationPrefs> onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        decoration: _settingsCardDecoration(),
        child: Text(
          'Loading…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _kStone400,
              ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kCardRadius),
        side: const BorderSide(color: _kStone200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('Enable notifications'),
            subtitle: const Text(
              'Local banners when mail arrives for cold hosts',
            ),
            value: prefs.enabled,
            onChanged: (v) => onChanged(prefs.copyWith(enabled: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('New mail for my agents'),
            value: prefs.mailForAgents,
            onChanged: prefs.enabled
                ? (v) => onChanged(prefs.copyWith(mailForAgents: v))
                : null,
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('Needs you'),
            subtitle: const Text('Human decisions waiting in mutande'),
            value: prefs.needsYou,
            onChanged: prefs.enabled
                ? (v) => onChanged(prefs.copyWith(needsYou: v))
                : null,
          ),
          const Divider(height: 1, thickness: 1, color: _kStone100),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Agents',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _kStone400,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
              ),
            ),
          ),
          for (final slug in const ['cursor', 'claude', 'chatgpt'])
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: AiHostIcon(slug, size: 28),
              title: Text(
                AiHostIcon.displayName(slug),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              value: prefs.isAgentEnabled(slug),
              onChanged: prefs.enabled && prefs.mailForAgents
                  ? (v) {
                      final next = Map<String, bool>.from(prefs.agentSlugsEnabled);
                      next[slug] = v;
                      onChanged(prefs.copyWith(agentSlugsEnabled: next));
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({
    required this.ours,
    required this.loading,
    required this.registering,
    required this.onCompare,
    required this.onRegisterDevice,
  });

  final SafetyNumberResult? ours;
  final bool loading;
  final bool registering;
  final VoidCallback onCompare;
  final VoidCallback onRegisterDevice;

  @override
  Widget build(BuildContext context) {
    final groups = _digitGroups(ours?.fingerprint ?? '');
    final pubkey = ours?.pubkey?.trim() ?? '';

    final canCompare = !loading && groups.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      decoration: BoxDecoration(
        color: _kStone900,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(
              Icons.verified_user_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Safety Numbers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Compare these numbers with your teammate out of band to confirm end-to-end encryption.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _kStone400,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 16),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: MutandeOrb.loading(semanticLabel: 'Loading…'),
                  ),
                )
              else if (groups.isEmpty)
                Text(
                  'Safety numbers unavailable until the daemon is configured.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _kStone400,
                      ),
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < groups.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _DigitBlock(
                          top: groups[i].$1,
                          bottom: groups[i].$2,
                        ),
                      ),
                    ],
                  ],
                ),
              if (!loading) ...[
                const SizedBox(height: 14),
                _DevicePubkeyRow(pubkey: pubkey),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: canCompare ? onCompare : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF44403C),
                    foregroundColor: _kStone900,
                    disabledForegroundColor: _kStone400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text(
                    'Compare safety numbers',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              TextButton(
                onPressed: registering ? null : onRegisterDevice,
                style: TextButton.styleFrom(
                  foregroundColor: _kStone400,
                  disabledForegroundColor: _kStone500,
                  minimumSize: const Size(0, 40),
                ),
                child: Text(
                  registering ? 'Registering…' : 'Register this device',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// First 6 five-digit groups → 3 boxes of (top, bottom).
  static List<(String, String)> _digitGroups(String fingerprint) {
    final parts = fingerprint
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const [];
    final pairs = <(String, String)>[];
    for (var i = 0; i + 1 < parts.length && pairs.length < 3; i += 2) {
      pairs.add((parts[i], parts[i + 1]));
    }
    return pairs;
  }
}

class _DevicePubkeyRow extends StatelessWidget {
  const _DevicePubkeyRow({required this.pubkey});

  final String pubkey;

  @override
  Widget build(BuildContext context) {
    final missing = pubkey.isEmpty;
    final preview = missing
        ? 'No local device key yet'
        : pubkey.length <= 20
            ? pubkey
            : '${pubkey.substring(0, 10)}…${pubkey.substring(pubkey.length - 8)}';

    return Material(
      color: _kStone800,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: missing
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: pubkey));
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Device pubkey copied')),
                );
              },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This device pubkey',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _kStone400,
                            letterSpacing: 0.3,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        height: 1.3,
                        color: missing
                            ? _kStone500
                            : Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              if (!missing)
                Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DigitBlock extends StatelessWidget {
  const _DigitBlock({required this.top, required this.bottom});

  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: _kStone800,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              top,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              bottom,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    this.handle,
    this.signingOut = false,
    this.onSignOut,
  });

  final String? handle;
  final bool signingOut;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final hasHandle = handle != null && handle!.trim().isNotEmpty;
    final h = hasHandle ? formatMailAddress(handle!) : 'Not signed in';
    final initial = hasHandle ? h.characters.first.toUpperCase() : '?';
    final handleText = Text(
      h,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: hasHandle ? _kStone800 : _kStone500,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            height: 1.25,
          ),
    );

    return Container(
      decoration: _settingsCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: _kCardPad,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _kStone100,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Color(0xFF57534E),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasHandle)
                        Tooltip(
                          message: 'Copy handle',
                          child: InkWell(
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(text: h));
                              if (!context.mounted) return;
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(content: Text('Handle copied')),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: handleText,
                          ),
                        )
                      else
                        handleText,
                      const SizedBox(height: 3),
                      Text(
                        hasHandle
                            ? 'On this Mac'
                            : 'Sign in to use mutande on this Mac',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _kStone400,
                              fontSize: 12,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onSignOut != null) ...[
            const Divider(height: 1, thickness: 1, color: _kStone100),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: signingOut ? null : onSignOut,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 16,
                          color: signingOut ? _kStone300 : _kRose,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          signingOut ? 'Signing out…' : 'Sign out',
                          style: TextStyle(
                            color: signingOut ? _kStone400 : _kRose,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatefulWidget {
  const _FeedbackCard({
    required this.daemon,
    required this.appVersion,
  });

  final DaemonClient daemon;
  final String appVersion;

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a short note first.');
      return;
    }
    if (message.length > 4000) {
      setState(() => _error = 'Keep feedback under 4,000 characters.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await widget.daemon.submitFeedback(
        message: message,
        category: 'pilot',
        appVersion: widget.appVersion,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = friendlyDaemonError(e, what: 'Feedback');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _kCardPad,
      decoration: _settingsCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us what broke or felt off. Goes to the mutande team — not into threads.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _kStone500,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            enabled: !_sending,
            onChanged: (_) {
              if (_sent || _error != null) {
                setState(() {
                  _sent = false;
                  _error = null;
                });
              }
            },
            decoration: const InputDecoration(
              hintText: 'e.g. Connect hosts failed on Claude…',
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kRed,
                  ),
            ),
          ],
          if (_sent) ...[
            const SizedBox(height: 8),
            Text(
              'Sent — thank you.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kGreen,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const MutandeOrb.loading(semanticLabel: 'Sending…')
                  : const Text('Send feedback'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    var msg = message;
    if (msg.startsWith('DaemonException: ')) {
      msg = msg.substring('DaemonException: '.length);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, size: 16, color: _kRed),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _kRed,
                    height: 1.35,
                  ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: _kRed,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _CompareSheet extends StatefulWidget {
  const _CompareSheet({required this.daemon, this.ours});

  final DaemonClient daemon;
  final SafetyNumberResult? ours;

  @override
  State<_CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends State<_CompareSheet> {
  final _handle = TextEditingController();
  final _compare = TextEditingController();
  bool _loading = false;
  String? _error;
  bool? _verified;
  SafetyNumberResult? _theirs;

  @override
  void dispose() {
    _handle.dispose();
    _compare.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final handle = _handle.text.trim();
    final fp = _compare.text.trim();
    if (handle.isEmpty || fp.isEmpty) {
      setState(() => _error = 'Handle and fingerprint (or QR URI) required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.daemon.verifyContact(
        handle: handle,
        fingerprint: fp,
      );
      if (!mounted) return;
      setState(() {
        _theirs = result;
        _verified = result.verified;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyDaemonError(e, what: 'Compare');
        _loading = false;
        _verified = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Compare safety numbers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _kStone800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            if (widget.ours != null) ...[
              const SizedBox(height: 8),
              Text(
                'Your number',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _kStone500,
                    ),
              ),
              SelectableText(
                widget.ours!.fingerprint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      color: _kStone800,
                    ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: widget.ours!.uri),
                    );
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Safety URI copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy URI'),
                ),
              ),
            ],
            TextField(
              controller: _handle,
              decoration: const InputDecoration(
                labelText: 'Handle',
                hintText: 'alice@acme',
              ),
              enabled: !_loading,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _compare,
              decoration: const InputDecoration(
                labelText: 'Their number or QR URI',
                hintText: 'Paste digits or mutande:safety:…',
              ),
              enabled: !_loading,
              minLines: 1,
              maxLines: 3,
              onSubmitted: (_) {
                if (!_loading) _verify();
              },
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loading ? null : _verify,
              style: FilledButton.styleFrom(
                backgroundColor: _kStone900,
                minimumSize: const Size(0, 44),
              ),
              child: _loading
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MutandeOrb.loading(
                          semanticLabel: 'Checking…',
                          dark: true,
                        ),
                        SizedBox(width: 8),
                        Text('Checking…'),
                      ],
                    )
                  : const Text('Compare'),
            ),
            if (_verified != null) ...[
              const SizedBox(height: 12),
              Text(
                _verified!
                    ? 'Match — contact verified.'
                    : 'No match — do not trust yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _verified! ? _kGreen : _kRed,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (_theirs != null && _verified == null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _theirs!.fingerprint,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _kRed,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
