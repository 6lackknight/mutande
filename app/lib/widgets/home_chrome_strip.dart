import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/mutande_macos_theme.dart';

/// Titlebar pill metrics — outer track plus the selected thumb (Collab).
/// Search, icon wells, and labeled pills reuse [thumbHeight] / [thumbStadium]
/// / [thumbPadX].
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

  /// Horizontal inset inside thumb-height wells (icon buttons and labels).
  static const thumbPadX = 10.0;

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
///
/// One overlay thumb translates between equal-width segments (not a
/// per-segment fill fade).
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
    LucideIcons.gitMerge,
    CupertinoIcons.rectangle_split_3x1,
    CupertinoIcons.person_2,
  ];

  /// Overlay selection thumb — tests assert it translates, not teleports.
  static const thumbKey = Key('home-chrome-thumb');

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGlyph) ...[
          const Padding(
            padding: EdgeInsets.only(left: HomeChrome.glyphLeading, right: 12),
            child: _AtIGlyph(),
          ),
        ],
        _SlidingSegmentedTrack(tab: tab, onTab: onTab),
      ],
    );
  }
}

class _SlidingSegmentedTrack extends StatefulWidget {
  const _SlidingSegmentedTrack({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

  @override
  State<_SlidingSegmentedTrack> createState() => _SlidingSegmentedTrackState();
}

class _SlidingSegmentedTrackState extends State<_SlidingSegmentedTrack> {
  final _labelKeys = List<GlobalKey>.generate(
    HomeChromeStrip.labels.length,
    (_) => GlobalKey(),
  );

  /// Null until the first layout; then the max segment width (equal slots).
  double? _segmentWidth;

  int get _tab {
    final last = HomeChromeStrip.labels.length - 1;
    if (widget.tab < 0) return 0;
    if (widget.tab > last) return last;
    return widget.tab;
  }

  double get _thumbWidth => _segmentWidth ?? HomeChrome.controlMinWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(_SlidingSegmentedTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    var widest = HomeChrome.controlMinWidth;
    for (final key in _labelKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final intrinsic = box.getMaxIntrinsicWidth(HomeChrome.thumbHeight);
      if (intrinsic > widest) widest = intrinsic;
    }
    if (_segmentWidth == null || (widest - _segmentWidth!).abs() > 0.5) {
      setState(() => _segmentWidth = widest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = HomeChromeStrip.labels.length;
    final slide = MutandeMotion.of(context, MutandeMotion.ui);
    return SizedBox(
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
          child: RepaintBoundary(
            child: Stack(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _tab.toDouble()),
                  duration: slide,
                  curve: MutandeMotion.easeOut,
                  builder: (context, t, child) {
                    return Transform.translate(
                      offset: Offset(t * _thumbWidth, 0),
                      child: child,
                    );
                  },
                  child: IgnorePointer(
                    child: SizedBox(
                      key: HomeChromeStrip.thumbKey,
                      width: _thumbWidth,
                      height: HomeChrome.thumbHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: MutandeColors.stone50,
                          borderRadius: HomeChrome.thumbStadium,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < n; i++)
                      _SegmentHit(
                        measureKey: _labelKeys[i],
                        selected: _tab == i,
                        width: _segmentWidth,
                        onTap: () => widget.onTab(i),
                        child: _SegmentLabel(
                          icon: HomeChromeStrip.icons[i],
                          label: HomeChromeStrip.labels[i],
                          selected: _tab == i,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentHit extends StatelessWidget {
  const _SegmentHit({
    required this.measureKey,
    required this.selected,
    required this.width,
    required this.onTap,
    required this.child,
  });

  final Key measureKey;
  final bool selected;
  final double? width;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      key: measureKey,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(child: child),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: width == null
              ? ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: HomeChrome.controlMinWidth,
                    minHeight: HomeChrome.thumbHeight,
                    maxHeight: HomeChrome.thumbHeight,
                  ),
                  child: padded,
                )
              : SizedBox(
                  width: width,
                  height: HomeChrome.thumbHeight,
                  child: padded,
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
    final target = selected ? MutandeColors.stone800 : MutandeColors.stone500;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: MutandeMotion.of(context, MutandeMotion.hover),
      curve: MutandeMotion.ease,
      builder: (context, color, child) {
        final ink = color ?? target;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: HomeChrome.iconSize, color: ink),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: ink,
              ),
            ),
          ],
        );
      },
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
