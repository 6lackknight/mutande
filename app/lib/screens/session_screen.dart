import 'package:flutter/material.dart';

import '../platform/user_home.dart';
import '../services/daemon_client.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/thinking_orb.dart';

/// Session tab: daemon health + Connect AI hosts with quiet success UI.
class SessionPanel extends StatefulWidget {
  const SessionPanel({
    super.key,
    required this.daemon,
    required this.checking,
    required this.connecting,
    this.health,
    this.connectResult,
    this.connectError,
    required this.onCheckDaemon,
    required this.onConnectHosts,
  });

  final DaemonClient daemon;
  final bool checking;
  final bool connecting;
  final DaemonHealthResult? health;
  final ConnectHostResult? connectResult;
  final String? connectError;
  final VoidCallback onCheckDaemon;
  final VoidCallback onConnectHosts;

  @override
  State<SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends State<SessionPanel> {
  bool _loadingAgents = true;
  String? _agentsError;
  AgentListResult? _agents;
  bool _savingDefault = false;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    setState(() {
      _loadingAgents = true;
      _agentsError = null;
    });
    try {
      final list = await widget.daemon.listAgents();
      if (!mounted) return;
      setState(() {
        _agents = list;
        _loadingAgents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _agentsError = e.toString();
        _loadingAgents = false;
      });
    }
  }

  Future<void> _pickDefault(String agentId) async {
    if (_agents?.defaultAgentId == agentId) return;
    setState(() => _savingDefault = true);
    try {
      await widget.daemon.setDefaultAgent(agentId);
      await _loadAgents();
    } catch (e) {
      if (!mounted) return;
      setState(() => _agentsError = e.toString());
    } finally {
      if (mounted) setState(() => _savingDefault = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Session',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF292524),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Keep the courier running and link your AI hosts.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF78716C),
              ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Default agent',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF57534E),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bare handle mail and @all fan-in route here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF78716C),
                      ),
                ),
                const SizedBox(height: 12),
                if (_loadingAgents)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: MutandeOrb.loading(semanticLabel: 'Loading agents…'),
                    ),
                  )
                else if (_agentsError != null)
                  Text(
                    _friendlyError(_agentsError!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF991B1B),
                        ),
                  )
                else if (_agents == null || _agents!.agents.isEmpty)
                  Text(
                    'No agents yet — connect an AI host to register one.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF78716C),
                        ),
                  )
                else
                  ..._agents!.agents.map((agent) {
                    final isDefault = agent.id == _agents!.defaultAgentId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: _savingDefault ? null : () => _pickDefault(agent.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDefault
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 18,
                                color: isDefault
                                    ? const Color(0xFF166534)
                                    : const Color(0xFFA8A29E),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  agent.slug,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF292524),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'default',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: const Color(0xFF166534),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: widget.checking ? null : widget.onCheckDaemon,
                  icon: widget.checking
                      ? const MutandeOrb.loading(
                          semanticLabel: 'Checking…',
                          dark: true,
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(widget.checking ? 'Checking…' : 'Check daemon'),
                ),
                if (widget.health != null) ...[
                  const SizedBox(height: 12),
                  _DaemonStatusRow(health: widget.health!),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.connecting ? null : widget.onConnectHosts,
                  icon: widget.connecting
                      ? const MutandeOrb.loading(semanticLabel: 'Connecting…')
                      : const Icon(Icons.link, size: 18),
                  label: Text(
                    widget.connecting ? 'Connecting…' : 'Connect AI hosts',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.connectError != null) ...[
          const SizedBox(height: 14),
          _ConnectErrorCard(message: widget.connectError!),
        ],
        if (widget.connectResult != null) ...[
          const SizedBox(height: 14),
          _ConnectSuccessCard(result: widget.connectResult!),
        ],
      ],
    );
  }
}

class _DaemonStatusRow extends StatelessWidget {
  const _DaemonStatusRow({required this.health});

  final DaemonHealthResult health;

