import 'package:flutter/cupertino.dart';

import '../theme/mutande_macos_theme.dart';

/// Titlebar pill metrics — outer track plus the selected thumb (Collab).
/// Search and icon pills reuse [thumbHeight] / [thumbStadium].
abstract final class HomeChrome {
  static const height = 40.0;
  static const inset = 3.0;
  static const thumbHeight = height - inset * 2;
  static const glyphLeading = 16.0;
  static const pillGap = 8.0;
  static const muteFill = MutandeColors.stone200;
  static const muteForeground = MutandeColors.stone500;

  /// Segment label / chrome control icon (Threads · Collab · Network).
  static const iconSize = 16.0;

  /// Selected thumb min width.
  static const controlMinWidth = 112.0;

  /// Window inset around the home body card (below the titlebar).
  static const bodyInset = EdgeInsets.fromLTRB(10, 6, 10, 10);

  /// Content-card radius — same family as the tab track (stadium 20).
  static BorderRadius get bodyRadius => BorderRadius.circular(16);

  /// Active tab thumb fill — raised reading pane reuses this.
  static const raisedFill = MutandeColors.stone50;

  /// Inset of the reading card inside the muted body (list stays flush).
  static const raisedInset = EdgeInsets.fromLTRB(4, 8, 8, 8);

  /// Nested in [bodyRadius] 16; matches Material card corners.
  static BorderRadius get raisedRadius => BorderRadius.circular(12);

  static BorderRadius get stadium => BorderRadius.circular(height / 2);
  static BorderRadius get thumbStadium =>
      BorderRadius.circular(thumbHeight / 2);
}

/// Inset muted surface for Threads · Collab · Network — same fill as the
/// tab-chip track, clipped so inner panes don't bleed into the window frame.
class HomeChromeBody extends StatelessWidget {
  const HomeChromeBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: HomeChrome.bodyInset,
      child: ClipRRect(
        borderRadius: HomeChrome.bodyRadius,
        child: ColoredBox(color: HomeChrome.muteFill, child: child),
      ),
    );
  }
}

/// White raised surface matching the selected tab thumb (`stone50`, no
/// border/shadow — the chip has none). Used for the Threads reading pane.
class HomeChromeRaised extends StatelessWidget {
  const HomeChromeRaised({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: HomeChrome.raisedInset,
      child: ClipRRect(
        borderRadius: HomeChrome.raisedRadius,
        child: ColoredBox(color: HomeChrome.raisedFill, child: child),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    const thumbHeight = HomeChrome.thumbHeight;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGlyph) ...[
          const Padding(
            padding: EdgeInsets.only(left: HomeChrome.glyphLeading, right: 12),
            child: _AtIGlyph(),
          ),
        ],
        SizedBox(
          height: HomeChrome.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MutandeColors.stone200,
              borderRadius: HomeChrome.stadium,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                6,
                HomeChrome.inset,
                6,
                HomeChrome.inset,
              ),
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
              borderRadius: HomeChrome.thumbStadium,
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
