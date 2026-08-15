import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_chrome_buttons.dart';
import 'thinking_orb.dart';

/// Primary control that morphs into the thinking orb while [loading].
class MorphingOrbButton extends StatelessWidget {
  const MorphingOrbButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
    this.loadingLabel = 'Working…',
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final String loadingLabel;

  static const double _restH = HomeChromeButtons.height;
  static const double _orb = 64; // ThinkingOrbSize.panel

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 340);
    const curve = Curves.easeOutCubic;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullW = constraints.maxWidth;
        return SizedBox(
          // Reserve orb height so layout doesn't jump when morphing up.
          height: _orb,
          width: fullW,
          child: Align(
            alignment: Alignment.center,
            child: Semantics(
              button: true,
              enabled: !loading && onPressed != null,
              label: loading ? loadingLabel : label,
              child: AnimatedContainer(
                duration: duration,
                curve: curve,
                width: loading ? _orb : fullW,
                height: loading ? _orb : _restH,
                decoration: BoxDecoration(
                  color: loading
                      ? Colors.transparent
                      : (onPressed == null
                            ? MutandeColors.stone200
                            : MutandeColors.stone800),
                  borderRadius: loading
                      ? BorderRadius.circular(_orb / 2)
                      : HomeChromeButtons.radius,
                ),
                clipBehavior: Clip.antiAlias,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: curve,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [...previous, ?current],
                    );
                  },
                  transitionBuilder: (child, anim) {
                    return FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: loading
                      ? KeyedSubtree(
                          key: const ValueKey('orb'),
                          child: MutandeOrb.standard(
                            semanticLabel: loadingLabel,
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('label'),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onPressed,
                              borderRadius: HomeChromeButtons.radius,
                              child: SizedBox(
                                width: fullW,
                                height: _restH,
                                child: Center(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: onPressed == null
                                          ? MutandeColors.stone500
                                          : MutandeColors.stone50,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
