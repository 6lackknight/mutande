import 'dart:async';
import 'dart:convert';

import 'package:app/config/app_config.dart';
import 'package:app/screens/onboarding_flow_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/first_run_store.dart';
import 'package:app/services/host_link_store.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/ai_host_icon.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:app/widgets/onboarding_address_rail.dart';
import 'package:app/widgets/onboarding_chrome.dart';
import 'package:app/widgets/thread_skeletons.dart';
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
          'display_name': 'Tawanda Brandon',
          'avatar_url': 'https://cdn.example.test/t.jpg',
        });
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {
              'handle': 'orinea@tbhco',
              'kind': 'org',
              'display_name': 'Orinea',
              'avatar_url': 'https://cdn.example.test/o.jpg',
            },
            {
              'handle': 'tawandadev@tbhco',
              'kind': 'org',
              'display_name': 'Tawanda Dev',
              'avatar_url': 'https://cdn.example.test/d.jpg',
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
    expect(find.text('Tawanda Dev'), findsOneWidget);
    expect(find.text('tawandadev@tbhco'), findsOneWidget);
    expect(find.byType(PersonAvatar), findsNWidgets(3));
    final avatars = tester
        .widgetList<PersonAvatar>(find.byType(PersonAvatar))
        .toList();
    expect(avatars[0].isSelf, isTrue);
    expect(avatars[0].url, 'https://cdn.example.test/t.jpg');
    expect(avatars[1].url, 'https://cdn.example.test/o.jpg');
    expect(avatars[2].url, 'https://cdn.example.test/d.jpg');
    expect(find.text('Two teammates can already reach you.'), findsOneWidget);
  });

  testWidgets('team roster shows known host marks as a stack', (
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
            },
            {'handle': 'orinea@tbhco', 'kind': 'org', 'display_name': 'Orinea'},
          ],
        });
      }
      if (method == 'list_agents') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        final handle = params['handle'] as String?;
        if (handle == 'orinea@tbhco') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'o1', 'slug': 'cursor'},
              {'id': 'o2', 'slug': 'claude'},
            ],
          });
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 's1', 'slug': 'cursor'},
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
    await _pumpUntil(tester, find.byType(AiHostIcon));
    expect(find.byType(AiHostIcon), findsNWidgets(3));
  });

  testWidgets('team roster loading keeps onboarding chrome', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final gate = Completer<void>();
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
        await gate.future;
        return _rpcOk(body['id'], {
          'contacts': [
            {
              'handle': 'tawanda@tbhco',
              'kind': 'org',
              'display_name': 'Tawanda Brandon',
            },
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: OnboardingFlowScreen(
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
      ),
    );
    await tester.pump();
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Your team.'), findsOneWidget);
    expect(find.byType(OnboardingRosterSkeleton), findsOneWidget);
    expect(find.text('Tawanda Brandon'), findsNothing);

    gate.complete();
    await _pumpUntil(tester, find.text('Tawanda Brandon'));
    expect(find.byType(OnboardingRosterSkeleton), findsNothing);
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Tawanda Brandon'), findsOneWidget);
  });

  testWidgets('connect host loading keeps onboarding chrome', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final gate = Completer<void>();
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
      if (method == 'detect_ai_hosts') {
        await gate.future;
        return _rpcOk(body['id'], {
          'hosts': [
            {'host': 'cursor', 'installed': true, 'config_present': false},
          ],
        });
      }
      if (method == 'list_agents') {
        await gate.future;
        return _rpcOk(body['id'], {'agents': <Object?>[]});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: OnboardingFlowScreen(
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
            initialStep: OnboardingStep.connect,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Pick a host to connect.'), findsOneWidget);
    expect(find.byType(OnboardingHostSkeleton), findsOneWidget);

    gate.complete();
    await _pumpUntil(tester, find.text('Cursor'));
    expect(find.byType(OnboardingHostSkeleton), findsNothing);
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Pick a host to connect.'), findsOneWidget);
    expect(find.text('ChatGPT'), findsNWidgets(2));
    expect(find.text('Claude'), findsNWidgets(2));
    expect(find.text('ChatGPT Desktop'), findsNothing);
    expect(find.text('ChatGPT Web'), findsNothing);
    expect(find.text('Claude Web'), findsNothing);
  });

  testWidgets('tapping ChatGPT Web opens the connector mini-flow', (
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
          'handle': 'alice@acme',
          'hub_url': 'http://localhost:8000',
        });
      }
      if (method == 'detect_ai_hosts') {
        return _rpcOk(body['id'], {
          'hosts': [
            {'host': 'cursor', 'installed': true, 'config_present': false},
          ],
        });
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {'agents': <Object?>[]});
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
            handle: 'alice@acme',
            hubUrl: 'http://localhost:8000',
          ),
          initialStep: OnboardingStep.connect,
        ),
      ),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('chatgpt-web')));
    await tester.tap(find.byKey(const ValueKey('chatgpt-web')));
    await tester.pumpAndSettle();
    expect(find.text('Add mutande in ChatGPT.'), findsOneWidget);
    expect(find.text('I’ve added the connector'), findsOneWidget);
    expect(find.textContaining('mcp.mutande.online'), findsOneWidget);
  });

  testWidgets('one host does not unlock Continue to handoff', (
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
          'handle': 'alice@acme',
          'hub_url': 'http://localhost:8000',
        });
      }
      if (method == 'detect_ai_hosts') {
        return _rpcOk(body['id'], {
          'hosts': [
            {'host': 'cursor', 'installed': true, 'config_present': true},
            {'host': 'claude', 'installed': true, 'config_present': false},
          ],
        });
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor'},
          ],
        });
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'alice@acme', 'kind': 'org'},
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
            handle: 'alice@acme',
            hubUrl: 'http://localhost:8000',
          ),
          initialStep: OnboardingStep.connect,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      find.textContaining('A handoff needs a second host'),
    );
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Invite on the web'), findsOneWidget);
  });

  testWidgets('two own agents unlock Continue to handoff', (
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
          'handle': 'alice@acme',
          'hub_url': 'http://localhost:8000',
        });
      }
      if (method == 'detect_ai_hosts') {
        return _rpcOk(body['id'], {
          'hosts': [
            {'host': 'cursor', 'installed': true, 'config_present': true},
            {'host': 'claude', 'installed': true, 'config_present': true},
          ],
        });
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor'},
            {'id': 'a2', 'slug': 'claude'},
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
            handle: 'alice@acme',
            hubUrl: 'http://localhost:8000',
          ),
          initialStep: OnboardingStep.connect,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Continue'));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Make default'), findsNothing);
    expect(find.text('Default'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('claude')));
    await tester.pump();
    expect(find.text('Make default'), findsOneWidget);
    expect(find.text('Default'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chatgpt-web')));
    await tester.pumpAndSettle();
    expect(find.text('Add mutande in ChatGPT.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(
      find.text('Host link was cancelled. Pick a host to continue.'),
      findsNothing,
    );
  });
}
