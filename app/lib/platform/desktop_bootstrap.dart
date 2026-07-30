import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../services/tray_controller.dart';

/// Initializes window_manager + tray + macos_ui window chrome.
///
/// No-op outside macOS (keeps `flutter test` free of platform channels).
Future<TrayController?> bootstrapDesktopShell() async {
  if (kIsWeb || !Platform.isMacOS) return null;

  await windowManager.ensureInitialized();

  // Transparent titlebar / full-size content for macos_ui shell.
  const macosChrome = MacosWindowUtilsConfig(
    toolbarStyle: NSWindowToolbarStyle.unified,
    enableFullSizeContentView: true,
    makeTitlebarTransparent: true,
    hideTitle: true,
  );
  await macosChrome.apply();

  const windowOptions = WindowOptions(
    size: Size(1088, 720), // ~15% narrower than 1280; height kept
    minimumSize: Size(816, 540),
    center: true,
    skipTaskbar: true,
    title: 'mutande',
  );

  final tray = TrayController();
  // Start tray immediately so health polling runs across hot restart
  // (waitUntilReadyToShow may not re-fire when the window already exists).
  await tray.start();

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.show();
    await windowManager.focus();
  });

  return tray;
}
