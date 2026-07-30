import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'platform/desktop_bootstrap.dart';
import 'services/core_sidecar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sidecar = CoreSidecar();
  // Start bundled mutande-core before UI talks to the daemon.
  // Failures surface via DaemonErrorScreen / tray "Daemon: down".
  await sidecar.start();

  final tray = await bootstrapDesktopShell();
  tray?.attachSidecar(sidecar);

  // `--dart-define=APP_VERSION=` wins; otherwise pubspec via package_info.
  const definedVersion = String.fromEnvironment('APP_VERSION');
  final appVersion = definedVersion.isNotEmpty
      ? definedVersion
      : (await PackageInfo.fromPlatform()).version;

  runApp(
    MutandeApp(
      config: AppConfig.fromEnvironment(),
      appVersion: appVersion,
      onRestartCourier: () async {
        final result = await sidecar.restart();
        if (result.ok || result.stillStarting) return null;
        return result.error ?? 'Could not restart mutande-core';
      },
    ),
  );
}
