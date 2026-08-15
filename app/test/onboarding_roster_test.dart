import 'dart:async';
import 'dart:convert';

import 'package:app/config/app_config.dart';
import 'package:app/screens/onboarding_flow_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/first_run_store.dart';
import 'package:app/services/host_link_store.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:app/widgets/onboarding_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _rpcOk(Object? id, Object result) {
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

DaemonClient _mockDaemon(
  FutureOr<http.Response> Function(http.Request) handler,
) {
  return DaemonClient(
    httpClient: MockClient((request) async => handler(request)),
    httpToken: 'test-token',
    requestTimeout: const Duration(seconds: 2),
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('team roster shows avatar, name, handle, and you marker', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'get_status') {
        return _rpcOk(body['id'], {
          'configured': true,
          'signed_in': true,
          'handle': 'tawanda@tbhco',
          'hub_url': 'http://localhost:8000',
        });
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {
              'handle': 'tawanda@tbhco',
              'kind': 'org',
              'display_name': 'Tawanda Brandon',
              'avatar_url': 'https://cdn.example.test/t.jpg',
            },
            {
              'handle': 'orinea@tbhco',
              'kind': 'org',
              'display_name': 'Orinea',
            },
            {
              'handle': 'tawandadev@tbhco',
              'kind': 'org',
            },
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: OnboardingFlowScreen(
          config: const AppConfig(hubUrl: 'http://localhost:8000'),
          daemon: daemon,
          firstRunStore: FirstRunStore.memory(),
          hostLinkStore: HostLinkStore.memory(),
          onComplete: (_, _) {},
          initialStatus: const DaemonStatusResult(
            configured: true,
            signedIn: true,
            handle: 'tawanda@tbhco',
            hubUrl: 'http://localhost:8000',
          ),
          initialStep: OnboardingStep.team,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Tawanda Brandon'));

    expect(find.text('Tawanda Brandon'), findsOneWidget);
    expect(find.text('tawanda@tbhco'), findsWidgets);
    expect(find.text('you'), findsOneWidget);
    expect(find.text('Orinea'), findsOneWidget);
    expect(find.text('orinea@tbhco'), findsOneWidget);
    expect(find.text('Tawandadev'), findsOneWidget);
    expect(find.text('tawandadev@tbhco'), findsOneWidget);
    expect(find.byType(PersonAvatar), findsNWidgets(3));
    expect(find.text('Two teammates can already reach you.'), findsOneWidget);
  });
}
