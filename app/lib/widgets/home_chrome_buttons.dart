import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_chrome_strip.dart';

/// Shared filled / outlined onboarding CTAs.
///
/// Taller than the titlebar *thumb* (34). Desktop CTA height is 48; stadium
/// radius is `height / 2`. Tab chips are unchanged.
abstract final class HomeChromeButtons {
  static const height = 48.0;
  static const iconSize = 20.0;
  static final radius = BorderRadius.circular(height / 2);

  static const _label = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    letterSpacing: -0.1,
  );

  static ButtonStyle get filled => FilledButton.styleFrom(
    backgroundColor: MutandeColors.stone800,
    foregroundColor: MutandeColors.stone50,
    disabledBackgroundColor: MutandeColors.stone200,
    disabledForegroundColor: MutandeColors.stone500,
    minimumSize: const Size(HomeChrome.controlMinWidth, height),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    elevation: 0,
    shadowColor: const Color(0x00000000),
    shape: RoundedRectangleBorder(borderRadius: radius),
    textStyle: _label,
    iconSize: iconSize,
  );

  static ButtonStyle get outlined => OutlinedButton.styleFrom(
    foregroundColor: MutandeColors.stone800,
    disabledForegroundColor: MutandeColors.stone400,
    backgroundColor: const Color(0x00000000),
    minimumSize: const Size(HomeChrome.controlMinWidth, height),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    side: const BorderSide(color: MutandeColors.stone200),
    shape: RoundedRectangleBorder(borderRadius: radius),
    textStyle: _label,
    iconSize: iconSize,
  );

  /// Apply [filled] / [outlined] to descendant Material buttons.
  static Widget theme({required Widget child}) {
    return FilledButtonTheme(
      data: FilledButtonThemeData(style: filled),
      child: OutlinedButtonTheme(
        data: OutlinedButtonThemeData(style: outlined),
        child: child,
      ),
    );
  }
}
