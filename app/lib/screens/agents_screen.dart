import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../services/host_link_store.dart';
import '../util/address_display.dart';
import '../util/thread_peer.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/peer_popover.dart';
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

/// Ease-out cubic unit interval — hub / ring / node entrance.
double _easeUnit(double t, double begin, double end) {
  if (end <= begin) return t >= end ? 1.0 : 0.0;
  final u = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(u);
}

/// Handle → primary (default) → sub-agents. Graph (Stitch) + list toggle.
class AgentsPanel extends StatefulWidget {
  AgentsPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.appVersion = '1.0.0',
    this.onViewThreads,
    this.onStartThread,
    this.onReloadReady,
    HostLinkStore? hostLinkStore,
  }) : hostLinkStore = hostLinkStore ?? HostLinkStore();

  final DaemonClient daemon;
  final String? handle;
  final String appVersion;
  final VoidCallback? onViewThreads;
  final ValueChanged<String>? onStartThread;
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
  List<ContactView> _orgContacts = const [];
  List<ContactView> _externalContacts = const [];
  Map<String, List<String>> _peerAgents = const {};
  String? _directoryError;
  _NetworkZoom _zoom = _NetworkZoom.me;
  String? _selectedAgentId;
  String? _selectedPeerId;
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
      var org = const <ContactView>[];
      var external = const <ContactView>[];
      String? directoryError;
      try {
        org = await widget.daemon.listContacts();
      } catch (e) {
        directoryError = e.toString();
      }
      try {
        external = await widget.daemon.listExternalContacts();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _list = list;
        _hostLinks = links;
        _orgContacts = org;
        _externalContacts = external;
        _directoryError = directoryError;
        _loading = false;
      });
      unawaited(_hydratePeerAgents(own: list, org: org));
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
            onChanged: (z) => setState(() {
              _zoom = z;
              _selectedPeerId = null;
            }),
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
              _NetworkZoom.org => _directoryError != null &&
                      _orgPeople().length <= 1
                  ? PaneQuietState(
                      title: "Couldn't load org",
                      body: friendlyAgentsError(_directoryError!),
                      onRetry: _reload,
                      icon: Icons.cloud_off_outlined,
                    )
                  : _orgGraph(handle),
              _NetworkZoom.external => _peopleGraph(
                  hubLabel: 'you',
                  hubCaption: formatMailAddress(handle),
                  people: _externalOrgPeople(),
                  onSelect: _onSelectExternalOrg,
                ),
            },
          ),
        _AgentsFooter(count: _footerCount(agents.length), version: widget.appVersion),
      ],
    );
  }

  static String _orgSlug(String handle) {
    final at = handle.lastIndexOf('@');
    if (at < 0 || at >= handle.length - 1) return handle;
    return handle.substring(at + 1).toLowerCase();
  }

  static String _localPart(String handle) {
    final h = bareMailHandle(handle);
    final at = h.indexOf('@');
    if (at <= 0) return h;
    return h.substring(0, at);
  }

  int _footerCount(int agentCount) {
    return switch (_zoom) {
      _NetworkZoom.me => agentCount,
      _NetworkZoom.org => _orgPeople().length,
      _NetworkZoom.external => _externalOrgPeople().length,
    };
  }

  List<_OrbitPerson> _orgPeople() {
    final mine = widget.handle?.trim();
    final myBare = mine == null || mine.isEmpty ? '' : bareMailHandle(mine);
    final people = <_OrbitPerson>[
      if (myBare.isNotEmpty)
        _OrbitPerson(
          id: myBare,
          label: 'you',
          caption: formatMailAddress(mine!),
          isSelf: true,
          agentSlugs: _slugsFor(myBare),
        ),
      for (final c in _orgContacts)
        if (!c.isBroadcast &&
            c.handle.trim().isNotEmpty &&
            bareMailHandle(c.handle) != myBare)
          _OrbitPerson(
            id: bareMailHandle(c.handle),
            label: _localPart(c.handle),
            caption: formatMailAddress(c.handle),
            avatarUrl: c.avatarUrl,
            agentSlugs: _slugsFor(c.handle),
          ),
    ];
    return people;
  }

  List<String> _slugsFor(String handle) =>
      _peerAgents[bareMailHandle(handle)] ?? const [];

  Future<void> _hydratePeerAgents({
    required AgentListResult own,
    required List<ContactView> org,
  }) async {
    final mine = widget.handle?.trim();
    final out = <String, List<String>>{
      if (mine != null && mine.isNotEmpty)
        bareMailHandle(mine): _uniqueAgentSlugs(own.agents),
    };
    final peers = org
        .where((c) => !c.isBroadcast && c.handle.trim().isNotEmpty)
        .take(12)
        .toList();
    await Future.wait([
      for (final c in peers)
        () async {
          try {
            final list = await widget.daemon.listAgents(handle: c.handle);
            out[bareMailHandle(c.handle)] = _uniqueAgentSlugs(list.agents);
          } catch (_) {}
        }(),
    ]);
    if (!mounted) return;
    setState(() => _peerAgents = out);
  }

  static List<String> _uniqueAgentSlugs(Iterable<AgentInfo> agents) {
    final seen = <String>{};
    final out = <String>[];
    for (final a in agents) {
      final s = a.slug.trim().toLowerCase();
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }

  List<_OrbitPerson> _externalOrgPeople() {
    final byOrg = <String, List<ContactView>>{};
    for (final c in _externalContacts) {
      final handle = c.handle.trim();
      if (handle.isEmpty) continue;
      final org = _orgSlug(handle);
      if (org.isEmpty) continue;
      byOrg.putIfAbsent(org, () => []).add(c);
    }
    final orgs = byOrg.keys.toList()..sort();
    return [
      for (final org in orgs)
        _OrbitPerson(
          id: org,
          label: org,
          caption: byOrg[org]!.length == 1
              ? formatMailAddress(byOrg[org]!.first.handle)
              : '${byOrg[org]!.length} people',
          members: byOrg[org]!,
        ),
    ];
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $address'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _orgGraph(String handle) {
    return _peopleGraph(
      hubLabel: _orgSlug(handle),
      hubCaption: '@all@${_orgSlug(handle)}',
      people: _orgPeople(),
      onHubTap: () => _copyAddress('@all@${_orgSlug(handle)}'),
      onSelect: _onSelectOrgPerson,
    );
  }

  Widget _peopleGraph({
    required String hubLabel,
    required String? hubCaption,
    required List<_OrbitPerson> people,
    required ValueChanged<_OrbitPerson> onSelect,
    VoidCallback? onHubTap,
  }) {
    final graph = _PeopleOrbitGraph(
      hubLabel: hubLabel,
      hubCaption: hubCaption,
      people: people,
      selectedId: _selectedPeerId,
      onHubTap: onHubTap,
      onSelect: onSelect,
    );
    final data = [for (final p in people) _inspectData(p)];
    return PeerPopoverLayer(
      graph: graph,
      people: data,
      selectedId: _selectedPeerId,
      onDismiss: () => setState(() => _selectedPeerId = null),
      onCopy: _copyQuiet,
      onMessage: (h) => widget.onStartThread?.call(h),
    );
  }

  ContactView? _contactFor(_OrbitPerson p) {
    if (p.members != null && p.members!.isNotEmpty) return p.members!.first;
    final id = bareMailHandle(p.id);
    for (final c in [..._orgContacts, ..._externalContacts]) {
      if (bareMailHandle(c.handle) == id) return c;
    }
    return null;
  }

  PeerInspectData _inspectData(_OrbitPerson p) {
    final handles = p.members == null || p.members!.isEmpty
        ? [
            if ((p.caption ?? p.id).trim().isNotEmpty) p.caption ?? p.id,
          ]
        : [
            for (final m in p.members!)
              if (m.handle.trim().isNotEmpty) formatMailAddress(m.handle),
          ];
    final hit = _contactFor(p);
    final members = p.members ?? [if (hit != null) hit];
    final platforms = <String>{
      for (final c in members)
        for (final d in c.devices)
          if ((d.platform ?? '').trim().isNotEmpty) d.platform!.trim().toLowerCase(),
    };
    final deviceCount = members.fold<int>(0, (n, c) => n + c.devices.length);
    final hasPubkey = members.any(
      (c) =>
          (c.pubkey ?? '').trim().isNotEmpty ||
          c.devices.any((d) => d.pubkey.trim().isNotEmpty),
    );
    String? orgSlug;
    if (p.members != null && p.members!.isNotEmpty) {
      orgSlug = p.id.toLowerCase();
    } else {
      final h = handles.isNotEmpty ? handles.first : p.id;
      final at = h.lastIndexOf('@');
      if (at >= 0 && at < h.length - 1) orgSlug = h.substring(at + 1).toLowerCase();
    }
    final kindLabel = p.isSelf
        ? 'you'
        : (p.members != null && p.members!.length > 1)
            ? 'org'
            : members.any((c) => c.isExternal)
                ? 'external'
                : 'teammate';
    String? linkedAt;
    for (final c in members) {
      final at = c.linkedAt?.trim();
      if (at != null && at.isNotEmpty) {
        linkedAt = at;
        break;
      }
    }
    return PeerInspectData(
      id: p.id,
      label: p.label,
      handle: handles.isNotEmpty ? handles.first : p.id,
      handles: handles,
      avatarUrl: p.avatarUrl,
      agentSlugs: p.agentSlugs,
      orgSlug: orgSlug,
      kindLabel: kindLabel,
      deviceCount: deviceCount,
      hasPubkey: hasPubkey,
      linkedAt: linkedAt,
      hasThread: members.any((c) => (c.threadId ?? '').trim().isNotEmpty),
      platforms: platforms.toList(),
    );
  }

  void _copyQuiet(String address) {
    Clipboard.setData(ClipboardData(text: address));
  }

  void _onSelectOrgPerson(_OrbitPerson person) {
    if (person.isSelf) {
      setState(() {
        _selectedPeerId = person.id;
        _zoom = _NetworkZoom.me;
      });
      return;
    }
    setState(() => _selectedPeerId = person.id);
  }

  void _onSelectExternalOrg(_OrbitPerson person) {
    setState(() => _selectedPeerId = person.id);
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

class _OrbitPerson {
  const _OrbitPerson({
    required this.id,
    required this.label,
    this.caption,
    this.avatarUrl,
    this.isSelf = false,
    this.members,
    this.agentSlugs = const [],
  });

  final String id;
  final String label;
  final String? caption;
  final String? avatarUrl;
  final bool isSelf;
  final List<ContactView>? members;
  final List<String> agentSlugs;
}

/// Org / External: ink discs on one orbit around hub.
class _PeopleOrbitGraph extends StatefulWidget {
  const _PeopleOrbitGraph({
    required this.hubLabel,
    required this.people,
    required this.onSelect,
    this.hubCaption,
    this.selectedId,
    this.onHubTap,
  });

  final String hubLabel;
  final String? hubCaption;
  final List<_OrbitPerson> people;
  final String? selectedId;
  final VoidCallback? onHubTap;
  final ValueChanged<_OrbitPerson> onSelect;

  @override
  State<_PeopleOrbitGraph> createState() => _PeopleOrbitGraphState();
}

class _PeopleOrbitGraphState extends State<_PeopleOrbitGraph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.people;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFFF5F5F4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final center = Offset(size.width * 0.48, size.height * 0.48);
            final orbitR = (math.min(size.width, size.height) * 0.32)
                .clamp(120.0, 190.0);
            final n = math.max(people.length, 1);
            final selectedIndex = widget.selectedId == null
                ? -1
                : people.indexWhere((p) => p.id == widget.selectedId);
            final graphReady = _enter.value > 0.9;
            final hubSize = widget.hubLabel.length > 8 ? 11.0 : 14.0;

            return AnimatedBuilder(
              animation: _enter,
              builder: (context, _) {
                final t = _enter.value;
                final hubT = _easeUnit(t, 0.00, 0.36);
                final labelT = _easeUnit(t, 0.10, 0.48);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: size,
                      painter: _ConcentricOrbitPainter(
                        center: center,
                        orbitR: orbitR,
                        agentCount: people.length,
                        emphasizeIndex: selectedIndex,
                        progress: t,
                      ),
                    ),
                    Positioned(
                      left: center.dx - 44,
                      top: center.dy - 44,
                      width: 88,
                      child: Column(
                        children: [
                          Opacity(
                            opacity: hubT,
                            child: Transform.scale(
                              scale: reduce ? 1 : 0.88 + 0.12 * hubT,
                              child: GestureDetector(
                                onTap: widget.onHubTap,
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF292524),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    widget.hubLabel,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: const Color(0xFFFAFAF9),
                                      fontSize: hubSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (widget.hubCaption != null) ...[
                            const SizedBox(height: 8),
                            Opacity(
                              opacity: labelT,
                              child: Text(
                                widget.hubCaption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF78716C),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    for (var i = 0; i < people.length; i++)
                      _OrbitDiscNode(
                        key: ValueKey(people[i].id),
                        angle: -math.pi / 2 + (2 * math.pi * i / n),
                        center: center,
                        orbitR: orbitR,
                        selected: people[i].id == widget.selectedId,
                        reduceMotion: reduce,
                        appearDelay: graphReady
                            ? Duration.zero
                            : Duration(
                                milliseconds: 180 + math.min(i * 70, 280),
                              ),
                        label: people[i].label,
                        ink: true,
                        agentSlugs: people[i].agentSlugs,
                        mark: _personMark(people[i]),
                        onSelect: () => widget.onSelect(people[i]),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Widget _personMark(_OrbitPerson person) {
    if (!person.isSelf &&
        person.avatarUrl != null &&
        person.avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          person.avatarUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _personInitial(person.label),
        ),
      );
    }
    if (person.isSelf) {
      return const Text(
        'you',
        style: TextStyle(
          color: Color(0xFFFAFAF9),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return _personInitial(person.label);
  }

  static Widget _personInitial(String label) {
    final ch = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return Text(
      ch,
      style: const TextStyle(
        color: Color(0xFFFAFAF9),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Calm concentric map: you at center, agents on one orbit (Penpot Network — Me).
class _AgentsGraph extends StatefulWidget {
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

  @override
  State<_AgentsGraph> createState() => _AgentsGraphState();
}

class _AgentsGraphState extends State<_AgentsGraph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;

  List<AgentInfo> get _orbitAgents => [
        ?widget.primary,
        ...widget.subs,
      ];

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agents = _orbitAgents;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFFF5F5F4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final center = Offset(size.width * 0.48, size.height * 0.48);
            final orbitR = (math.min(size.width, size.height) * 0.32)
                .clamp(120.0, 190.0);
            final n = math.max(agents.length, 1);
            final selectedIndex = widget.selectedId == null
                ? -1
                : agents.indexWhere((a) => a.id == widget.selectedId);
            final emphasize = selectedIndex >= 0
                ? selectedIndex
                : (widget.primary == null
                    ? -1
                    : agents.indexWhere((a) => a.id == widget.primary!.id));
            final graphReady = _enter.value > 0.9;

            return AnimatedBuilder(
              animation: _enter,
              builder: (context, _) {
                final t = _enter.value;
                final hubT = _easeUnit(t, 0.00, 0.36);
                final labelT = _easeUnit(t, 0.10, 0.48);
                final addT = _easeUnit(t, 0.52, 0.82);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: size,
                      painter: _ConcentricOrbitPainter(
                        center: center,
                        orbitR: orbitR,
                        agentCount: agents.length,
                        emphasizeIndex: emphasize,
                        progress: t,
                      ),
                    ),
                    Positioned(
                      left: center.dx - 44,
                      top: center.dy - 44,
                      width: 88,
                      child: Column(
                        children: [
                          Opacity(
                            opacity: hubT,
                            child: Transform.scale(
                              scale: reduce ? 1 : 0.88 + 0.12 * hubT,
                              child: Container(
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
                            ),
                          ),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: labelT,
                            child: Text(
                              formatMailAddress(widget.handle),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF78716C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < agents.length; i++)
                      _OrbitDiscNode(
                        key: ValueKey(agents[i].id),
                        angle: -math.pi / 2 + (2 * math.pi * i / n),
                        center: center,
                        orbitR: orbitR,
                        selected: agents[i].id == widget.selectedId ||
                            (widget.selectedId == null &&
                                widget.primary != null &&
                                agents[i].id == widget.primary!.id),
                        reduceMotion: reduce,
                        appearDelay: graphReady
                            ? Duration.zero
                            : Duration(
                                milliseconds: 180 + math.min(i * 70, 280),
                              ),
                        label: agents[i].slug.trim().toLowerCase(),
                        mark: AiHostIcon(
                          agents[i].slug.trim().toLowerCase(),
                          size: 28,
                          showPlate: false,
                        ),
                        onSelect: () => widget.onSelect(
                          agents[i],
                          widget.primary != null &&
                              agents[i].id == widget.primary!.id,
                        ),
                      ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Opacity(
                        opacity: addT,
                        child: TextButton.icon(
                          onPressed: widget.onAdd,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF57534E),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _OrbitDiscNode extends StatefulWidget {
  const _OrbitDiscNode({
    super.key,
    required this.angle,
    required this.center,
    required this.orbitR,
    required this.selected,
    required this.reduceMotion,
    required this.appearDelay,
    required this.onSelect,
    required this.label,
    required this.mark,
    this.ink = false,
    this.agentSlugs = const [],
  });

  final double angle;
  final Offset center;
  final double orbitR;
  final bool selected;
  final bool reduceMotion;
  final Duration appearDelay;
  final VoidCallback onSelect;
  final String label;
  final Widget mark;
  final bool ink;
  final List<String> agentSlugs;

  @override
  State<_OrbitDiscNode> createState() => _OrbitDiscNodeState();
}

class _OrbitDiscNodeState extends State<_OrbitDiscNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _appear;
  Timer? _delay;
  bool _hover = false;
  bool _press = false;

  static const _disc = 56.0;
  static const _tick = 18.0;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    if (widget.reduceMotion) {
      _appear.value = 1;
    } else if (widget.appearDelay == Duration.zero) {
      _appear.forward();
    } else {
      _delay = Timer(widget.appearDelay, () {
        if (mounted) _appear.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ax = widget.center.dx + math.cos(widget.angle) * widget.orbitR;
    final ay = widget.center.dy + math.sin(widget.angle) * widget.orbitR;
    final motion = _agentsMotion(context, const Duration(milliseconds: 180));
    final hoverScale = widget.reduceMotion
        ? 1.0
        : _press
            ? 0.96
            : _hover
                ? 1.05
                : 1.0;
    final ink = widget.ink;
    final ticks = widget.agentSlugs.take(4).toList();
    final extra = widget.agentSlugs.length - ticks.length;
    final tickCount = ticks.length + (extra > 0 ? 1 : 0);
    final boxW = ink ? 140.0 : 112.0;

    return Positioned(
      left: ax - boxW / 2,
      top: ay - _disc / 2,
      width: boxW,
      child: AnimatedBuilder(
        animation: _appear,
        builder: (context, child) {
          final at = Curves.easeOutCubic.transform(_appear.value);
          final inward = widget.reduceMotion ? 0.0 : (1 - at) * 14;
          return Opacity(
            opacity: at,
            child: Transform.translate(
              offset: Offset(
                -math.cos(widget.angle) * inward,
                -math.sin(widget.angle) * inward,
              ),
              child: Transform.scale(
                scale: widget.reduceMotion ? 1 : 0.86 + 0.14 * at,
                child: child,
              ),
            ),
          );
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() {
            _hover = false;
            _press = false;
          }),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _press = true),
            onTapUp: (_) => setState(() => _press = false),
            onTapCancel: () => setState(() => _press = false),
            onTap: widget.onSelect,
            behavior: HitTestBehavior.opaque,
            child: AnimatedScale(
              scale: hoverScale,
              duration: motion,
              curve: Curves.easeOutCubic,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: boxW,
                    height: _disc,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        AnimatedScale(
                          scale: widget.selected ? 1.0 : 48 / _disc,
                          duration: motion,
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: motion,
                            curve: Curves.easeOutCubic,
                            width: _disc,
                            height: _disc,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ink
                                  ? const Color(0xFF292524)
                                  : const Color(0xFFFAFAF9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.selected
                                    ? (ink
                                        ? const Color(0xFFFAFAF9)
                                        : const Color(0xFF292524))
                                    : (ink
                                        ? const Color(0xFF292524)
                                        : const Color(0xFFA8A29E)),
                                width: widget.selected ? 2 : (ink ? 0 : 1),
                              ),
                              boxShadow: widget.selected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF166534)
                                            .withValues(alpha: 0.22),
                                        blurRadius: 14,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: widget.mark,
                          ),
                        ),
                        if (ink)
                          for (var i = 0; i < ticks.length; i++)
                            _rimTick(
                              index: i,
                              count: tickCount,
                              child: _HostRimChip(ticks[i], size: _tick),
                            ),
                        if (ink && extra > 0)
                          _rimTick(
                            index: ticks.length,
                            count: tickCount,
                            child: _HostCountChip('+$extra'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                      color: const Color(0xFF57534E),
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

  Widget _rimTick({
    required int index,
    required int count,
    required Widget child,
  }) {
    final spread = count <= 1 ? 0.0 : 0.55;
    final t = count <= 1 ? 0.0 : (index / (count - 1) - 0.5);
    final tickAng = widget.angle + t * spread;
    const r = 34.0;
    return Positioned(
      left: (widget.ink ? 140.0 : 112.0) / 2 + math.cos(tickAng) * r - _tick / 2,
      top: _disc / 2 + math.sin(tickAng) * r - _tick / 2,
      child: child,
    );
  }
}

class _HostRimChip extends StatelessWidget {
  const _HostRimChip(this.slug, {required this.size});

  final String slug;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF9),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE7E5E4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140C0A09),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: AiHostIcon(slug, size: size * 0.62, showPlate: false),
    );
  }
}

class _HostCountChip extends StatelessWidget {
  const _HostCountChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF292524),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFAFAF9),
          fontSize: 9,
          fontWeight: FontWeight.w700,
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
    required this.progress,
  });

  final Offset center;
  final double orbitR;
  final int agentCount;
  final int emphasizeIndex;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final ringT = _easeUnit(progress, 0.10, 0.45);
    final outerT = _easeUnit(progress, 0.18, 0.55);
    final spokeT = _easeUnit(progress, 0.16, 0.58);

    if (ringT > 0) {
      canvas.drawCircle(
        center,
        orbitR,
        Paint()
          ..color = const Color(0xFFE7E5E4).withValues(alpha: ringT)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (outerT > 0) {
      const outer = Color(0x66E7E5E4);
      canvas.drawCircle(
        center,
        orbitR + 70,
        Paint()
          ..color = outer.withValues(alpha: outer.a * outerT)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    if (agentCount == 0 || spokeT <= 0.02) return;
    final n = agentCount;
    for (var i = 0; i < n; i++) {
      final ang = -math.pi / 2 + (2 * math.pi * i / n);
      final end = Offset(
        center.dx + math.cos(ang) * orbitR,
        center.dy + math.sin(ang) * orbitR,
      );
      final emphasized = i == emphasizeIndex;
      final base = emphasized
          ? const Color(0xBFA8A29E)
          : const Color(0x80A8A29E);
      final spoke = Paint()
        ..color = base.withValues(alpha: base.a * spokeT)
        ..strokeWidth = emphasized ? 1.5 : 1.15
        ..style = PaintingStyle.stroke;
      final ux = (end.dx - center.dx) / orbitR;
      final uy = (end.dy - center.dy) / orbitR;
      final start = Offset(center.dx + ux * 44, center.dy + uy * 44);
      final fullTip = Offset(end.dx - ux * 24, end.dy - uy * 24);
      final tip = Offset.lerp(start, fullTip, spokeT)!;
      canvas.drawLine(start, tip, spoke);
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricOrbitPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.orbitR != orbitR ||
        oldDelegate.agentCount != agentCount ||
        oldDelegate.emphasizeIndex != emphasizeIndex ||
        oldDelegate.progress != progress;
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
