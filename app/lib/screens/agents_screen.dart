import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../widgets/thinking_orb.dart';

/// Handle → primary (default) → sub-agents. Graph (Stitch) + list toggle.
class AgentsPanel extends StatefulWidget {
  const AgentsPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.appVersion = '1.0.0',
  });

  final DaemonClient daemon;
  final String? handle;
  final String appVersion;

  @override
  State<AgentsPanel> createState() => _AgentsPanelState();
}

class _AgentsPanelState extends State<AgentsPanel> {
  bool _loading = true;
  String? _error;
  AgentListResult? _list;
  bool _graph = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.daemon.listAgents(handle: widget.handle);
      if (!mounted) return;
      setState(() {
        _list = list;
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
      setState(() => _error = e.toString());
    }
  }

  Future<void> _rename(AgentInfo agent) async {
    final controller = TextEditingController(text: agent.slug);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename slug'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'claude'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null || next.isEmpty || next == agent.slug) return;
    try {
      await widget.daemon.renameAgent(agentId: agent.id, slug: next);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _openInspector(AgentInfo agent, {required bool isPrimary}) {
    final handle = widget.handle ?? 'alice@acme';
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x660C0A09),
      builder: (context) => _AgentInspector(
        handle: handle,
        agent: agent,
        isPrimary: isPrimary,
        onRename: () {
          Navigator.pop(context);
          _rename(agent);
        },
        onSetDefault: isPrimary
            ? null
            : () async {
                Navigator.pop(context);
                await _setDefault(agent.id);
              },
        onViewThreads: () {
          Navigator.pop(context);
          // Parent owns tabs; snack is enough for now.
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(content: Text('Open Threads to view mail.')),
          );
        },
      ),
    );
  }

  void _onAdd() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connect an AI host in Settings, then return here to Add.'),
      ),
    );
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
        if (_loading)
          const Expanded(child: Center(child: MutandeOrb.standard()))
        else if (_error != null)
          Expanded(
            child: Center(
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF991B1B),
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
                    onSelect: (a, isPrimary) =>
                        _openInspector(a, isPrimary: isPrimary),
                    onAdd: _onAdd,
                  )
                : _AgentsList(
                    handle: handle,
                    primary: primary,
                    subs: subs,
                    onSelect: (a, isPrimary) =>
                        _openInspector(a, isPrimary: isPrimary),
                    onAdd: _onAdd,
                    onSetDefault: _setDefault,
                  ),
          ),
        _AgentsFooter(
          count: agents.length,
          version: widget.appVersion,
        ),
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
    required this.onSelect,
    required this.onAdd,
  });

  final String handle;
  final AgentInfo? primary;
  final List<AgentInfo> subs;
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
                  onTap: () => onSelect(primary!, true),
                ),
                _Trunk(solid: false),
                _BranchRow(
                  subs: subs,
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
          child: Text(
            handle,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFFAFAF9),
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  letterSpacing: 0.2,
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
        painter: _LinePainter(
          color: const Color(0xFF92400E),
          dashed: !solid,
        ),
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
  const _PrimaryCard({required this.slug, required this.onTap});

  final String slug;
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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: Color(0xFF57534E),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slug,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: const Color(0xFF292524),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF166534),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'CONNECTED',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF78716C),
                                    letterSpacing: 0.6,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
    required this.onSelect,
    required this.onAdd,
  });

  final List<AgentInfo> subs;
  final ValueChanged<AgentInfo> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      ...subs.map(
        (a) => _SubCard(
          slug: a.slug,
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
          child: CustomPaint(
            painter: _BranchPainter(count: children.length),
          ),
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
  const _SubCard({required this.slug, required this.onTap});

  final String slug;
  final VoidCallback onTap;

  IconData get _icon {
    switch (slug) {
      case 'cursor':
        return Icons.code;
      case 'chatgpt':
        return Icons.smart_toy_outlined;
      default:
        return Icons.extension_outlined;
    }
  }

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
              Icon(_icon, size: 20, color: const Color(0xFF57534E)),
              const SizedBox(height: 8),
              Text(
                slug,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF292524),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD97706),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Idle',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF78716C),
                        ),
                  ),
                ],
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
          child: Center(
            child: Icon(Icons.add, color: Color(0xFF78716C)),
          ),
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
          'Connect an AI host in Settings for your primary agent.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF78716C),
              ),
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
    required this.onSelect,
    required this.onAdd,
    required this.onSetDefault,
  });

  final String handle;
  final AgentInfo? primary;
  final List<AgentInfo> subs;
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
            leading: const Icon(Icons.anchor, color: Color(0xFF92400E)),
            title: Text(primary!.slug),
            subtitle: Text('Primary · receives $handle & @all'),
            trailing: const Text('PRIMARY',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                )),
            onTap: () => onSelect(primary!, true),
          ),
        for (final a in subs)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 48, right: 8),
            leading: const Icon(Icons.circle_outlined, size: 16),
            title: Text(a.slug),
            subtitle: Text('$handle/${a.slug}'),
            trailing: TextButton(
              onPressed: () => onSetDefault(a.id),
              child: const Text('Set default'),
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

class _AgentInspector extends StatelessWidget {
  const _AgentInspector({
    required this.handle,
    required this.agent,
    required this.isPrimary,
    required this.onRename,
    required this.onViewThreads,
    this.onSetDefault,
  });

  final String handle;
  final AgentInfo agent;
  final bool isPrimary;
  final VoidCallback onRename;
  final VoidCallback onViewThreads;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    final display = isPrimary ? handle : '$handle/${agent.slug}';

    return Dialog(
      backgroundColor: const Color(0xFFFAFAF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_outlined,
                      size: 18, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Text(
                    'Agent Inspector',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF292524),
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _InspectorField(label: 'DISPLAY ADDRESS', value: display),
              _InspectorField(label: 'AGENT SLUG', value: agent.slug),
              _InspectorField(label: 'HOST', value: _hostLabel(agent.slug)),
              _InspectorField(
                label: 'STATUS',
                value: isPrimary ? 'Connected' : 'Idle',
                trailing: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? const Color(0xFF166534)
                        : const Color(0xFFD97706),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRename,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Rename slug'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: const Color(0xFF44403C),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Disconnect from Settings → AI hosts.'),
                    ),
                  );
                },
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Disconnect host'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: const Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onViewThreads,
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('View Threads'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1917),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSetDefault,
                      child: const Text('Set as Default'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hostLabel(String slug) {
    switch (slug) {
      case 'claude':
        return 'Claude Desktop';
      case 'cursor':
        return 'Cursor';
      case 'chatgpt':
        return 'ChatGPT';
      default:
        return slug;
    }
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFA8A29E),
                  letterSpacing: 0.8,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontFamily: 'Menlo',
                        fontSize: 13,
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
