import 'package:flutter/material.dart';

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

  runApp(
    MutandeApp(
      config: AppConfig.fromEnvironment(),
      onRestartCourier: () async {
        final result = await sidecar.restart();
        if (result.ok || result.stillStarting) return null;
        return result.error ?? 'Could not restart mutande-core';
      },
    ),
  );
}
