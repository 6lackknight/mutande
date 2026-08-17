import 'dart:convert';
import 'dart:io' show Platform;

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
  });
}
