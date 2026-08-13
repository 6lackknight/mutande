import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/mutande_macos_theme.dart';
import '../util/clock_format.dart';
import 'ai_host_icon.dart';

/// Org / External tap target for the on-graph popover.
class PeerInspectData {
  const PeerInspectData({
    required this.id,
    required this.label,
    required this.handle,
    this.handles = const [],
    this.avatarUrl,
    this.agentSlugs = const [],
    this.orgSlug,
    this.kindLabel,
    this.deviceCount = 0,
    this.hasPubkey = false,
    this.linkedAt,
    this.hasThread = false,
    this.platforms = const [],
  });

  final String id;
  final String label;
  final String handle;
  final List<String> handles;
  final String? avatarUrl;
  final List<String> agentSlugs;
  final String? orgSlug;
  final String? kindLabel;
  final int deviceCount;
  final bool hasPubkey;
  final String? linkedAt;
  final bool hasThread;
  final List<String> platforms;
}

Alignment peerPopoverAlignment(List<PeerInspectData> people, String id) {
  final i = people.indexWhere((p) => p.id == id);
  if (i < 0 || people.isEmpty) return const Alignment(0, 0.35);
  final n = math.max(people.length, 1);
  final ang = -math.pi / 2 + (2 * math.pi * i / n);
  return Alignment(math.cos(ang) * 0.62, math.sin(ang) * 0.55 + 0.08);
}

/// Graph + unfold inspect (locked Org tap). Light barrier; Esc / tap out.
class PeerPopoverLayer extends StatefulWidget {
  const PeerPopoverLayer({
    super.key,
    required this.graph,
    required this.people,
    required this.selectedId,
    required this.onDismiss,
    required this.onCopy,
    required this.onMessage,
  });

  final Widget graph;
  final List<PeerInspectData> people;
  final String? selectedId;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onMessage;

  @override
  State<PeerPopoverLayer> createState() => _PeerPopoverLayerState();
}

class _PeerPopoverLayerState extends State<PeerPopoverLayer> {
  String? _copied;

  PeerInspectData? get _peer {
    final id = widget.selectedId;
    if (id == null) return null;
    for (final p in widget.people) {
      if (p.id == id) return p;
    }
    return null;
  }

  Duration _motion(Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

  void _copy(String handle) {
    widget.onCopy(handle);
    setState(() => _copied = handle);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _copied == handle) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer = _peer;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final motion = _motion(const Duration(milliseconds: 200));

    return Focus(
      autofocus: peer != null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape && peer != null) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned.fill(child: widget.graph),
          if (peer != null) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onDismiss,
                behavior: HitTestBehavior.opaque,
                child: const ColoredBox(color: Color(0x220C0A09)),
              ),
            ),
            Align(
              alignment: peerPopoverAlignment(widget.people, peer.id),
              child: PeerUnfoldInspect(
                peer: peer,
                copied: _copied,
                motion: motion,
                reduce: reduce,
                onCopy: _copy,
                onMessage: widget.onMessage,
                onClose: widget.onDismiss,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Selected disc grows; inspect is the node (label + action tray).
class PeerUnfoldInspect extends StatelessWidget {
  const PeerUnfoldInspect({
    super.key,
    required this.peer,
    required this.copied,
    required this.motion,
    required this.reduce,
    required this.onCopy,
    required this.onMessage,
    required this.onClose,
  });

  final PeerInspectData peer;
  final String? copied;
  final Duration motion;
  final bool reduce;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onMessage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final extras = peer.handles.where((h) => h != peer.handle).toList();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0.86, end: 1),
      duration: motion,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: reduce ? 1 : t,
        child: Transform.scale(scale: t, child: child),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topRight,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MutandeColors.emerald.withValues(alpha: 0.28),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: PeerFace(peer: peer, size: 88),
              ),
              Positioned(
                right: -8,
                top: -8,
                child: IconButton.filled(
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: MutandeColors.stone50,
                    foregroundColor: MutandeColors.stone600,
                    minimumSize: const Size(28, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            peer.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            peer.handle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Menlo',
              fontSize: 11,
              color: MutandeColors.stone500,
            ),
          ),
          const SizedBox(height: 12),
          PeerWriteToTray(
            peer: peer,
            copied: copied,
            extras: extras,
            onCopy: onCopy,
            onMessage: onMessage,
          ),
        ],
      ),
    );
  }
}

