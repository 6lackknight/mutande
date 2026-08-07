import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'platform/desktop_bootstrap.dart';
import 'services/core_sidecar.dart';

Future<void> main() async {
  final config = AppConfig.fromEnvironment();
  // `--dart-define=SENTRY_SMOKE=true` (or `1`) forces a GlitchTip ping.
  const smokeFlag = String.fromEnvironment('SENTRY_SMOKE');
  const smoke = smokeFlag == 'true' || smokeFlag == '1';

  await SentryFlutter.init(
    (options) {
      options.dsn = config.sentryDsn;
      // GlitchTip: keep traces light; sessions unsupported.
      options.tracesSampleRate = smoke ? 1.0 : 0.01;
      options.enableAutoSessionTracking = false;
      options.sendDefaultPii = false;
      if (smoke) {
        options.debug = true;
      }
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      // `--dart-define=APP_VERSION=` wins; otherwise pubspec via package_info.
      const definedVersion = String.fromEnvironment('APP_VERSION');
      final appVersion = definedVersion.isNotEmpty
          ? definedVersion
          : (await PackageInfo.fromPlatform()).version;

      await Sentry.configureScope((scope) {
        scope.setTag('app.version', appVersion);
      });

      final sidecar = CoreSidecar(expectedVersion: appVersion);
      final tray = await bootstrapDesktopShell();
      tray?.attachSidecar(sidecar);

      // Paint the welcome splash immediately — do not block on Keychain /
      // mutande-core health (can take tens of seconds while the user authorizes).
      runApp(
        MutandeApp(
          config: config,
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
        unawaited(() async {
          if (smoke) {
            final transaction = Sentry.startTransaction(
              'glitchtip.smoke',
              'smoke',
              bindToScope: true,
            );
            await Sentry.captureMessage(
              'mutande GlitchTip smoke ($appVersion)',
              level: SentryLevel.info,
            );
            await transaction.finish(status: const SpanStatus.ok());
            // Give HTTP transport time to deliver before close.
            await Future<void>.delayed(const Duration(seconds: 6));
            await Sentry.close();
            // ignore: avoid_print
            print('SENTRY_SMOKE: message + transaction flushed');
            exit(0);
          }
          await sidecar.start();
        }());
      });
    },
  );
}
