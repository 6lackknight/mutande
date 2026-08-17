import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_chrome_strip.dart';

/// Quiet trailing sort — same pill family as filters, without a second black selected state.
enum MutandeListSort { recent, name }

class MutandeSortToggles extends StatelessWidget {
  const MutandeSortToggles({
    super.key,
    required this.value,
    required this.onChanged,
    this.recentKey = const Key('sort-recent'),
    this.nameKey = const Key('sort-name'),
  });

  final MutandeListSort value;
  final ValueChanged<MutandeListSort> onChanged;
  final Key recentKey;
  final Key nameKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SortPill(
          key: recentKey,
          label: 'Recent',
          selected: value == MutandeListSort.recent,
          onTap: () => onChanged(MutandeListSort.recent),
        ),
        const SizedBox(width: 4),
        _SortPill(
          key: nameKey,
          label: 'Name',
          selected: value == MutandeListSort.name,
          onTap: () => onChanged(MutandeListSort.name),
        ),
      ],
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MutandeMotion.of(context, MutandeMotion.hover),
        curve: MutandeMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? MutandeColors.stone100 : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? MutandeColors.stone200 : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? MutandeColors.stone800 : MutandeColors.stone500,
          ),
        ),
      ),
    );
  }
}

/// Labeled stadium matching [HomeChromeIconButton] height, padding, and radius.
class HomeChromeLabelPill extends StatelessWidget {
  const HomeChromeLabelPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = selected ? MutandeColors.stone50 : MutandeColors.stone600;
    final labelText = Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MutandeMotion.of(context, MutandeMotion.hover),
        curve: MutandeMotion.ease,
        height: HomeChrome.thumbHeight,
        padding: const EdgeInsets.symmetric(horizontal: HomeChrome.thumbPadX),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? MutandeColors.stone800 : HomeChrome.muteFill,
          borderRadius: HomeChrome.thumbStadium,
        ),
        child: icon == null
            ? labelText
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: HomeChrome.iconSize, color: color),
                  const SizedBox(width: 5),
                  labelText,
                ],
              ),
      ),
    );
  }
}

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
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return HomeChromePill(
      child: _ChromeIconHit(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        badge: badge,
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
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int? badge;

  @override
  State<_ChromeIconHit> createState() => _ChromeIconHitState();
}

class _ChromeBadge extends StatelessWidget {
  const _ChromeBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MutandeColors.bronze,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MutandeColors.stone50, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
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
            child: SizedBox(
              width: HomeChrome.iconSize + HomeChrome.thumbPadX * 2,
              height: HomeChrome.thumbHeight,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    widget.icon,
                    size: 16,
                    color: _hover
                        ? MutandeColors.stone600
                        : HomeChrome.muteForeground,
                  ),
                  if (widget.badge != null && widget.badge! > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _ChromeBadge(count: widget.badge!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
