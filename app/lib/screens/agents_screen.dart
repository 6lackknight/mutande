import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_flow.dart';
import '../widgets/connect_host_picker.dart';
import '../widgets/host_link_status.dart';
import '../widgets/thinking_orb.dart';

/// Agent slug rules match hub `assertValidAgentSlug` (`[a-z0-9-]{1,32}`).
String? validateAgentSlug(String slug, {Set<String> taken = const {}}) {
  final s = slug.trim().toLowerCase();
  if (s.isEmpty) return 'Enter a slug.';
  if (s.length > 32) return 'Use at most 32 characters.';
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(s)) {
    return 'Use lowercase letters, digits, or hyphens.';
  }
  if (s == 'default' || s == 'all') {
    return '"$s" is reserved.';
  }
  if (taken.contains(s)) {
    return 'That slug is already in use.';
  }
  return null;
}

String agentHostLabel(String slug) {
  switch (slug.trim().toLowerCase()) {
    case 'claude':
      return 'Claude Desktop';
    case 'cursor':
      return 'Cursor';
    case 'chatgpt':
      return 'ChatGPT';
    case '':
      return 'Unknown host';
    default:
      return slug.trim();
  }
}

/// Hub/timeout errors should not read like a dead local daemon.
String friendlyAgentsError(Object error) {
  final base = friendlyDaemonError(error, what: 'Agents');
  if (base.startsWith('Agents took too long')) {
    return 'The hub took too long to respond. Your agents may still be fine — try again.';
  }
  if (base.startsWith("Couldn't load Agents")) {
    return "Couldn't load agents from the hub. Check you're signed in, then retry.";
  }
  if (base.startsWith("Couldn't reach the hub")) {
    return "Couldn't load agents from the hub. Try again in a moment.";
  }
  return base;
}

Duration _agentsMotion(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Handle → primary (default) → sub-agents. Graph (Stitch) + list toggle.
class AgentsPanel extends StatefulWidget {
  AgentsPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.appVersion = '1.0.0',
    this.onViewThreads,
    this.onReloadReady,
    HostLinkStore? hostLinkStore,
  }) : hostLinkStore = hostLinkStore ?? HostLinkStore();

  final DaemonClient daemon;
  final String? handle;
  final String appVersion;
  final VoidCallback? onViewThreads;
  final void Function(VoidCallback? reload)? onReloadReady;
  final HostLinkStore hostLinkStore;

  @override
  State<AgentsPanel> createState() => _AgentsPanelState();
}

class _AgentsPanelState extends State<AgentsPanel> {
  bool _loading = true;
  bool _adding = false;
  String? _error;
  AgentListResult? _list;
  bool _graph = true;
  Map<String, HostLinkRecord> _hostLinks = const {};

  @override
  void initState() {
    super.initState();
    widget.onReloadReady?.call(() => _reload(soft: true));
    _reload();
  }

  @override
  void dispose() {
    widget.onReloadReady?.call(null);
    super.dispose();
  }

  Future<void> _loadHostLinks() async {
    final links = await widget.hostLinkStore.load();
    if (!mounted) return;
    setState(() => _hostLinks = links);
  }

  Future<void> _reload({bool soft = false}) async {
    if (!soft) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.daemon.listAgents();
      final links = await widget.hostLinkStore.load();
      if (!mounted) return;
      setState(() {
        _list = list;
        _hostLinks = links;
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

  Future<void> _setDefault(String agentId) async {
    try {
      await widget.daemon.setDefaultAgent(agentId);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyAgentsError(e))));
    }
  }

  Set<String> _takenSlugs({String? except}) {
    final taken = <String>{};
    for (final a in _list?.agents ?? const <AgentInfo>[]) {
      final s = a.slug.toLowerCase();
      if (except != null && s == except.toLowerCase()) continue;
      taken.add(s);
    }
    return taken;
  }

  Future<void> _renameAgent(AgentInfo agent, String next) async {
    await widget.daemon.renameAgent(agentId: agent.id, slug: next);
    await _reload();
  }

