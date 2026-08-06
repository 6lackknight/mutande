import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'platform/desktop_bootstrap.dart';
import 'services/core_sidecar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `--dart-define=APP_VERSION=` wins; otherwise pubspec via package_info.
  const definedVersion = String.fromEnvironment('APP_VERSION');
  final appVersion = definedVersion.isNotEmpty
      ? definedVersion
      : (await PackageInfo.fromPlatform()).version;

  final sidecar = CoreSidecar(expectedVersion: appVersion);
  final tray = await bootstrapDesktopShell();
  tray?.attachSidecar(sidecar);

  // Paint the welcome splash immediately — do not block on Keychain /
  // mutande-core health (can take tens of seconds while the user authorizes).
  runApp(
    MutandeApp(
      config: AppConfig.fromEnvironment(),
      appVersion: appVersion,
      onRestartCourier: () async {
        // Kills :3847 listener (stale or current), then spawns bundled
        // Resources/mutande-core. stillStarting = Keychain unlock in progress
        // — do not surface as a hard failure (AGENTS.md 60s wait).
        final result = await sidecar.restart();
        if (result.stillStarting) return null;
        if (result.ok) return null;
        return result.error ?? 'Could not restart mutande-core';
      },
    ),
  );

  // Start bundled mutande-core after the first frame so the UI is visible
  // while the OS Keychain prompt is up. Replaces a stale daemon when its
  // health version ≠ appVersion (old flutter run / prior DMG on :3847).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(sidecar.start());
  });
}
