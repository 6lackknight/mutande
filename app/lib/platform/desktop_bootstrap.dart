import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/tray_controller.dart';

/// Initializes window_manager + tray for the macOS menu-bar shell.
///
/// No-op outside macOS (keeps `flutter test` free of platform channels).
Future<TrayController?> bootstrapDesktopShell() async {
  if (kIsWeb || !Platform.isMacOS) return null;

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(560, 680),
    center: true,
    skipTaskbar: true,
    title: 'mutande',
  );

  final tray = TrayController();
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.setSkipTaskbar(true);
    await tray.start();
    await windowManager.show();
    await windowManager.focus();
  });

  return tray;
}