  Future<void> _connectAgentHost(AgentInfo agent) async {
    final host = agent.slug.trim().toLowerCase();
    final result = await showConnectHostFlow(
      context: context,
      daemon: widget.daemon,
      hostLinkStore: widget.hostLinkStore,
      host: host,
    );
    await _loadHostLinks();
    if (!mounted) return;
    final label = agentHostLabel(host);
    if (result == null || !result.mcpOk) {
      throw StateError('Could not link $label.');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.mcpNote?.trim().isNotEmpty == true
              ? 'Linked $label. ${result.mcpNote!.trim()}'
              : 'Linked $label.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _openInspector(AgentInfo agent, {required bool isPrimary}) {
    final handle = widget.handle ?? 'your@handle';
    final host = agentHostLabel(agent.slug);
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x660C0A09),
      builder: (dialogContext) => _AgentInspector(
        handle: handle,
        agent: agent,
        isPrimary: isPrimary,
        link: hostLinkForSlug(agent.slug, _hostLinks),
        takenSlugs: _takenSlugs(except: agent.slug),
        onRename: (slug) => _renameAgent(agent, slug),
        onConnect: () => _connectAgentHost(agent),
        onSetDefault: isPrimary
            ? null
            : () async {
                await widget.daemon.setDefaultAgent(agent.id);
                await _reload();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${agent.slug} is now your default agent'),
                  ),
                );
              },
        onDisconnect: () async {
          // No remove-host RPC yet — confirm + guided outcome.
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'To disconnect $host, remove the mutande MCP server in that app. '
                'Reconnect anytime from Settings → AI hosts.',
              ),
            ),
          );
        },
        onViewThreads: () {
          Navigator.pop(dialogContext);
          final go = widget.onViewThreads;
          if (go != null) {
            go();
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Open Threads to view mail.')),
            );
          }
        },
      ),
    );
  }

  Future<void> _onAdd() async {
    if (_adding) return;
    final taken = {
      for (final a in _list?.agents ?? const <AgentInfo>[])
        a.slug.toLowerCase(),
    };
    final available = AiHostCatalog.hosts
        .where((h) => !taken.contains(h.$1))
        .toList(growable: false);
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All AI hosts are already on this graph.'),
        ),
      );
      return;
    }

    final host = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x660C0A09),
      builder: (context) => ConnectHostPicker(
        title: 'Add AI host',
        subtitle: 'Choose a host to add to your graph.',
        hosts: available,
        hostLinks: _hostLinks,
      ),
    );
    if (host == null || !mounted) return;

    setState(() => _adding = true);
    try {
      final result = await showConnectHostFlow(
        context: context,
        daemon: widget.daemon,
        hostLinkStore: widget.hostLinkStore,
        host: host,
      );
      if (!mounted) return;
      await _loadHostLinks();
      if (result == null || !result.mcpOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect $host.')),
        );
        return;
      }
      await _reload();
      if (!mounted) return;
      final label = AiHostCatalog.hosts.firstWhere((h) => h.$1 == host).$2;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added $label')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add host: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle ?? 'your@handle';
    final agents = _list?.agents ?? const <AgentInfo>[];
    final defaultId = _list?.defaultAgentId;
    AgentInfo? primary;
    final subs = <AgentInfo>[];
    for (final a in agents) {
      if (a.id == defaultId || (primary == null && defaultId == null)) {
        primary ??= a;
      } else {
        subs.add(a);
      }
    }
    // If default id didn't match, first agent is primary.
    if (primary == null && agents.isNotEmpty) {
      primary = agents.first;
      subs
        ..clear()
        ..addAll(agents.skip(1));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _ViewToggle(
            graph: _graph,
            onChanged: (g) => setState(() => _graph = g),
          ),
        ),
        const SizedBox(height: 4),
        if (_loading || _adding)
          const Expanded(
            child: Center(
              child: MutandeOrb.standard(semanticLabel: 'Loading agents…'),
            ),
          )
        else if (_error != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      friendlyAgentsError(_error!),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF78716C),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _reload,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF292524),
                        side: const BorderSide(color: Color(0xFFD6D3D1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: _graph
                ? _AgentsGraph(
                    handle: handle,
                    primary: primary,
                    subs: subs,
                    hostLinks: _hostLinks,
                    onSelect: (a, isPrimary) =>
                        _openInspector(a, isPrimary: isPrimary),
                    onAdd: _onAdd,
                  )
                : _AgentsList(
                    handle: handle,
                    primary: primary,
                    subs: subs,
                    hostLinks: _hostLinks,
                    onSelect: (a, isPrimary) =>
                        _openInspector(a, isPrimary: isPrimary),
                    onAdd: _onAdd,
                    onSetDefault: _setDefault,
                  ),
          ),
        _AgentsFooter(count: agents.length, version: widget.appVersion),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.graph, required this.onChanged});

  final bool graph;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE7E5E4) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected
                  ? const Color(0xFF292524)
                  : const Color(0xFF78716C),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('List', !graph, () => onChanged(false)),
        chip('Graph', graph, () => onChanged(true)),
      ],
    );
  }
}

