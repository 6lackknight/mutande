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
    expect(find.text('I’ve pasted it'), findsOneWidget);

    await tester.ensureVisible(find.text('Open Cursor'));
    await tester.tap(find.widgetWithText(FilledButton, 'Open Cursor'));
    await tester.pump();

    expect(openedPrompt, FirstRunPingWizard.promptFor('@claude'));
    expect(find.text('Open this in Claude.'), findsOneWidget);
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
    await tester.ensureVisible(find.text('I’ve pasted it'));
    await tester.tap(find.text('I’ve pasted it'));
    await tester.pump();

    expect(opened, isFalse);
    expect(find.text('Open this in Claude.'), findsOneWidget);
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
    await tester.ensureVisible(find.text('I’ve pasted it'));
    await tester.tap(find.text('I’ve pasted it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('TimeoutException'), findsNothing);
    expect(find.text('Open this in ChatGPT.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('handshake reply shows the thread and Finish', (tester) async {
    var completed = false;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {
          'threads': [
            {
              'id': 't1',
              'kind': 'direct',
              'status': 'open',
              'from': 'alice@acme/cursor',
              'audience': 'alice@acme/claude',
              'reply_count': 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });
      }
      if (method == 'get_thread') {
        return _rpcOk(body['id'], {
          'thread': {
            'id': 't1',
            'kind': 'direct',
            'status': 'open',
            'from': 'alice@acme/cursor',
            'audience': 'alice@acme/claude',
          },
          'messages': [
            {
              'id': 'm1',
              'from_handle': 'alice@acme/cursor',
              'created_at': '2026-08-19T10:00:00Z',
              'bundle': {
                'subject': 'Handshake',
                'notes': 'Hi — introduce yourself on mutande?',
              },
            },
            {
              'id': 'm2',
              'from_handle': 'alice@acme/claude',
              'created_at': '2026-08-19T10:00:08Z',
              'parent_message_id': 'm1',
              'bundle': {
                'notes': 'I’m Claude. Ask me about shipping.',
                'handshake': {'host': 'claude'},
              },
            },
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
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
        openComposer: ({required slug, required prompt}) async {
          return HostComposerOpenResult.prefilled;
        },
        onComplete: (_) => completed = true,
      ),
    );
    await tester.ensureVisible(find.text('I’ve pasted it'));
    await tester.tap(find.text('I’ve pasted it'));
    await tester.pump();
    await tester.pump();

    expect(find.text('they introduced themselves.'), findsOneWidget);
    expect(find.text('I’m Claude. Ask me about shipping.'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    expect(completed, isFalse);
    expect(store.pingComplete, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pump();

    expect(completed, isTrue);
    expect(store.pingComplete, isTrue);
  });

  testWidgets('debug waiting still polls through to Finish', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {
          'threads': [
            {
              'id': 't1',
              'kind': 'direct',
              'status': 'open',
              'from': 'alice@acme/cursor',
              'audience': 'alice@acme/claude',
              'reply_count': 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });
      }
      if (method == 'get_thread') {
        return _rpcOk(body['id'], {
          'thread': {
            'id': 't1',
            'kind': 'direct',
            'status': 'open',
            'from': 'alice@acme/cursor',
            'audience': 'alice@acme/claude',
          },
          'messages': [
            {
              'id': 'm1',
              'from_handle': 'alice@acme/cursor',
              'created_at': '2026-08-19T10:00:00Z',
              'bundle': {'notes': 'Please /handshake'},
            },
            {
              'id': 'm2',
              'from_handle': 'alice@acme/claude',
              'created_at': '2026-08-19T10:00:08Z',
              'parent_message_id': 'm1',
              'bundle': {
                'notes': 'I’m Claude.',
                'handshake': {'host': 'claude'},
              },
            },
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
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
        preview: PingPreview.waiting,
        onComplete: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Finish'), findsOneWidget);
    expect(store.pingComplete, isFalse);
  });

  testWidgets('teammate step asks the human, not a second host', (
    tester,
  ) async {
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
        target: 'orinea@tbhco',
        preview: PingPreview.copy,
        openComposer: ({required slug, required prompt}) async {
          return HostComposerOpenResult.prefilled;
        },
        onComplete: (_) {},
      ),
    );
    await tester.tap(find.text('I’ve pasted it'));
    await tester.pump();

    expect(find.text('Ask orinea@tbhco to reply.'), findsOneWidget);
    expect(find.text('Open Claude'), findsNothing);
  });

  testWidgets('timeout Keep waiting watches the same thread', (tester) async {
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
        preview: PingPreview.timeout,
        onComplete: (_) {},
      ),
    );

    expect(find.text('Still waiting for a reply'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Keep waiting'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Keep waiting'));
    await tester.pump();

    expect(find.text('Open this in Claude.'), findsOneWidget);
    expect(find.text('Still waiting for a reply'), findsNothing);
  });

  testWidgets('timeout Start over returns to the prompt', (tester) async {
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
        preview: PingPreview.timeout,
        onComplete: (_) {},
      ),
    );

    await tester.tap(find.text('Start over'));
    await tester.pump();

    expect(find.text('Open this in Cursor.'), findsOneWidget);
    expect(find.text('Still waiting for a reply'), findsNothing);
  });
}
