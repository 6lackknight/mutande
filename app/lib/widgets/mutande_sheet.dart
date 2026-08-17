import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_chrome_strip.dart';

/// Top inset for modal chrome under macOS traffic lights — header row only.
EdgeInsets macosModalHeaderPadding(BuildContext context) {
  if (kIsWeb || !Platform.isMacOS) {
    return const EdgeInsets.fromLTRB(20, 0, 12, 0);
  }
  return const EdgeInsets.fromLTRB(
    20,
    HomeChrome.titlebarInset,
    12,
    0,
  );
}

/// Screen rect of the control that opened a sheet.
Rect? mutandeSheetOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Overlay-space alignment so scale grows from [origin], not window center.
Alignment mutandeSheetAlignment(Rect origin, Size screen) {
  if (screen.width <= 0 || screen.height <= 0) return Alignment.center;
  return Alignment(
    ((origin.center.dx / screen.width) * 2 - 1).clamp(-1.0, 1.0),
    ((origin.center.dy / screen.height) * 2 - 1).clamp(-1.0, 1.0),
  );
}

/// macos_ui sheet chrome with 200ms ease-out scale 0.95 + fade from [origin].
///
/// Reduced motion snaps (no scale). Reverse uses the same ease-out.
Future<T?> showMutandeSheet<T>({
  required BuildContext context,
  required Widget child,
  required String barrierLabel,
  Rect? origin,
  double? width,
  double? height,
}) {
  final size = MediaQuery.sizeOf(context);
  final w = width ?? size.width.clamp(360.0, 480.0);
  final h = height ?? (size.height - 72).clamp(400.0, 560.0);
  final reduce = MediaQuery.disableAnimationsOf(context);
  final sheet = MacosSheet(
    child: SizedBox(width: w, height: h, child: child),
  );
  final alignment = (origin != null && !reduce)
      ? mutandeSheetAlignment(origin, size)
      : Alignment.center;

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: const Color(0x660C0A09),
    transitionDuration: reduce ? Duration.zero : MutandeMotion.ui,
    pageBuilder: (ctx, animation, secondary) => sheet,
    transitionBuilder: (ctx, animation, secondary, dialogChild) {
      if (reduce) return dialogChild;
      final curved = CurvedAnimation(
        parent: animation,
        curve: MutandeMotion.easeOut,
        reverseCurve: MutandeMotion.easeOut,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          alignment: alignment,
          child: dialogChild,
        ),
      );
    },
  );
}

/// Full-window modal — fade in, Escape / barrier / caller chrome to dismiss.
Future<T?> showMutandeFullscreen<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String barrierLabel,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: const Color(0x990C0A09),
    transitionDuration: reduce ? Duration.zero : MutandeMotion.ui,
    pageBuilder: (ctx, animation, secondary) => builder(ctx),
    transitionBuilder: (ctx, animation, secondary, dialogChild) {
      if (reduce) return dialogChild;
      final curved = CurvedAnimation(
        parent: animation,
        curve: MutandeMotion.easeOut,
        reverseCurve: MutandeMotion.easeOut,
      );
      return FadeTransition(opacity: curved, child: dialogChild);
    },
  );
}