class _AgentsGraph extends StatelessWidget {
  const _AgentsGraph({
    required this.handle,
    required this.primary,
    required this.subs,
    required this.hostLinks,
    required this.onSelect,
    required this.onAdd,
  });

  final String handle;
  final AgentInfo? primary;
  final List<AgentInfo> subs;
  final Map<String, HostLinkRecord> hostLinks;
  final void Function(AgentInfo agent, bool isPrimary) onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _DotGridPainter(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            children: [
              _HandleNode(handle: handle),
              _Trunk(solid: true),
              if (primary == null)
                _EmptyPrimary(onAdd: onAdd)
              else ...[
                _PrimaryCard(
                  slug: primary!.slug,
                  link: hostLinkForSlug(primary!.slug, hostLinks),
                  onTap: () => onSelect(primary!, true),
                ),
                _Trunk(solid: false),
                _BranchRow(
                  subs: subs,
                  hostLinks: hostLinks,
                  onSelect: (a) => onSelect(a, false),
                  onAdd: onAdd,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE7E5E4);
    const step = 14.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HandleNode extends StatelessWidget {
  const _HandleNode({required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE7E5E4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD6D3D1)),
              ),
              child: const Icon(Icons.person, color: Color(0xFF57534E)),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF166534),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1917),
            borderRadius: BorderRadius.circular(999),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Tooltip(
              message: handle,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFFAFAF9),
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Trunk extends StatelessWidget {
  const _Trunk({required this.solid});

  final bool solid;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: 2,
      child: CustomPaint(
        painter: _LinePainter(color: const Color(0xFF92400E), dashed: !solid),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (!dashed) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      return;
    }
    const dash = 4.0;
    const gap = 3.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashed != dashed;
}

class _PrimaryCard extends StatelessWidget {
  const _PrimaryCard({
    required this.slug,
    required this.link,
    required this.onTap,
  });

  final String slug;
  final HostLinkRecord? link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x330C0A09),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD6D3D1)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  AiHostIcon(slug, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: slug,
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            slug,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: const Color(0xFF292524),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        HostLinkStatusBadge(link: link),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF92400E),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'PRIMARY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.subs,
    required this.hostLinks,
    required this.onSelect,
    required this.onAdd,
  });

  final List<AgentInfo> subs;
  final Map<String, HostLinkRecord> hostLinks;
  final ValueChanged<AgentInfo> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      ...subs.map(
        (a) => _SubCard(
          slug: a.slug,
          link: hostLinkForSlug(a.slug, hostLinks),
          onTap: () => onSelect(a),
        ),
      ),
      _AddNode(onTap: onAdd),
    ];

    return Column(
      children: [
        SizedBox(
          height: 18,
          width: math.max(200.0, children.length * 100.0),
          child: CustomPaint(painter: _BranchPainter(count: children.length)),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: children,
        ),
      ],
    );
  }
}

class _BranchPainter extends CustomPainter {
  _BranchPainter({required this.count});

  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFFA8A29E)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final midY = size.height;
    final cx = size.width / 2;
    // Vertical stub from primary
    _dash(canvas, Offset(cx, 0), Offset(cx, midY * 0.35), paint);
    if (count == 1) {
      _dash(canvas, Offset(cx, midY * 0.35), Offset(cx, midY), paint);
      return;
    }
    final left = size.width * 0.15;
    final right = size.width * 0.85;
    _dash(canvas, Offset(left, midY * 0.35), Offset(right, midY * 0.35), paint);
    for (var i = 0; i < count; i++) {
      final t = count == 1 ? 0.5 : i / (count - 1);
      final x = left + (right - left) * t;
      _dash(canvas, Offset(x, midY * 0.35), Offset(x, midY), paint);
    }
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
    final metrics = path.computeMetrics().first;
    const dash = 4.0;
    const gap = 3.0;
    var dist = 0.0;
    while (dist < metrics.length) {
      final next = math.min(dist + dash, metrics.length);
      canvas.drawPath(metrics.extractPath(dist, next), paint);
      dist = next + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _BranchPainter oldDelegate) =>
      oldDelegate.count != count;
}