class PeerFace extends StatelessWidget {
  const PeerFace({super.key, required this.peer, required this.size});

  final PeerInspectData peer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = peer.avatarUrl?.trim();
    final ch = peer.label.trim().isEmpty
        ? '?'
        : peer.label.trim()[0].toUpperCase();
    final mark = url != null && url.isNotEmpty
        ? ClipOval(
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initial(ch),
            ),
          )
        : _initial(ch);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: MutandeColors.stone800,
        shape: BoxShape.circle,
      ),
      child: mark,
    );
  }

  Widget _initial(String ch) {
    return Text(
      ch,
      style: TextStyle(
        color: MutandeColors.stone50,
        fontSize: size >= 72 ? 28 : size >= 44 ? 18 : 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

List<String> peerInspectMeta(PeerInspectData p) {
  return [
    if ((p.kindLabel ?? '').isNotEmpty) p.kindLabel!,
    if ((p.orgSlug ?? '').isNotEmpty) p.orgSlug!,
    if (p.deviceCount > 0)
      p.platforms.isNotEmpty
          ? p.platforms.join(' · ')
          : '${p.deviceCount} device${p.deviceCount == 1 ? '' : 's'}',
    if (p.hasPubkey) 'wrap' else if (p.kindLabel == 'external') 'app',
    if (p.hasThread) 'thread',
    if ((p.linkedAt ?? '').isNotEmpty) 'linked ${formatRelativeTime(p.linkedAt)}',
  ];
}

/// Handle + hosts as destinations; copy is a text button.
class PeerWriteToTray extends StatelessWidget {
  const PeerWriteToTray({
    super.key,
    required this.peer,
    required this.copied,
    required this.extras,
    required this.onCopy,
    required this.onMessage,
  });

  final PeerInspectData peer;
  final String? copied;
  final List<String> extras;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) {
    final meta = peerInspectMeta(peer);
    final copiedHere = copied == peer.handle;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Material(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(14),
        elevation: 8,
        shadowColor: const Color(0x330C0A09),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                  child: Text(
                    meta.join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: MutandeColors.stone500,
                    ),
                  ),
                ),
              PeerDestRow(
                label: peer.handle,
                mono: true,
                onTap: () => onMessage(peer.handle),
              ),
              for (final slug in peer.agentSlugs)
                PeerDestRow(
                  label: '@$slug',
                  slug: slug,
                  onTap: () => onMessage('${peer.handle}/$slug'),
                ),
              for (final h in extras)
                PeerDestRow(
                  label: h,
                  mono: true,
                  onTap: () => onMessage(h),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onCopy(peer.handle),
                  child: Text(copiedHere ? 'Copied' : 'Copy address'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PeerDestRow extends StatefulWidget {
  const PeerDestRow({
    super.key,
    required this.label,
    required this.onTap,
    this.slug,
    this.mono = false,
  });

  final String label;
  final String? slug;
  final bool mono;
  final VoidCallback onTap;

  @override
  State<PeerDestRow> createState() => _PeerDestRowState();
}

class _PeerDestRowState extends State<PeerDestRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduce ? 0 : 120),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? MutandeColors.stone100 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (widget.slug != null) ...[
                AiHostIcon(widget.slug!, size: 14, showPlate: false),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: widget.mono ? 'Menlo' : null,
                    fontSize: widget.mono ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: MutandeColors.stone800,
                  ),
                ),
              ),
              Icon(
                Icons.north_east,
                size: 14,
                color: _hover ? MutandeColors.stone800 : MutandeColors.stone400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
