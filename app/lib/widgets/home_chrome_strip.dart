import 'package:flutter/cupertino.dart';

import '../theme/mutande_macos_theme.dart';

/// Pinned home tabs: Threads · Collab · Network.
///
/// [CupertinoSlidingSegmentedControl] in the titlebar / top chrome row.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGlyph) ...[
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: _AtIGlyph(),
          ),
        ],
        CupertinoSlidingSegmentedControl<int>(
          groupValue: tab,
          onValueChanged: (value) {
            if (value != null) onTab(value);
          },
          thumbColor: MutandeColors.stone50,
          backgroundColor: MutandeColors.stone200,
          proportionalWidth: true,
          children: {
            for (var i = 0; i < labels.length; i++)
              i: _SegmentLabel(
                icon: icons[i],
                label: labels[i],
                selected: tab == i,
              ),
          },
        ),
      ],
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
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
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
