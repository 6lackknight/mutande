import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_flow.dart';
import '../widgets/connect_host_picker.dart';
import '../widgets/host_link_status.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/transport_chip.dart';

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

enum _NetworkZoom { me, org, external }

class _AgentsPanelState extends State<AgentsPanel> {
  bool _loading = true;
  bool _adding = false;
  String? _error;
  AgentListResult? _list;
  _NetworkZoom _zoom = _NetworkZoom.me;
  String? _selectedAgentId;
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

  /// Slugs blocked for rename/add. Same display slug may exist twice when
  /// transports differ (sidecar + web); only same-transport collisions count.
  Set<String> _takenSlugs({AgentInfo? forAgent}) {
    final agents = _list?.agents ?? const <AgentInfo>[];
    if (forAgent == null) {
      return {for (final a in agents) a.slug.toLowerCase()};
    }
    final taken = <String>{};
    for (final a in agents) {
      if (a.id == forAgent.id) continue;
      final sameTransportConflict = forAgent.transport == null ||
          a.transport == null ||
          a.transport == forAgent.transport;
      if (sameTransportConflict) {
        taken.add(a.slug.toLowerCase());
      }
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
        takenSlugs: _takenSlugs(forAgent: agent),
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
                    content: Text(
                      '${agent.slug.toLowerCase()} is now your default agent',
                    ),
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
          alignment: Alignment.centerLeft,
          child: _ZoomToggle(
            zoom: _zoom,
            onChanged: (z) => setState(() => _zoom = z),
          ),
        ),
        const SizedBox(height: 4),
        if (_loading || _adding)
          const Expanded(
            child: Center(
              child: MutandeOrb.standard(semanticLabel: 'Loading network…'),
            ),
          )
        else if (_error != null)
          Expanded(
            child: PaneQuietState(
              title: "Couldn't load network",
              body: friendlyAgentsError(_error!),
              onRetry: _reload,
              icon: Icons.cloud_off_outlined,
            ),
          )
        else
          Expanded(
            child: switch (_zoom) {
              _NetworkZoom.me => _AgentsGraph(
                  handle: handle,
                  primary: primary,
                  subs: subs,
                  selectedId: _selectedAgentId ?? primary?.id,
                  onSelect: (a, isPrimary) {
                    setState(() => _selectedAgentId = a.id);
                    _openInspector(a, isPrimary: isPrimary);
                  },
                  onAdd: _onAdd,
                ),
              _NetworkZoom.org => _ZoomPlaceholder(
                  title: 'Org',
                  body:
                      'Teammates as ink discs on one orbit — peer agent trees open on select. Coming next.',
                  hubLabel: _orgSlug(handle),
                ),
              _NetworkZoom.external => const _ZoomPlaceholder(
                  title: 'External',
                  body:
                      'Cross-org peers farther out. Trust and pairing stay in the inspector.',
                  hubLabel: 'you',
                ),
            },
          ),
        _AgentsFooter(count: agents.length, version: widget.appVersion),
      ],
    );
  }

  static String _orgSlug(String handle) {
    final at = handle.lastIndexOf('@');
    if (at < 0 || at >= handle.length - 1) return handle;
    return handle.substring(at + 1).toLowerCase();
  }
}

class _ZoomToggle extends StatelessWidget {
  const _ZoomToggle({required this.zoom, required this.onChanged});

  final _NetworkZoom zoom;
  final ValueChanged<_NetworkZoom> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _NetworkZoom value) {
      final selected = zoom == value;
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip('Me', _NetworkZoom.me),
            chip('Org', _NetworkZoom.org),
            chip('External', _NetworkZoom.external),
          ],
        ),
      ),
    );
  }
}

class _ZoomPlaceholder extends StatelessWidget {
  const _ZoomPlaceholder({
    required this.title,
    required this.body,
    required this.hubLabel,
  });

  final String title;
  final String body;
  final String hubLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFFF5F5F4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF292524),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  hubLabel == 'you' ? 'you' : hubLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFAFAF9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF292524),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 280,
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF78716C),
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

