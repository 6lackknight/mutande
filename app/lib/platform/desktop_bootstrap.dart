import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../services/tray_controller.dart';

/// Initializes window_manager + tray (+ macos_ui chrome on macOS).
///
/// No-op on web (keeps `flutter test` free of platform channels).
Future<TrayController?> bootstrapDesktopShell() async {
  if (kIsWeb) return null;
  if (!Platform.isMacOS && !Platform.isWindows) return null;

  await windowManager.ensureInitialized();

  if (Platform.isMacOS) {
    // Transparent titlebar / full-size content for macos_ui shell.
    const macosChrome = MacosWindowUtilsConfig(
      toolbarStyle: NSWindowToolbarStyle.unified,
      enableFullSizeContentView: true,
      makeTitlebarTransparent: true,
      hideTitle: true,
    );
    await macosChrome.apply();
  }

  final windowOptions = WindowOptions(
    size: Platform.isWindows ? const Size(960, 720) : const Size(1088, 720),
    minimumSize: const Size(816, 540),
    center: true,
    skipTaskbar: Platform.isMacOS,
    title: 'mutande',
  );

  final tray = TrayController();
  // Start tray immediately so health polling runs across hot restart
  // (waitUntilReadyToShow may not re-fire when the window already exists).
  await tray.start();

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(true);
    }
    await windowManager.show();
    await windowManager.focus();
  });

  return tray;
}