class _SubCard extends StatelessWidget {
  const _SubCard({
    required this.slug,
    required this.link,
    required this.onTap,
  });

  final String slug;
  final HostLinkRecord? link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x220C0A09),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 112,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE7E5E4)),
          ),
          child: Column(
            children: [
              AiHostIcon(slug, size: 36),
              const SizedBox(height: 8),
              Tooltip(
                message: slug,
                waitDuration: const Duration(milliseconds: 400),
                child: Text(
                  slug.isEmpty ? '—' : slug,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF292524),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 88,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: HostLinkStatusBadge(link: link),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddNode extends StatelessWidget {
  const _AddNode({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _DashedRectPainter(color: const Color(0xFFA8A29E)),
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Center(child: Icon(Icons.add, color: Color(0xFF78716C))),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(10),
    );
    final path = Path()..addRRect(r);
    for (final metric in path.computeMetrics()) {
      const dash = 5.0;
      const gap = 4.0;
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _EmptyPrimary extends StatelessWidget {
  const _EmptyPrimary({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Add an AI host for your primary agent.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF78716C)),
        ),
        const SizedBox(height: 12),
        _AddNode(onTap: onAdd),
      ],
    );
  }
}

class _AgentsList extends StatelessWidget {
  const _AgentsList({
    required this.handle,
    required this.primary,
    required this.subs,
    required this.hostLinks,
    required this.onSelect,
    required this.onAdd,
    required this.onSetDefault,
  });

  final String handle;
  final AgentInfo? primary;
  final List<AgentInfo> subs;
  final Map<String, HostLinkRecord> hostLinks;
  final void Function(AgentInfo agent, bool isPrimary) onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onSetDefault;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(handle),
          subtitle: const Text('Handle'),
        ),
        if (primary != null)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 28, right: 8),
            leading: AiHostIcon(primary!.slug, size: 32),
            title: Text(primary!.slug),
            subtitle: Text('Primary · receives $handle & @all'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HostLinkStatusBadge(
                  link: hostLinkForSlug(primary!.slug, hostLinks),
                  style: HostLinkStatusStyle.settings,
                ),
                const SizedBox(width: 8),
                const Text(
                  'PRIMARY',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            onTap: () => onSelect(primary!, true),
          ),
        for (final a in subs)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 48, right: 8),
            leading: AiHostIcon(a.slug, size: 32),
            title: Text(a.slug),
            subtitle: Text('$handle/${a.slug}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HostLinkStatusBadge(
                  link: hostLinkForSlug(a.slug, hostLinks),
                  style: HostLinkStatusStyle.settings,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => onSetDefault(a.id),
                  child: const Text('Set as default'),
                ),
              ],
            ),
            onTap: () => onSelect(a, false),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 48, top: 4, right: 8),
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

class _AgentsFooter extends StatelessWidget {
  const _AgentsFooter({required this.count, required this.version});