/// Calm concentric map: you at center, agents on one orbit (Penpot Network — Me).
class _AgentsGraph extends StatelessWidget {
  const _AgentsGraph({
    required this.handle,
    required this.primary,
    required this.subs,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  final String handle;
  final AgentInfo? primary;
  final List<AgentInfo> subs;
  final String? selectedId;
  final void Function(AgentInfo agent, bool isPrimary) onSelect;
  final VoidCallback onAdd;

  List<AgentInfo> get _orbitAgents => [
        ?primary,
        ...subs,
      ];

  @override
  Widget build(BuildContext context) {
    final agents = _orbitAgents;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFFF5F5F4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final center = Offset(size.width * 0.48, size.height * 0.48);
            final orbitR = (math.min(size.width, size.height) * 0.28)
                .clamp(100.0, 160.0);
            final n = math.max(agents.length, 1);
            final selectedIndex = selectedId == null
                ? -1
                : agents.indexWhere((a) => a.id == selectedId);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: size,
                  painter: _ConcentricOrbitPainter(
                    center: center,
                    orbitR: orbitR,
                    agentCount: agents.length,
                    emphasizeIndex: selectedIndex >= 0
                        ? selectedIndex
                        : (primary == null
                            ? -1
                            : agents.indexWhere((a) => a.id == primary!.id)),
                  ),
                ),
                Positioned(
                  left: center.dx - 44,
                  top: center.dy - 44,
                  width: 88,
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF292524),
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          'you',
                          style: TextStyle(
                            color: Color(0xFFFAFAF9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatMailAddress(handle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF78716C),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < agents.length; i++)
                  _orbitNode(
                    agent: agents[i],
                    index: i,
                    count: n,
                    center: center,
                    orbitR: orbitR,
                    isPrimary: primary != null && agents[i].id == primary!.id,
                    selected: agents[i].id == selectedId ||
                        (selectedId == null &&
                            primary != null &&
                            agents[i].id == primary!.id),
                  ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF57534E),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _orbitNode({
    required AgentInfo agent,
    required int index,
    required int count,
    required Offset center,
    required double orbitR,
    required bool isPrimary,
    required bool selected,
  }) {
    final ang = -math.pi / 2 + (2 * math.pi * index / count);
    final ax = center.dx + math.cos(ang) * orbitR;
    final ay = center.dy + math.sin(ang) * orbitR;
    final nodeSize = selected ? 36.0 : 28.0;
    final slug = agent.slug.trim().toLowerCase();
    return Positioned(
      left: ax - 40,
      top: ay - nodeSize / 2,
      width: 80,
      child: GestureDetector(
        onTap: () => onSelect(agent, isPrimary),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: nodeSize,
              height: nodeSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAF9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF292524)
                      : const Color(0xFFA8A29E),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF166534).withValues(alpha: 0.22),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: AiHostIcon(
                slug,
                size: selected ? 16 : 13,
                showPlate: false,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              slug,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: const Color(0xFF57534E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConcentricOrbitPainter extends CustomPainter {
  _ConcentricOrbitPainter({
    required this.center,
    required this.orbitR,
    required this.agentCount,
    required this.emphasizeIndex,
  });

  final Offset center;
  final double orbitR;
  final int agentCount;
  final int emphasizeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = const Color(0xFFE7E5E4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, orbitR, guide);
    canvas.drawCircle(
      center,
      orbitR + 70,
      Paint()
        ..color = const Color(0x66E7E5E4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (agentCount == 0) return;
    final n = agentCount;
    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + (2 * math.pi * i / n);
      final end = Offset(
        center.dx + math.cos(ang) * orbitR,
        center.dy + math.sin(ang) * orbitR,
      );
      final emphasized = i == emphasizeIndex;
      final spoke = Paint()
        ..color = emphasized
            ? const Color(0xBFA8A29E)
            : const Color(0x80A8A29E)
        ..strokeWidth = emphasized ? 1.5 : 1.15
        ..style = PaintingStyle.stroke;
      final ux = (end.dx - center.dx) / orbitR;
      final uy = (end.dy - center.dy) / orbitR;
      final start = Offset(center.dx + ux * 44, center.dy + uy * 44);
      final tip = Offset(end.dx - ux * 14, end.dy - uy * 14);
      canvas.drawLine(start, tip, spoke);
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricOrbitPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.orbitR != orbitR ||
        oldDelegate.agentCount != agentCount ||
        oldDelegate.emphasizeIndex != emphasizeIndex;
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
              Text('•••  $count ON NETWORK', style: style),
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
  String get _display => formatMailAddress(
        widget.isPrimary
            ? widget.handle
            : '${widget.handle}/${widget.agent.slug}',
      );

  String get _host => agentHostLabel(widget.agent.slug);

  String get _statusLabel =>
      HostLinkStatusBadge.resolve(widget.link).$1;

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
    final slug = widget.agent.slug.trim().isEmpty
        ? '—'
        : widget.agent.slug.trim().toLowerCase();

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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isPrimary ? '$slug · primary' : slug,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF292524),
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _linked
                                  ? '$_statusLabel · ${_host.toLowerCase()}'
                                  : _statusLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _linked
                                        ? const Color(0xFF166534)
                                        : const Color(0xFF78716C),
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
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
                  const SizedBox(height: 14),
                  _InspectorField(label: 'Address', value: _display),
                  if (widget.agent.transport != null)
                    _InspectorField(
                      label: 'Transport',
                      value: widget.agent.transport!.chipLabel,
                      trailing: TransportChip(
                        transport: widget.agent.transport!,
                        compact: true,
                        active: widget.agent.capabilityFresh,
                        lastSeen: widget.agent.lastSeen,
                      ),
                    ),
                  const _InspectorField(
                    label: 'Trust',
                    value: 'org · E2E',
                  ),
                  if (_linked) ...[
                    if ((widget.link?.path ?? '').trim().isNotEmpty)
                      _InspectorField(
                        label: 'Config path',
                        value: widget.link!.path!,
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
