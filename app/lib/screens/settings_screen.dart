import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/thinking_orb.dart';

/// Plumbing + trust — pushed from the home gear (Stitch Settings hub).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.daemon,
    required this.checking,
    required this.connecting,
    required this.health,
    this.connectResult,
    this.connectError,
    required this.onCheckDaemon,
    required this.onConnectHosts,
    this.handle,
  });

  final DaemonClient daemon;
  final bool checking;
  final bool connecting;
  final DaemonHealthResult? health;
  final ConnectHostResult? connectResult;
  final String? connectError;
  final VoidCallback onCheckDaemon;
  final VoidCallback onConnectHosts;
  final String? handle;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _checking = widget.checking;
  late bool _connecting = widget.connecting;
  late DaemonHealthResult? _health = widget.health;
  late ConnectHostResult? _connectResult = widget.connectResult;
  late String? _connectError = widget.connectError;
  DateTime? _lastPingAt;
  SafetyNumberResult? _ours;
  bool _loadingSafety = true;

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

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      final result = await widget.daemon.connectHost('all');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectResult = result;
      });
      widget.onConnectHosts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = e.toString();
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
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: connected ? _green : const Color(0xFFB45309),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  connected ? 'CONNECTED' : 'OFFLINE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: connected ? _green : const Color(0xFFB45309),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
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
            onCheck: _check,
            onRetry: _check,
          ),
          const SizedBox(height: 28),
          _sectionHeader(
            context,
            'AI HOSTS',
            trailing: TextButton(
              onPressed: _connecting ? null : _connect,
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
          _HostsCard(result: _connectResult),
          if (_connectError != null) ...[
            const SizedBox(height: 10),
            _ErrorBanner(message: _connectError!),
          ],
          if (_connectResult != null) ...[
            const SizedBox(height: 10),
            _ConnectDetails(result: _connectResult!),
          ],
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
          _AccountCard(handle: widget.handle),
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
    required this.onCheck,
    required this.onRetry,
  });

  final DaemonHealthResult? health;
  final bool checking;
  final DateTime? lastPingAt;
  final VoidCallback onCheck;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final service = health?.service ?? 'mutande-core';
    final version = health?.version;
    final title = version != null && version.isNotEmpty
        ? '$service-v$version'
        : service;
    final ping = lastPingAt == null
        ? 'Last ping: —'
        : 'Last ping: ${_relativePing(lastPingAt!)}';

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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.terminal,
                  size: 20,
                  color: Color(0xFF57534E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF292524),
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      checking ? 'Checking…' : ping,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF78716C),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
  const _HostsCard({this.result});

  final ConnectHostResult? result;

  static const _hosts = [
    ('cursor', 'Cursor'),
    ('claude', 'Claude (Anthropic)'),
    ('chatgpt', 'ChatGPT'),
  ];

  @override
  Widget build(BuildContext context) {
    final byHost = <String, HostWriteResult>{
      for (final h in result?.hosts ?? const <HostWriteResult>[])
        h.host.toLowerCase(): h,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _hosts.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: Color(0xFFE7E5E4)),
            _HostRow(
              host: _hosts[i].$1,
              label: _hosts[i].$2,
              write: byHost[_hosts[i].$1],
              hasResult: result != null,
            ),
          ],
        ],
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({
    required this.host,
    required this.label,
    required this.write,
    required this.hasResult,
  });

  final String host;
  final String label;
  final HostWriteResult? write;
  final bool hasResult;

  @override
  Widget build(BuildContext context) {
    final status = _status();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AiHostIcon(host, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          status,
        ],
      ),
    );
  }

  Widget _status() {
    if (!hasResult || write == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Idle',
          style: TextStyle(
            color: Color(0xFF78716C),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (write!.ok) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Connected',
            style: TextStyle(
              color: Color(0xFF166534),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return const Text(
      'Failed',
      style: TextStyle(
        color: Color(0xFF991B1B),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ConnectDetails extends StatefulWidget {
  const _ConnectDetails({required this.result});

  final ConnectHostResult result;

  @override
  State<_ConnectDetails> createState() => _ConnectDetailsState();
}

class _ConnectDetailsState extends State<_ConnectDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hosts = widget.result.hosts;
    final okCount = hosts.where((h) => h.ok).length;
    final summary = hosts.isEmpty
        ? 'No hosts updated'
        : okCount == hosts.length
            ? 'Connected $okCount AI host${okCount == 1 ? '' : 's'}'
            : 'Connected $okCount of ${hosts.length} AI hosts';

    return Material(
      color: const Color(0xFFECFDF5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFA7F3D0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              summary,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Text(
                      _open ? 'Hide details' : 'Details',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF78716C),
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const Spacer(),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: const Color(0xFFA8A29E),
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              for (final h in hosts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      '${_hostName(h.host)}\n${_tildePath(h.path)}'
                      '${_softNote(h) != null ? '\n${_softNote(h)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF78716C),
                            height: 1.35,
                          ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _hostName(String host) {
    switch (host.toLowerCase()) {
      case 'cursor':
        return 'Cursor';
      case 'claude':
        return 'Claude Desktop';
      case 'chatgpt':
        return 'ChatGPT';
      default:
        return host;
    }
  }

  static String? _softNote(HostWriteResult host) {
    final note = host.note?.trim();
    if (note == null || note.isEmpty) return null;
    final lower = note.toLowerCase();
    if (lower.contains('chatgpt') || lower.contains('unconfirmed')) {
      return 'Config written — if ChatGPT doesn’t pick it up, open Settings → MCP.';
    }
    return note.length > 120 ? '${note.substring(0, 117)}…' : note;
  }

  static String _tildePath(String path) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
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
  const _AccountCard({this.handle});

  final String? handle;

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
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Menlo',
                        fontSize: 13,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Standard Professional License',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF78716C),
                      ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sign out isn’t available in this build yet.'),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF78716C),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text(
              'Sign out',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                        MutandeOrb.loading(semanticLabel: 'Checking…'),
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