  @override
  Widget build(BuildContext context) {
    final ok = health.connected;
    final color = ok ? const Color(0xFF166534) : const Color(0xFF991B1B);
    final bg = ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    final title = ok ? 'Daemon is running' : 'Daemon unreachable';
    final detail = ok
        ? [
            if (health.service != null) health.service!,
            if (health.version != null) 'v${health.version}',
          ].join(' · ')
        : (health.error ?? 'Could not reach mutande-core.');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color.withValues(alpha: 0.75),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectErrorCard extends StatelessWidget {
  const _ConnectErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFEF2F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFECACA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFF991B1B)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _friendlyError(message),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF991B1B),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectSuccessCard extends StatefulWidget {
  const _ConnectSuccessCard({required this.result});

  final ConnectHostResult result;

  @override
  State<_ConnectSuccessCard> createState() => _ConnectSuccessCardState();
}

class _ConnectSuccessCardState extends State<_ConnectSuccessCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _appear;
  bool _detailsOpen = false;
  /// Bumps [ExpansionTile] key so Details collapses on a new connect result.
  int _detailsEpoch = 0;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _ConnectSuccessCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) {
      _appear.forward(from: 0);
      _detailsOpen = false;
      _detailsEpoch++;
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = widget.result.hosts;
    final okCount = hosts.where((h) => h.ok).length;
    final allOk = okCount == hosts.length && hosts.isNotEmpty;
    final summary = hosts.isEmpty
        ? 'No hosts updated'
        : allOk
            ? 'Connected $okCount AI host${okCount == 1 ? '' : 's'}'
            : 'Connected $okCount of ${hosts.length} AI hosts';
    final accent = allOk ? const Color(0xFF166534) : const Color(0xFFB45309);
    final border = allOk ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final card = Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  allOk ? Icons.check_circle : Icons.info_outline,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF292524),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < hosts.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _HostStatusRow(host: hosts[i], index: i),
            ],
            const SizedBox(height: 4),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey('connect-details-$_detailsEpoch'),
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                onExpansionChanged: (open) => setState(() => _detailsOpen = open),
                title: Text(
                  _detailsOpen ? 'Hide details' : 'Details',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF78716C),
                        fontWeight: FontWeight.w500,
                      ),
                ),
                trailing: Icon(
                  _detailsOpen
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 20,
                  color: const Color(0xFFA8A29E),
                ),
                children: [
                  for (final h in hosts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          '${_hostDisplayName(h.host)}\n${_tildePath(h.path)}',
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
          ],
        ),
      ),
    );

    if (reduceMotion) return card;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic)),
        child: card,
      ),
    );
  }
}

class _HostStatusRow extends StatelessWidget {
  const _HostStatusRow({required this.host, required this.index});

  final HostWriteResult host;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name = _hostDisplayName(host.host);
    final helper = _softHelperNote(host);
    final ok = host.ok;
    final chipColor = ok ? const Color(0xFF166534) : const Color(0xFF991B1B);
    final chipBg = ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    final chipLabel = ok ? 'Connected' : 'Failed';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final reduce = MediaQuery.disableAnimationsOf(context);
        final opacity = reduce ? 1.0 : t;
        return Opacity(
          opacity: opacity,
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AiHostIcon(host.host, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ok ? Icons.check : Icons.close,
                      size: 12,
                      color: chipColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chipLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: chipColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                helper,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFA8A29E),
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _hostDisplayName(String host) {
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

/// Soften daemon notes (esp. ChatGPT path uncertainty) into calm helper copy.
String? _softHelperNote(HostWriteResult host) {
  if (!host.ok) {
    final note = host.note?.trim();
    if (note == null || note.isEmpty) return 'Could not write this host config.';
    // Keep failure reason but strip absolute noise when possible.
    if (note.length > 120) return '${note.substring(0, 117)}…';
    return note;
  }
  final note = host.note?.trim();
  if (note == null || note.isEmpty) return null;
  final lower = note.toLowerCase();
  if (lower.contains('chatgpt') || lower.contains('unconfirmed')) {
    return 'Config written — if ChatGPT doesn’t pick it up, open Settings → MCP.';
  }
  if (note.length > 120) return '${note.substring(0, 117)}…';
  return note;
}

String _tildePath(String path) {
  final home = userHomeDir();
  if (home != null && home.isNotEmpty && path.startsWith(home)) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

String _friendlyError(String raw) {
  var msg = raw;
  if (msg.startsWith('DaemonException: ')) {
    msg = msg.substring('DaemonException: '.length);
  }
  if (msg.startsWith('Exception: ')) {
    msg = msg.substring('Exception: '.length);
  }
  return msg;
}