  final int count;
  final String version;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: const Color(0xFFA8A29E),
      letterSpacing: 0.8,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          const Divider(height: 1, color: Color(0xFFE7E5E4)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('•••  $count AGENTS SYNCED', style: style),
              const Spacer(),
              Text('v$version', style: style),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentInspector extends StatefulWidget {
  const _AgentInspector({
    required this.handle,
    required this.agent,
    required this.isPrimary,
    required this.link,
    required this.takenSlugs,
    required this.onRename,
    required this.onConnect,
    required this.onViewThreads,
    required this.onDisconnect,
    this.onSetDefault,
  });

  final String handle;
  final AgentInfo agent;
  final bool isPrimary;
  final HostLinkRecord? link;
  final Set<String> takenSlugs;
  final Future<void> Function(String slug) onRename;
  final Future<void> Function() onConnect;
  final VoidCallback onViewThreads;
  final Future<void> Function() onDisconnect;
  final Future<void> Function()? onSetDefault;

  @override
  State<_AgentInspector> createState() => _AgentInspectorState();
}

class _AgentInspectorState extends State<_AgentInspector> {
  bool _renaming = false;
  bool _connecting = false;
  bool _disconnecting = false;
  bool _settingDefault = false;
  String? _actionError;
  Future<void> Function()? _retryAction;

  bool get _busy =>
      _renaming || _connecting || _disconnecting || _settingDefault;

  bool get _linked => widget.link != null && widget.link!.ok;

  // Bare handle for default; never show /default. Subs: alice@acme/<slug>.
  String get _display => widget.isPrimary
      ? widget.handle
      : '${widget.handle}/${widget.agent.slug}';

  String get _host => agentHostLabel(widget.agent.slug);

  String get _statusLabel =>
      HostLinkStatusBadge.resolve(widget.link).$1;

  Color get _statusColor =>
      HostLinkStatusBadge.resolve(widget.link).$2;

  Future<void> _onRename() async {
    if (_busy) return;
    final next = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x660C0A09),
      builder: (context) => _RenameSlugDialog(
        initial: widget.agent.slug,
        takenSlugs: widget.takenSlugs,
      ),
    );
    if (next == null || !mounted) return;
    setState(() {
      _renaming = true;
      _actionError = null;
      _retryAction = null;
    });
    try {
      await widget.onRename(next);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _renaming = false;
        _actionError = friendlyAgentsError(e);
        _retryAction = _onRename;
      });
    }
  }

  Future<void> _onConnect() async {
    if (_busy) return;
    setState(() {
      _connecting = true;
      _actionError = null;
      _retryAction = null;
    });
    try {
      await widget.onConnect();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _actionError = e is StateError
            ? e.message
            : friendlyAgentsError(e);
        _retryAction = _onConnect;
      });
    }
  }

  Future<void> _onDisconnect() async {
    if (_busy) return;
    final host = _host;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x660C0A09),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAFAF9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Disconnect host?'),
        content: Text(
          'This stops mutande from using $host as an MCP host on this Mac. '
          'You can reconnect later from Settings → AI hosts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _disconnecting = true;
      _actionError = null;
      _retryAction = null;
    });
    try {
      await widget.onDisconnect();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _disconnecting = false;
        _actionError = friendlyAgentsError(e);
        _retryAction = _onDisconnect;
      });
    }
  }

  Future<void> _onSetDefault() async {
    final action = widget.onSetDefault;
    if (action == null || _busy) return;
    setState(() {
      _settingDefault = true;
      _actionError = null;
      _retryAction = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settingDefault = false;
        _actionError = friendlyAgentsError(e);
        _retryAction = _onSetDefault;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = _agentsMotion(context, const Duration(milliseconds: 180));
    final slug = widget.agent.slug.trim().isEmpty ? '—' : widget.agent.slug;

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: const Color(0xFFFAFAF9),
        elevation: 8,
        shadowColor: const Color(0x330C0A09),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320, maxHeight: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 18),
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Padding(
                        // Optical nudge: tree icon sits slightly high vs SF title.
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.account_tree_outlined,
                          size: 18,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Agent Inspector',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF292524),
                                height: 1.2,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        color: const Color(0xFF78716C),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InspectorField(label: 'Display address', value: _display),
                  _InspectorField(label: 'Agent slug', value: slug),
                  _InspectorField(
                    label: 'Host',
                    value: _host,
                    trailing: AiHostIcon(
                      widget.agent.slug,
                      size: 22,
                      showPlate: false,
                    ),
                  ),
                  _InspectorField(
                    label: 'Status',
                    value: _statusLabel,
                    trailing: AnimatedContainer(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  if (_linked) ...[
                    if ((widget.link?.path ?? '').trim().isNotEmpty)
                      _InspectorField(
                        label: 'Config path',
                        value: widget.link!.path!,
                      ),
                    if ((widget.link?.command ?? '').trim().isNotEmpty)
                      _InspectorField(
                        label: 'MCP command',
                        value: widget.link!.command!,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        (widget.link?.note ?? '').trim().isNotEmpty
                            ? widget.link!.note!.trim()
                            : 'Quit and reopen $_host so it loads the mutande MCP tools.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF78716C),
                              height: 1.35,
                            ),
                      ),
                    ),
                  ],
                  AnimatedSize(
                    duration: motion,
                    curve: Curves.easeOutCubic,
                    child: _actionError == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _InspectorErrorBanner(
                              message: _actionError!,
                              onRetry: _busy
                                  ? null
                                  : () {
                                      final retry = _retryAction;
                                      setState(() {
                                        _actionError = null;
                                        _retryAction = null;
                                      });
                                      retry?.call();
                                    },
                            ),
                          ),
                  ),
                  const SizedBox(height: 2),
                  _InspectorTextAction(
                    icon: Icons.edit_outlined,
                    label: _renaming ? 'Renaming…' : 'Rename slug',
                    onPressed: _busy ? null : _onRename,
                    busy: _renaming,
                  ),
                  if (_linked)
                    _InspectorTextAction(
                      icon: Icons.link,
                      label: _connecting ? 'Reconnecting…' : 'Reconnect host',
                      onPressed: _busy ? null : _onConnect,
                      busy: _connecting,
                    ),
                  if (_linked)
                    _InspectorTextAction(
                      icon: Icons.link_off,
                      label: _disconnecting
                          ? 'Disconnecting…'
                          : 'Disconnect host',
                      onPressed: _busy ? null : _onDisconnect,
                      busy: _disconnecting,
                      destructive: true,
                    ),
                  const SizedBox(height: 14),
                  if (_linked) ...[
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : widget.onViewThreads,
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('View threads'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1917),
                          disabledBackgroundColor: const Color(0xFFD6D3D1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: widget.isPrimary || _busy
                            ? null
                            : _onSetDefault,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF44403C),
                          disabledForegroundColor: const Color(0xFFA8A29E),
                          side: BorderSide(
                            color: widget.isPrimary
                                ? const Color(0xFFE7E5E4)
                                : const Color(0xFFD6D3D1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _settingDefault
                            ? const MutandeOrb.loading(
                                semanticLabel: 'Setting default…',
                              )
                            : Text(
                                widget.isPrimary
                                    ? 'Default'
                                    : 'Set as default',
                              ),
                      ),
                    ),
                  ] else
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _connecting
                            ? () {}
                            : (_busy ? null : _onConnect),
                        icon: _connecting
                            ? const MutandeOrb.loading(
                                semanticLabel: 'Connecting…',
                                dark: true,
                              )
                            : const Icon(Icons.link, size: 16),
                        label: Text(
                          _connecting ? 'Connecting…' : 'Connect host',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1917),
                          disabledBackgroundColor: const Color(0xFFD6D3D1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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

class _RenameSlugDialog extends StatefulWidget {
  const _RenameSlugDialog({required this.initial, required this.takenSlugs});

  final String initial;
  final Set<String> takenSlugs;

  @override
  State<_RenameSlugDialog> createState() => _RenameSlugDialogState();
}

class _RenameSlugDialogState extends State<_RenameSlugDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateLive(String _) {
    final next = _controller.text.trim().toLowerCase();
    setState(() {
      if (next == widget.initial.toLowerCase()) {
        _error = null;
      } else {
        _error = validateAgentSlug(next, taken: widget.takenSlugs);
      }
    });
  }

  void _submit() {
    if (_saving) return;
    final next = _controller.text.trim().toLowerCase();
    if (next == widget.initial.toLowerCase()) {
      Navigator.pop(context);
      return;
    }
    final err = validateAgentSlug(next, taken: widget.takenSlugs);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _saving = true);
    Navigator.pop(context, next);
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        !_saving &&
        _controller.text.trim().isNotEmpty &&
        (_error == null ||
            _controller.text.trim().toLowerCase() ==
                widget.initial.toLowerCase());

    return AlertDialog(
      backgroundColor: const Color(0xFFFAFAF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Rename slug'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lowercase letters, digits, or hyphens · 1–32 characters. '
            'Reserved: default, all.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF78716C),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            onChanged: _validateLive,
            onSubmitted: (_) => _submit(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
              LengthLimitingTextInputFormatter(32),
            ],
            decoration: InputDecoration(
              hintText: 'claude',
              errorText: _error,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1C1917),
            disabledBackgroundColor: const Color(0xFFD6D3D1),
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const MutandeOrb.loading(
                  semanticLabel: 'Saving…',
                  dark: true,
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _InspectorTextAction extends StatelessWidget {
  const _InspectorTextAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFB91C1C)
        : const Color(0xFF44403C);
    final disabled = onPressed == null;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: busy
            ? MutandeOrb.loading(
                semanticLabel: '$label…',
                dark: Theme.of(context).brightness == Brightness.dark,
              )
            : Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: color.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          minimumSize: const Size(44, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

class _InspectorErrorBanner extends StatelessWidget {
  const _InspectorErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF991B1B),
                height: 1.35,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF991B1B),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _InspectorField extends StatelessWidget {
  const _InspectorField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF292524),
      fontFamily: 'Menlo',
      fontSize: 13,
      height: 1.3,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFFA8A29E),
              letterSpacing: 0.8,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: value,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}
