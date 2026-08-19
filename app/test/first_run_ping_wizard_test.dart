import 'dart:async';
import 'dart:convert';

import 'package:app/screens/first_run_ping_wizard.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/first_run_store.dart';
import 'package:app/services/host_composer_launch.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/onboarding_address_rail.dart';
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

Future<void> _pumpWizard(
  WidgetTester tester, {
  required FirstRunPingWizard child,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: child,
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Open Cursor prefills then waits', (tester) async {
    var openedPrompt = '';
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _rpcOk(body['id'], {'threads': <Object>[]});
    });
    final store = FirstRunStore.memory(notificationsComplete: true)
      ..loadMemorySync();

    await _pumpWizard(
      tester,
      child: FirstRunPingWizard(
        daemon: daemon,
        firstRunStore: store,
        address: const OnboardingAddress(
          name: 'alice',
          org: 'acme',
          agent: 'cursor',
        ),
        target: '@claude',
        preview: PingPreview.copy,
        openComposer: ({required slug, required prompt}) async {
          openedPrompt = prompt;
          expect(slug, 'cursor');
          return HostComposerOpenResult.prefilled;
        },
        onComplete: (_) {},
      ),
    );

    expect(find.text('Open this in Cursor.'), findsOneWidget);
    expect(find.text('Open Cursor'), findsOneWidget);
    expect(find.text('I’ve pasted it — wait for the reply'), findsOneWidget);

    await tester.ensureVisible(find.text('Open Cursor'));
    await tester.tap(find.widgetWithText(FilledButton, 'Open Cursor'));
    await tester.pump();

    expect(openedPrompt, FirstRunPingWizard.promptFor('@claude'));
    expect(find.text('Waiting for their handshake…'), findsOneWidget);
  });

  testWidgets('paste fallback still waits without opening', (tester) async {
    var opened = false;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _rpcOk(body['id'], {'threads': <Object>[]});
    });
    final store = FirstRunStore.memory(notificationsComplete: true)
      ..loadMemorySync();

    await _pumpWizard(
      tester,
      child: FirstRunPingWizard(
        daemon: daemon,
        firstRunStore: store,
        address: const OnboardingAddress(
          name: 'alice',
          org: 'acme',
          agent: 'cursor',
        ),
        target: '@claude',
        preview: PingPreview.copy,
        openComposer: ({required slug, required prompt}) async {
          opened = true;
          return HostComposerOpenResult.prefilled;
        },
        onComplete: (_) {},
      ),
    );
    await tester.ensureVisible(
      find.text('I’ve pasted it — wait for the reply'),
    );
    await tester.tap(find.text('I’ve pasted it — wait for the reply'));
    await tester.pump();

    expect(opened, isFalse);
    expect(find.text('Waiting for their handshake…'), findsOneWidget);
  });

  testWidgets('wait poll timeout stays quiet and keeps watching', (
    tester,
  ) async {
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _rpcOk(body['id'], {'threads': <Object>[]});
      }),
      httpToken: 'test-token',
      requestTimeout: const Duration(milliseconds: 20),
    );
    final store = FirstRunStore.memory(notificationsComplete: true)
      ..loadMemorySync();

    await _pumpWizard(
      tester,
      child: FirstRunPingWizard(
        daemon: daemon,
        firstRunStore: store,
        address: const OnboardingAddress(
          name: 'alice',
          org: 'acme',
          agent: 'cursor',
        ),
        target: '@chatgpt',
        preview: PingPreview.copy,
        openComposer: ({required slug, required prompt}) async {
          return HostComposerOpenResult.prefilled;
        },
        onComplete: (_) {},
      ),
    );
    await tester.ensureVisible(
      find.text('I’ve pasted it — wait for the reply'),
    );
    await tester.tap(find.text('I’ve pasted it — wait for the reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('TimeoutException'), findsNothing);
    expect(find.text('Waiting for their handshake…'), findsOneWidget);
  });
}
