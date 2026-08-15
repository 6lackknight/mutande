import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_chrome_strip.dart';

/// Muted stadium chrome matching unselected segmented segments.
class HomeChromePill extends StatelessWidget {
  const HomeChromePill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: HomeChrome.thumbHeight,
      decoration: BoxDecoration(
        color: HomeChrome.muteFill,
        borderRadius: HomeChrome.thumbStadium,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class HomeChromeIconAction {
  const HomeChromeIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

/// Single-icon stadium control (notifications bell).
class HomeChromeIconButton extends StatelessWidget {
  const HomeChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return HomeChromePill(
      child: _ChromeIconHit(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Grouped icons in one pill with hairline dividers (Safari share/+/tabs).
class HomeChromeIconCluster extends StatelessWidget {
  const HomeChromeIconCluster({super.key, required this.actions});

  final List<HomeChromeIconAction> actions;

  @override
  Widget build(BuildContext context) {
    return HomeChromePill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              const SizedBox(
                width: 1,
                height: 16,
                child: ColoredBox(color: MutandeColors.stone400),
              ),
            _ChromeIconHit(
              icon: actions[i].icon,
              tooltip: actions[i].tooltip,
              onPressed: actions[i].onPressed,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChromeIconHit extends StatefulWidget {
  const _ChromeIconHit({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_ChromeIconHit> createState() => _ChromeIconHitState();
}

class _ChromeIconHitState extends State<_ChromeIconHit> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: Tooltip(
            message: widget.tooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: HomeChrome.thumbHeight,
              alignment: Alignment.center,
              color: const Color(0x00000000),
              child: Icon(
                widget.icon,
                size: 16,
                color: _hover
                    ? MutandeColors.stone600
                    : HomeChrome.muteForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
