import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:app/app.dart';
import 'package:app/config/app_config.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/first_run_store.dart';
import 'package:app/services/update_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('UpdateGateClient', () {
    test('fetchLatest parses desktop-version payload', () async {
      final client = UpdateGateClient(
        webAppUrl: 'https://mutande.online',
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'channel': 'alpha',
              'version': '2.0.2',
              'download_url': 'https://mutande.online/download',
              'mac_arm64_url': 'https://downloads.mutande.online/mutande-alpha.dmg',
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final latest = await client.fetchLatest();
      expect(latest?.version, '2.0.2');
      expect(latest?.channel, 'alpha');
    });

    test('gateTarget returns latest when current is older', () {
      final client = UpdateGateClient(webAppUrl: 'https://mutande.online');
      addTearDown(client.close);

      const latest = DesktopVersionInfo(
        version: '2.0.2',
        channel: 'alpha',
        downloadUrl: 'https://mutande.online/download',
      );

      expect(
        client.gateTarget(currentVersion: '2.0.1+20', latest: latest)?.version,
        '2.0.2',
      );
      expect(
        client.gateTarget(currentVersion: '2.0.2', latest: latest),
        isNull,
      );
    });

    test('fetchLatest prefers windows_version on Windows payloads', () async {
      final client = UpdateGateClient(
        webAppUrl: 'https://mutande.online',
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'channel': 'alpha',
              'version': '2.0.4',
              'windows_version': '2.0.2',
              'download_url': 'https://mutande.online/download',
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final latest = await client.fetchLatest();
      expect(
        DesktopVersionInfo.publishedVersionFromJson({
          'version': '2.0.4',
          'windows_version': '2.0.2',
        }),
        Platform.isWindows ? '2.0.2' : '2.0.4',
      );
      expect(latest?.version, isNotNull);
    });

    test('fetchLatest fails open on non-200', () async {
      final client = UpdateGateClient(
        webAppUrl: 'https://mutande.online',
        httpClient: MockClient((_) async => http.Response('', 503)),
      );
      addTearDown(client.close);

      expect(await client.fetchLatest(), isNull);
    });

    test('fetchLatest fails open on timeout', () async {
      final client = UpdateGateClient(
        webAppUrl: 'https://mutande.online',
        timeout: const Duration(milliseconds: 50),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('', 200);
        }),
      );
      addTearDown(client.close);

      expect(await client.fetchLatest(), isNull);
    });
  });

  MutandeApp _shell({
    String appVersion = '2.0.6',
    UpdateGateClient? updateGate,
  }) {
    return MutandeApp(
      config: const AppConfig(hubUrl: 'http://localhost:8000'),
      appVersion: appVersion,
      updateGate: updateGate,
      welcomeDuration: Duration.zero,
      seedStatus: const DaemonStatusResult(
        configured: true,
        hubUrl: 'http://localhost:8000',
        handle: 'alice@acme',
      ),
      firstRunStore: FirstRunStore.memory(
        connectComplete: true,
        pingComplete: true,
        notificationsComplete: true,
      ),
    );
  }

  group('MutandeApp update gate', () {
    testWidgets('startup is never blocked by a checking screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Checking for updates'), findsNothing);
      expect(find.text('Update required'), findsNothing);
      expect(find.bySemanticsLabel('mutande'), findsOneWidget);
    });

    testWidgets('does not block startup on slow version check', (
      WidgetTester tester,
    ) async {
      final gate = UpdateGateClient(
        webAppUrl: 'https://mutande.online',
        timeout: const Duration(milliseconds: 50),
        httpClient: MockClient(
          (_) => Completer<http.Response>().future,
        ),
      );
      addTearDown(gate.close);

      await tester.pumpWidget(_shell(appVersion: '2.0.5', updateGate: gate));
      await tester.pump();

      expect(find.text('Checking for updates'), findsNothing);
      expect(find.text('Update required'), findsNothing);
      expect(find.bySemanticsLabel('mutande'), findsOneWidget);

      // Background check times out and fails open (inner 50ms + outer +1s).
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Checking for updates'), findsNothing);
      expect(find.text('Update required'), findsNothing);
      expect(find.bySemanticsLabel('mutande'), findsOneWidget);
    });

    testWidgets('shows Update required after background check when behind', (
      WidgetTester tester,
    ) async {
      final gate = _FixedGate(
        const DesktopVersionInfo(
          version: '9.9.9',
          channel: 'alpha',
          downloadUrl: 'https://mutande.online/download',
        ),
      );
      addTearDown(gate.close);

      await tester.pumpWidget(_shell(appVersion: '2.0.5', updateGate: gate));
      await tester.pump();

      expect(find.text('Checking for updates'), findsNothing);

      await tester.pump();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Download update'), findsOneWidget);
    });

    testWidgets('stays in app when published version matches', (
      WidgetTester tester,
    ) async {
      final gate = _FixedGate(
        const DesktopVersionInfo(
          version: '2.0.7',
          channel: 'alpha',
          downloadUrl: 'https://mutande.online/download',
        ),
      );
      addTearDown(gate.close);

      await tester.pumpWidget(_shell(appVersion: '2.0.7', updateGate: gate));
      await tester.pump();
      await tester.pump();

      expect(find.text('Checking for updates'), findsNothing);
      expect(find.text('Update required'), findsNothing);
      expect(find.bySemanticsLabel('mutande'), findsOneWidget);
    });

    test('gateTarget marks newer published alpha as required', () async {
      final gate = UpdateGateClient(
        webAppUrl: 'https://mutande.online',
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'channel': 'alpha',
              'version': '9.9.9',
              'download_url': 'https://mutande.online/download',
            }),
            200,
          );
        }),
      );
      addTearDown(gate.close);

      final latest = await gate.fetchLatest();
      expect(latest, isNotNull);
      expect(
        gate.gateTarget(currentVersion: '2.0.5', latest: latest!)?.version,
        '9.9.9',
      );
    });
  });
}

class _FixedGate extends UpdateGateClient {
  _FixedGate(this.latest)
      : super(
          webAppUrl: 'https://mutande.online',
          httpClient: MockClient((_) async => http.Response('', 500)),
        );

  final DesktopVersionInfo? latest;

  @override
  Future<DesktopVersionInfo?> fetchLatest() async => latest;
}
