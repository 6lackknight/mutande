import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../widgets/ai_host_icon.dart';

/// Spatial command-center layout for threads + agent cards (pan/zoom canvas).
class ThreadsSpatialView extends StatefulWidget {
  const ThreadsSpatialView({
    super.key,
    required this.threads,
    required this.agents,
    required this.onOpenThread,
  });

  final List<ThreadSummary> threads;
  final AgentListResult? agents;
  final ValueChanged<String> onOpenThread;

  @override
  State<ThreadsSpatialView> createState() => _ThreadsSpatialViewState();
}

class _ThreadsSpatialViewState extends State<ThreadsSpatialView> {
  final _transform = TransformationController();

  void recenter() {
    _transform.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layouts = _layoutCards(widget.threads, widget.agents);
    const canvasW = 920.0;
    const canvasH = 640.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transform,
            minScale: 0.55,
            maxScale: 1.8,
            boundaryMargin: const EdgeInsets.all(120),
            child: CustomPaint(
              size: const Size(canvasW, canvasH),
              painter: _DotGridPainter(),
              child: SizedBox(
                width: canvasW,
                height: canvasH,
                child: Stack(
                  children: [
                    for (final layout in layouts)
                      Positioned(
                        left: layout.position.dx,
                        top: layout.position.dy,
                        child: layout.isAgent
                            ? _AgentSpatialCard(
                                agent: layout.agent!,
                                isDefault: layout.isDefault,
                              )
                            : _ThreadSpatialCard(
                                thread: layout.thread!,
                                emphasis: layout.emphasis,
                                onTap: () =>
                                    widget.onOpenThread(layout.thread!.id),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Material(
              color: Colors.white.withValues(alpha: 0.92),
              elevation: 1,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: recenter,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.center_focus_strong, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Recenter',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_SpatialLayout> _layoutCards(
    List<ThreadSummary> threads,
    AgentListResult? agents,
  ) {
    final out = <_SpatialLayout>[];
    final urgent = <ThreadSummary>[];
    final rest = <ThreadSummary>[];
    for (final t in threads) {
      if (t.yourStatus == 'pending') {
        urgent.add(t);
      } else {
        rest.add(t);
      }
    }

    var y = 24.0;
    for (var i = 0; i < urgent.length; i++) {
      out.add(
        _SpatialLayout(
          thread: urgent[i],
          emphasis: _SpatialEmphasis.hero,
          position: Offset(24, y),
        ),
      );
      y += 168;
    }

    final startY = urgent.isEmpty ? 24.0 : y + 12;
    const colW = 228.0;
    const rowH = 118.0;
    for (var i = 0; i < rest.length; i++) {
      final col = i % 3;
      final row = i ~/ 3;
      out.add(
        _SpatialLayout(
          thread: rest[i],
          emphasis: _SpatialEmphasis.normal,
          position: Offset(24 + col * colW, startY + row * rowH),
        ),
      );
    }

    final agentList = agents?.agents ?? const <AgentInfo>[];
    if (agentList.isNotEmpty) {
      var ax = 24.0;
      final threadRows = rest.isEmpty ? 0 : (rest.length + 2) ~/ 3;
      final ay = (urgent.isEmpty ? 24.0 : y + 12) + threadRows * 118 + 28;
      for (final a in agentList) {
        out.add(
          _SpatialLayout.agent(
            agent: a,
            isDefault: a.id == agents?.defaultAgentId,
            position: Offset(ax, ay),
          ),
        );
        ax += 196;
      }
    }

    return out;
  }
}

enum _SpatialEmphasis { hero, normal }

class _SpatialLayout {
  const _SpatialLayout({
    required this.thread,
    required this.emphasis,
    required this.position,
  }) : agent = null,
       isAgent = false,
       isDefault = false;

  const _SpatialLayout.agent({
    required this.agent,
    required this.isDefault,
    required this.position,
  }) : thread = null,
       emphasis = _SpatialEmphasis.normal,
       isAgent = true;

  final ThreadSummary? thread;
  final AgentInfo? agent;
  final _SpatialEmphasis emphasis;
  final Offset position;
  final bool isAgent;
  final bool isDefault;
}

class _ThreadSpatialCard extends StatelessWidget {
  const _ThreadSpatialCard({
    required this.thread,
    required this.emphasis,
    required this.onTap,
  });

  final ThreadSummary thread;
  final _SpatialEmphasis emphasis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hero = emphasis == _SpatialEmphasis.hero;
    final pending = thread.yourStatus == 'pending';
    final closed = thread.status == 'closed';

    final bg = hero ? const Color(0xFF292524) : Colors.white;
    final border = hero ? const Color(0xFF44403C) : const Color(0xFFE7E5E4);
    final titleColor = hero ? Colors.white : const Color(0xFF292524);
    final subColor = hero ? const Color(0xFFA8A29E) : const Color(0xFF78716C);

    final width = hero ? 280.0 : 208.0;
    final snippet = [
      thread.kind,
      if (thread.replyCount > 0) '${thread.replyCount} replies',
    ].join(' · ');

    return Material(
      color: bg,
      elevation: hero ? 2 : 1,
      shadowColor: const Color(0x220C0A09),
      borderRadius: BorderRadius.circular(hero ? 14 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(hero ? 14 : 12),
        child: Container(
          width: width,
          padding: EdgeInsets.fromLTRB(14, hero ? 14 : 12, 14, hero ? 14 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(hero ? 14 : 12),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _SpatialStatusPill(thread: thread, hero: hero),
                  const Spacer(),
                  if (hero)
                    Text(
                      'Now',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFD6D3D1),
                            fontSize: 10,
                          ),
                    ),
                ],
              ),
              SizedBox(height: hero ? 10 : 8),
              Text(
                thread.from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: hero ? 15 : 13,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                snippet.isEmpty ? 'Thread' : snippet,
                maxLines: hero ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subColor,
                      height: 1.35,
                    ),
              ),
              if (pending && hero) ...[
                const SizedBox(height: 10),
                Text(
                  'Awaiting your response',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFFBBF24),
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ] else if (closed && !hero) ...[
                const SizedBox(height: 6),
                Text(
                  'Resolved',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFA8A29E),
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

class _SpatialStatusPill extends StatelessWidget {
  const _SpatialStatusPill({required this.thread, required this.hero});

  final ThreadSummary thread;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color bg;
    late Color fg;
    late Color dot;

    if (thread.yourStatus == 'pending') {
      label = 'ACTION REQUIRED';
      bg = hero ? const Color(0xFF44403C) : const Color(0xFFFEF3C7);
      fg = hero ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
      dot = const Color(0xFFFBBF24);
    } else if (thread.status == 'closed') {
      label = 'CLOSED';
      bg = const Color(0xFFF5F5F4);
      fg = const Color(0xFF57534E);
      dot = const Color(0xFF78716C);
    } else if (thread.yourStatus == 'replied') {
      label = 'PENDING';
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFB45309);
      dot = const Color(0xFFD97706);
    } else {
      label = 'OPEN';
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF166534);
      dot = const Color(0xFF166534);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentSpatialCard extends StatelessWidget {
  const _AgentSpatialCard({required this.agent, this.isDefault = false});

  final AgentInfo agent;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7E5E4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110C0A09),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AiHostIcon(agent.slug, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  agent.slug,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF292524),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isDefault ? 'PRIMARY · monitoring' : 'Agent on canvas',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDefault
                      ? const Color(0xFF92400E)
                      : const Color(0xFF78716C),
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
          ),
        ],
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
