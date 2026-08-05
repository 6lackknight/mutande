import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../services/notification_prefs_store.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_flow.dart';
import '../widgets/connect_host_picker.dart';
import '../widgets/host_link_status.dart';
import '../widgets/thinking_orb.dart';

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
    this.onOpenThreads,
    this.onOpenAgents,
    this.onSignedOut,
    HostLinkStore? hostLinkStore,
    NotificationPrefsStore? notificationPrefs,
  }) : hostLinkStore = hostLinkStore ?? HostLinkStore(),
       notificationPrefs = notificationPrefs ?? NotificationPrefsStore();

  final DaemonClient daemon;
  final bool checking;
  final bool connecting;
  final DaemonHealthResult? health;
  final String? connectError;
  final VoidCallback onCheckDaemon;
  final String? handle;
  final String appVersion;
  /// Close settings and jump home Threads (e.g. from agent inspector).
  final VoidCallback? onOpenThreads;
  /// Close settings and jump home Agents graph.
  final VoidCallback? onOpenAgents;
  /// After local Auth0 logout — parent should leave Home for Sign in.
  final ValueChanged<DaemonStatusResult>? onSignedOut;
  final HostLinkStore hostLinkStore;
  final NotificationPrefsStore notificationPrefs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _checking = widget.checking;
  late bool _connecting = widget.connecting;
  late DaemonHealthResult? _health = widget.health;
  late String? _connectError = widget.connectError;
  DateTime? _lastPingAt;
  SafetyNumberResult? _ours;
  bool _loadingSafety = true;
  Map<String, HostLinkRecord> _hostLinks = const {};
  bool _loadingLinks = true;
  NotificationPrefs _notifPrefs = const NotificationPrefs();
  bool _loadingNotif = false;
  static const _bronze = Color(0xFF8B6914);
  static const _stone400 = Color(0xFFA8A29E);
  static const _stone50 = Color(0xFFFAFAF9);
  static const _green = Color(0xFF166534);

  @override
  void initState() {
    super.initState();
    if (_health?.connected == true) {
      _lastPingAt = DateTime.now();
    }
    _loadSafety();
    _loadHostLinks();
    _loadNotifPrefs();
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

  Future<void> _signOut() async {
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final status = await widget.daemon.authLogout();
      if (!mounted) return;
      widget.onSignedOut?.call(status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Couldn’t sign out: $e')),
      );
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    widget.onCheckDaemon();
    final result = await widget.daemon.pingHealth();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _health = result;
      if (result.connected) _lastPingAt = DateTime.now();
    });
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
      );
      if (!mounted) return;
      await _loadHostLinks();
      if (!mounted) return;
      setState(() => _connecting = false);

      final label = AiHostIcon.displayName(host);
      if (result == null || !result.mcpOk) {
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
      backgroundColor: _stone50,
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

  @override
  Widget build(BuildContext context) {
    final connected = _health?.connected == true;

    return Scaffold(
      backgroundColor: _stone50,
      appBar: AppBar(
        backgroundColor: _stone50,
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(
              context,
              'DAEMON',
              trailing: Text(
                connected ? 'Connected' : 'Unreachable',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: connected ? _green : const Color(0xFF991B1B),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            _DaemonCard(
              health: _health,
              checking: _checking,
              lastPingAt: _lastPingAt,
              connected: connected,
              onCheck: _check,
              onRetry: _check,
            ),
            const SizedBox(height: 28),
            _sectionHeader(context, 'AGENTS'),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (widget.onOpenAgents != null) {
                    widget.onOpenAgents!();
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                                color: Color(0xFF292524),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Open the Agents graph tab',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFA8A29E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Color(0xFFA8A29E)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _sectionHeader(
              context,
              'AI HOSTS',
              trailing: TextButton(
                onPressed: _connecting ? null : _pickAndConnect,
                style: TextButton.styleFrom(
                  foregroundColor: _bronze,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
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
            ),
            const SizedBox(height: 8),
            _HostsCard(links: _hostLinks, loading: _loadingLinks),
            if (_connectError != null) ...[
              const SizedBox(height: 10),
              _ErrorBanner(message: _connectError!),
            ],
            const SizedBox(height: 28),
            _sectionHeader(context, 'NOTIFICATIONS'),
            const SizedBox(height: 8),
            _NotificationsCard(
              prefs: _notifPrefs,
              loading: _loadingNotif,
              onChanged: _saveNotif,
            ),
            const SizedBox(height: 28),
            _sectionHeader(context, 'SECURITY VERIFICATION'),
            const SizedBox(height: 8),
            _SafetyCard(
              ours: _ours,
              loading: _loadingSafety,
              onCompare: _openCompare,
            ),
            const SizedBox(height: 28),
            _sectionHeader(context, 'ACCOUNT'),
            const SizedBox(height: 8),
            _AccountCard(
              handle: widget.handle,
              onSignOut: widget.onSignedOut == null ? null : _signOut,
            ),
            const SizedBox(height: 28),
            _sectionHeader(context, 'FEEDBACK'),
            const SizedBox(height: 8),
            _FeedbackCard(
              daemon: widget.daemon,
              appVersion: widget.appVersion,
            ),
          ],
        ),
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
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _stone400,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                fontSize: 11,
              ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _DaemonCard extends StatelessWidget {
  const _DaemonCard({
    required this.health,
    required this.checking,
    required this.lastPingAt,
    required this.connected,
    required this.onCheck,
    required this.onRetry,
  });

  final DaemonHealthResult? health;
  final bool checking;
  final DateTime? lastPingAt;
  final bool connected;
  final VoidCallback onCheck;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final version = health?.version;
    final title = 'Local courier';
    final detail = version != null && version.isNotEmpty
        ? 'mutande-core v$version'
        : 'mutande-core';
    final ping = lastPingAt == null
        ? 'Last check: —'
        : 'Last check: ${_relativePing(lastPingAt!)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF292524),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            checking ? 'Checking…' : detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF78716C),
                ),
          ),
          if (!checking && connected) ...[
            const SizedBox(height: 2),
            Text(
              ping,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA8A29E),
                    fontSize: 11,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          if (connected)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: checking ? null : onCheck,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF44403C),
                  side: const BorderSide(color: Color(0xFFD6D3D1)),
                  backgroundColor: const Color(0xFFF5F5F4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(checking ? '…' : 'Check daemon'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: checking ? null : onCheck,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF44403C),
                      side: const BorderSide(color: Color(0xFFD6D3D1)),
                      backgroundColor: const Color(0xFFF5F5F4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(checking ? '…' : 'Check daemon'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: checking ? null : onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B6914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ),
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

class _HostsCard extends StatelessWidget {
  const _HostsCard({required this.links, required this.loading});

  final Map<String, HostLinkRecord> links;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: MutandeOrb.loading(semanticLabel: 'Loading hosts…'),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < AiHostCatalog.hosts.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _HostTile(
              host: AiHostCatalog.hosts[i].$1,
              label: AiHostCatalog.hosts[i].$2,
              link: links[AiHostCatalog.hosts[i].$1],
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
  });

  final String host;
  final String label;
  final HostLinkRecord? link;

  String get _compactLabel {
    switch (host) {
      case 'claude':
        return 'Claude';
      default:
        return label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked = link?.ok == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: linked ? const Color(0xFFBBF7D0) : const Color(0xFFE7E5E4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiHostIcon(host, size: 40),
          const SizedBox(height: 10),
          Text(
            _compactLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF292524),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
          ),
          const SizedBox(height: 8),
          HostLinkStatusBadge(link: link, style: HostLinkStatusStyle.settings),
          if (link != null && link!.ok) ...[
            const SizedBox(height: 4),
            Text(
              _skillLabel(link!.skillStatus),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF78716C),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _skillLabel(SkillLinkStatus s) {
    switch (s) {
      case SkillLinkStatus.installed:
        return 'Skill · installed';
      case SkillLinkStatus.needsSetup:
        return 'Skill · needs setup';
      case SkillLinkStatus.skipped:
        return 'Skill · skipped';
      case SkillLinkStatus.none:
        return 'Skill · —';
    }
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: MutandeOrb.loading(semanticLabel: 'Loading notifications…'),
        ),
      );
    }

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE7E5E4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Enable notifications'),
            subtitle: const Text('Local banners when mail arrives for cold hosts'),
            value: prefs.enabled,
            onChanged: (v) => onChanged(prefs.copyWith(enabled: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('New mail for my agents'),
            value: prefs.mailForAgents,
            onChanged: prefs.enabled
                ? (v) => onChanged(prefs.copyWith(mailForAgents: v))
                : null,
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Needs you'),
            subtitle: const Text('Human decisions waiting in mutande'),
            value: prefs.needsYou,
            onChanged: prefs.enabled
                ? (v) => onChanged(prefs.copyWith(needsYou: v))
                : null,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Agents',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFA8A29E),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
              ),
            ),
          ),
          for (final slug in const ['cursor', 'claude', 'chatgpt'])
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: AiHostIcon(slug, size: 28),
              title: Text(AiHostIcon.displayName(slug)),
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
    required this.onCompare,
  });

  final SafetyNumberResult? ours;
  final bool loading;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final groups = _digitGroups(ours?.fingerprint ?? '');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1917),
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
                'Compare these numbers with your host to ensure the connection is end-to-end encrypted.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFA8A29E),
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
                        color: const Color(0xFFA8A29E),
                      ),
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < groups.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _DigitBlock(top: groups[i].$1, bottom: groups[i].$2)),
                    ],
                  ],
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: onCompare,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1C1917),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text(
                    'Compare safety numbers',
                    style: TextStyle(fontWeight: FontWeight.w600),
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

class _DigitBlock extends StatelessWidget {
  const _DigitBlock({required this.top, required this.bottom});

  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF292524),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            top,
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            bottom,
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({this.handle, this.onSignOut});

  final String? handle;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final h = (handle != null && handle!.isNotEmpty) ? handle! : '—';
    final initial = h != '—' ? h[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE7E5E4),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF57534E),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  h,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Menlo',
                        fontSize: 13,
                      ),
                ),
              ),
            ],
          ),
          if (onSignOut != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9F1239),
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Sign out'),
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
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us what broke or felt off. Goes to the mutande team — not into threads.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF78716C),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            enabled: !_sending,
            decoration: const InputDecoration(
              hintText: 'e.g. Connect hosts failed on Claude…',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF991B1B),
                  ),
            ),
          ],
          if (_sent) ...[
            const SizedBox(height: 8),
            Text(
              'Sent — thank you.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF166534),
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
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    var msg = message;
    if (msg.startsWith('DaemonException: ')) {
      msg = msg.substring('DaemonException: '.length);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        msg,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF991B1B),
            ),
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
        _error = e.toString();
        _loading = false;
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
                Text(
                  'Compare safety numbers',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF292524),
                      ),
                ),
                const Spacer(),
                IconButton(
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
                      color: const Color(0xFF78716C),
                    ),
              ),
              SelectableText(
                widget.ours!.fingerprint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      color: const Color(0xFF292524),
                    ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: widget.ours!.uri),
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
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loading ? null : _verify,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1C1917),
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
                      color: _verified!
                          ? const Color(0xFF166534)
                          : const Color(0xFF991B1B),
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
                      color: const Color(0xFF991B1B),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
