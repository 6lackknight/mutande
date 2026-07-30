import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';

/// Spatial command-center layout for threads + agent cards (pan/zoom canvas).
class ThreadsSpatialView extends StatefulWidget {
  const ThreadsSpatialView({
    super.key,
    required this.threads,
    required this.agents,
    required this.onOpenThread,
    this.myHandle,
  });

  final List<ThreadSummary> threads;
  final AgentListResult? agents;
  final ValueChanged<String> onOpenThread;
  final String? myHandle;

  @override
  State<ThreadsSpatialView> createState() => _ThreadsSpatialViewState();
}

class _ThreadsSpatialViewState extends State<ThreadsSpatialView> {
  final _transform = TransformationController();
  Size? _viewportSize;

  void recenter() {
    _fitToContent();
  }

  void _fitToContent() {
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      _transform.value = Matrix4.identity();
      return;
    }
    final pack = _layoutPack(widget.threads, widget.agents);
    const margin = 20.0;
    final bounds = pack.contentBounds;
    final scaleX = (viewport.width - margin * 2) / bounds.width;
    final scaleY = (viewport.height - margin * 2) / bounds.height;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.45, 1.0);
    final tx = (viewport.width - bounds.width * scale) / 2 - bounds.left * scale;
    final ty = (viewport.height - bounds.height * scale) / 2 - bounds.top * scale;
    _transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void didUpdateWidget(covariant ThreadsSpatialView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threads != widget.threads ||
        oldWidget.agents != widget.agents) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToContent());
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = _layoutPack(widget.threads, widget.agents);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewportSize != viewport) {
          _viewportSize = viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitToContent();
          });
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                minScale: 0.45,
                maxScale: 1.6,
                boundaryMargin: const EdgeInsets.all(80),
                clipBehavior: Clip.none,
                child: CustomPaint(
                  size: pack.canvasSize,
                  painter: _DotGridPainter(),
                  child: SizedBox(
                    width: pack.canvasSize.width,
                    height: pack.canvasSize.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final layout in pack.layouts)
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
                                    myHandle: widget.myHandle,
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
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.center_focus_strong, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Recenter',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
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
      },
    );
  }

  _SpatialLayoutPack _layoutPack(
    List<ThreadSummary> threads,
    AgentListResult? agents,
  ) {
    const cardW = 232.0;
    const rowH = 118.0;
    const gap = 16.0;
    const sectionGap = 24.0;
    const pad = 32.0;
    const maxCols = 3;

    final sorted = [...threads]
      ..sort((a, b) {
        final ap = a.yourStatus == 'pending' ? 0 : 1;
        final bp = b.yourStatus == 'pending' ? 0 : 1;
        return ap.compareTo(bp);
      });

    final layouts = <_SpatialLayout>[];
    final n = sorted.length;
    final cols = n <= 1 ? 1 : n == 2 ? 2 : maxCols.clamp(1, n);
    final rows = n == 0 ? 0 : (n + cols - 1) ~/ cols;
    final gridW = cols * cardW + (cols - 1) * gap;
    final gridH = rows == 0 ? 0.0 : rows * rowH + (rows - 1) * gap;

    for (var i = 0; i < n; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      layouts.add(
        _SpatialLayout(
          thread: sorted[i],
          emphasis: sorted[i].yourStatus == 'pending'
              ? _SpatialEmphasis.hero
              : _SpatialEmphasis.normal,
          position: Offset(col * (cardW + gap), row * (rowH + gap)),
        ),
      );
    }

    final agentList = agents?.agents ?? const <AgentInfo>[];
    const agentW = 176.0;
    const agentGap = 12.0;
    const agentH = 88.0;
    final agentsY = gridH == 0 ? 0.0 : gridH + sectionGap;
    final agentCols = agentList.isEmpty ? 0 : (agentList.length < cols ? agentList.length : cols);

    for (var i = 0; i < agentList.length; i++) {
      final row = agentCols == 0 ? 0 : i ~/ agentCols;
      final colInRow = agentCols == 0 ? 0 : i % agentCols;
      final agentsInRow = agentList.length - row * agentCols;
      final rowCount = agentsInRow > agentCols ? agentCols : agentsInRow;
      final rowW = rowCount * cardW + (rowCount - 1) * gap;
      final rowStartX = (gridW - rowW) / 2;
      final x = rowStartX + colInRow * (cardW + gap) + (cardW - agentW) / 2;
      final y = agentsY + row * (agentH + agentGap);
      layouts.add(
        _SpatialLayout.agent(
          agent: agentList[i],
          isDefault: agentList[i].id == agents?.defaultAgentId,
          position: Offset(x, y),
        ),
      );
    }

    final agentRows = agentCols == 0
        ? 0
        : (agentList.length + agentCols - 1) ~/ agentCols;
    final agentsBlockH = agentRows == 0
        ? 0.0
        : agentRows * agentH + (agentRows - 1) * agentGap;
    final contentW = gridW;
    final contentH = agentsY + agentsBlockH + (agentRows == 0 ? 0 : 12);
    final canvasW = contentW + pad * 2;
    final canvasH = contentH + pad * 2;
    final origin = Offset(
      (canvasW - contentW) / 2,
      (canvasH - contentH) / 2,
    );

    final positioned = layouts
        .map((l) => l.at(l.position + origin))
        .toList(growable: false);

    const threadCardH = 118.0;
    const agentCardH = 88.0;
    var maxRight = 0.0;
    var maxBottom = 0.0;
    for (final layout in positioned) {
      final w = layout.isAgent ? agentW : cardW;
      final h = layout.isAgent ? agentCardH : threadCardH;
      maxRight = maxRight > layout.position.dx + w
          ? maxRight
          : layout.position.dx + w;
      maxBottom = maxBottom > layout.position.dy + h
          ? maxBottom
          : layout.position.dy + h;
    }
    final contentBounds = Rect.fromLTRB(
      origin.dx,
      origin.dy,
      maxRight + 8,
      maxBottom + 8,
    );

    return _SpatialLayoutPack(
      layouts: positioned,
      canvasSize: Size(canvasW, canvasH),
      contentBounds: contentBounds,
    );
  }
}

