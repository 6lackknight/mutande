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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGlyph) ...[
          const Padding(padding: EdgeInsets.only(right: 8), child: _AtIGlyph()),
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
              i: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: tab == i ? FontWeight.w600 : FontWeight.w500,
                  color: tab == i
                      ? MutandeColors.stone800
                      : MutandeColors.stone500,
                ),
              ),
          },
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
