import 'package:flutter/cupertino.dart';

import '../theme/mutande_macos_theme.dart';

/// Pinned home tabs: Threads · Collab · Network.
///
/// Custom stadium segmented control in the titlebar — Flutter's
/// [CupertinoSlidingSegmentedControl] hardcodes a 7px thumb / 9px track.
class HomeChromeStrip extends StatelessWidget {
  const HomeChromeStrip({
    super.key,
    required this.tab,
    required this.onTab,
    this.showGlyph = false,
  });

  final int tab;
  final ValueChanged<int> onTab;

  /// Compact `@i` mark before the tabs (Mac titlebar, after traffic lights).
  final bool showGlyph;

  static const labels = ['Threads', 'Collab', 'Network'];
  static const icons = [
    CupertinoIcons.envelope,
    CupertinoIcons.rectangle_split_3x1,
    CupertinoIcons.person_2,
  ];

  static const _height = 40.0;
  static const _inset = 3.0;

  @override
  Widget build(BuildContext context) {
    final thumbHeight = _height - _inset * 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGlyph) ...[
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: _AtIGlyph(),
          ),
        ],
        SizedBox(
          height: _height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MutandeColors.stone200,
              borderRadius: BorderRadius.circular(_height / 2),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, _inset, 6, _inset),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    _HeaderThumb(
                      selected: tab == i,
                      thumbHeight: thumbHeight,
                      onTap: () => onTab(i),
                      child: _SegmentLabel(
                        icon: icons[i],
                        label: labels[i],
                        selected: tab == i,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderThumb extends StatelessWidget {
  const _HeaderThumb({
    required this.selected,
    required this.thumbHeight,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final double thumbHeight;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: thumbHeight,
            constraints: const BoxConstraints(minWidth: 112),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? MutandeColors.stone50 : const Color(0x00000000),
              borderRadius: BorderRadius.circular(thumbHeight / 2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? MutandeColors.stone800 : MutandeColors.stone500;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _AtIGlyph extends StatelessWidget {
  const _AtIGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MutandeColors.stone800,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        '@i',
        style: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'Menlo',
          height: 1,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}