class _SpatialLayoutPack {
  const _SpatialLayoutPack({
    required this.layouts,
    required this.canvasSize,
    required this.contentBounds,
  });

  final List<_SpatialLayout> layouts;
  final Size canvasSize;
  final Rect contentBounds;
}

enum _SpatialEmphasis { hero, normal }

class _SpatialLayout {
  const _SpatialLayout({
    required this.thread,
    required this.emphasis,
    required this.position,
  })  : agent = null,
        isAgent = false,
        isDefault = false;

  const _SpatialLayout.agent({
    required this.agent,
    required this.isDefault,
    required this.position,
  })  : thread = null,
        emphasis = _SpatialEmphasis.normal,
        isAgent = true;

  final ThreadSummary? thread;
  final AgentInfo? agent;
  final _SpatialEmphasis emphasis;
  final Offset position;
  final bool isAgent;
  final bool isDefault;

  _SpatialLayout at(Offset next) {
    if (isAgent) {
      return _SpatialLayout.agent(
        agent: agent!,
        isDefault: isDefault,
        position: next,
      );
    }
    return _SpatialLayout(
      thread: thread!,
      emphasis: emphasis,
      position: next,
    );
  }
}

class _ThreadSpatialCard extends StatelessWidget {
  const _ThreadSpatialCard({
    required this.thread,
    required this.emphasis,
    required this.onTap,
    this.myHandle,
  });

  final ThreadSummary thread;
  final _SpatialEmphasis emphasis;
  final VoidCallback onTap;
  final String? myHandle;

  static const _cardW = 232.0;

  @override
  Widget build(BuildContext context) {
    final hero = emphasis == _SpatialEmphasis.hero;
    final closed = thread.status == 'closed';

    final bg = hero ? const Color(0xFF292524) : Colors.white;
    final border = hero ? const Color(0xFF44403C) : const Color(0xFFE7E5E4);
    final titleColor = hero ? Colors.white : const Color(0xFF292524);
    final subColor = hero ? const Color(0xFFA8A29E) : const Color(0xFF78716C);

    final snippet = [
      thread.kind,
      if (thread.replyCount > 0) '${thread.replyCount} replies',
    ].join(' · ');
    final title = formatMailAddress(thread.from, myHandle: myHandle);

    return Material(
      color: bg,
      elevation: hero ? 2 : 1,
      shadowColor: const Color(0x220C0A09),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: _cardW,
          height: 118,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                snippet.isEmpty ? 'Thread' : snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subColor,
                      height: 1.35,
                    ),
              ),
              if (closed && !hero) ...[
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
      label = 'needs you';
      bg = hero ? const Color(0xFF44403C) : const Color(0xFFFEF3C7);
      fg = hero ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
      dot = const Color(0xFFB45309);
    } else if (thread.status == 'closed') {
      label = 'closed';
      bg = const Color(0xFFF5F5F4);
      fg = const Color(0xFF57534E);
      dot = const Color(0xFF78716C);
    } else if (thread.yourStatus == 'replied') {
      label = 'waiting';
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFB45309);
      dot = const Color(0xFFD97706);
    } else {
      label = 'open';
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
              fontWeight: FontWeight.w500,
              fontSize: 10,
              letterSpacing: 0.1,
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
    return SizedBox(
      width: 176,
      height: 88,
      child: Container(
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
                  agent.slug == 'default' ? 'default' : '@${agent.slug}',
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
