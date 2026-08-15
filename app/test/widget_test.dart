import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/app.dart';
import 'package:app/config/app_config.dart';
import 'package:app/screens/agents_screen.dart';
import 'package:app/screens/collab_screen.dart';
import 'package:app/screens/first_run_ping_wizard.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/first_run_store.dart';
import 'package:app/services/host_link_store.dart';

DaemonClient _mockDaemon(
  Future<http.Response> Function(http.Request) handler,
) {
  return DaemonClient(
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'install_skill') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        final host = params['host'] as String? ?? 'cursor';
        return _rpcOk(body['id'], {
          'host': host,
          'ok': true,
          'mode': 'auto',
          'path': '/tmp/.cursor/skills/mutande/SKILL.md',
          'hint': 'Skill ready',
        });
      }
      if (method == 'list_threads') {
        // Inbox watch may call this; default empty unless handler overrides.
        final override = await handler(request);
        final overrideBody = jsonDecode(override.body) as Map<String, dynamic>;
        if (overrideBody['result'] is Map &&
            (overrideBody['result'] as Map).containsKey('threads')) {
          return override;
        }
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_collabs') {
        final override = await handler(request);
        final overrideBody = jsonDecode(override.body) as Map<String, dynamic>;
        if (overrideBody['result'] is Map &&
            (overrideBody['result'] as Map).containsKey('collabs')) {
          return override;
        }
        return _rpcOk(body['id'], {'collabs': []});
      }
      if (method == 'list_contacts' || method == 'list_external_contacts') {
        final override = await handler(request);
        final overrideBody = jsonDecode(override.body) as Map<String, dynamic>;
        if (overrideBody['result'] is Map &&
            (overrideBody['result'] as Map).containsKey('contacts')) {
          return override;
        }
        return _rpcOk(body['id'], {'contacts': []});
      }
      return handler(request);
    }),
    httpToken: 'test-token',
    requestTimeout: const Duration(milliseconds: 200),
  );
}

Future<void> _finishConnectHostFlow(WidgetTester tester) async {
  // Timed pumps — MutandeOrb's ticker never settles under pumpAndSettle.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('Continue').evaluate().isNotEmpty ||
        find.text('Skip for now').evaluate().isNotEmpty ||
        find.text('I’ve added the skill').evaluate().isNotEmpty ||
        find.text('Retry').evaluate().isNotEmpty) {
      break;
    }
  }
  final continueBtn = find.text('Continue');
  if (continueBtn.evaluate().isNotEmpty) {
    await tester.tap(continueBtn.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    return;
  }
  final added = find.text('I’ve added the skill');
  if (added.evaluate().isNotEmpty) {
    await tester.tap(added.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    return;
  }
  final skip = find.text('Skip for now');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

http.Response _rpcOk(Object? id, Map<String, dynamic> result) {
  final body = utf8.encode(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  );
  return http.Response.bytes(
    body,
    200,
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}

Future<void> _tapGraphAgent(WidgetTester tester, String slug) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(slug).hitTestable().evaluate().isNotEmpty) break;
  }
  final node = find.text(slug).hitTestable();
  expect(node, findsWidgets);
  await tester.ensureVisible(node.last);
  await tester.tap(node.last);
  await tester.pumpAndSettle();
}

Future<void> _openNetworkAgents(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final network = find.text('Network');
  expect(network, findsWidgets);
  await tester.tap(network.first);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('network-agents')));
  await tester.pumpAndSettle();
}

Future<void> _openNetworkPeople(WidgetTester tester) async {
  final network = find.text('Network');
  expect(network, findsWidgets);
  await tester.tap(network.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home shell shows threads tab', (WidgetTester tester) async {
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
              'from': 'bob@acme',
              'audience': 'alice@acme',
              'your_status': 'pending',
              'reply_count': 0,
            },
          ],
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('mutande'), findsOneWidget);
    expect(find.text('Threads'), findsWidgets);
    expect(find.text('Collab'), findsWidgets);
    expect(find.text('Network'), findsWidgets);
    expect(find.text('bob@acme'), findsOneWidget);
    expect(find.byTooltip('alice@acme'), findsOneWidget);
    expect(find.text('All'), findsWidgets);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.textContaining('ACTION REQUIRED'), findsNothing);
  });

  testWidgets('mail timeout blocks home with starting screen', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        throw TimeoutException('Future not completed');
      }
      if (method == 'get_status') {
        return _rpcOk(body['id'], {
          'configured': true,
          'hub_url': 'http://localhost:8000',
          'handle': 'alice@acme',
        });
      }
      if (method == 'health') {
        return _rpcOk(body['id'], {
          'ok': true,
          'service': 'mutande-core',
          'version': '0.0.0',
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        firstRunStore:
            FirstRunStore.memory(connectComplete: true, pingComplete: true, notificationsComplete: true),
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Hub is taking too long').evaluate().isNotEmpty) break;
    }

    expect(find.text('Hub is taking too long'), findsOneWidget);
    expect(find.text('Sign in again'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Restart courier'), findsNothing);
    expect(find.text('Threads'), findsNothing);
  });

  testWidgets('settings has Check daemon', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'get_safety_number') {
        return _rpcOk(body['id'], {
          'handle': 'me',
          'fingerprint':
              '11111 22222 33333 44444 55555 66666 77777 88888 99999 00000',
          'uri': 'mutande:safety:me:11111 22222',
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Local courier'), findsOneWidget);
    expect(find.text('Network'), findsWidgets);
    await tester.ensureVisible(find.text('Check daemon'));
    expect(find.text('Check daemon'), findsOneWidget);
    await tester.ensureVisible(find.text('Connect new host'));
    expect(find.text('Connect new host'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('Not linked'), findsAtLeastNWidgets(3));
    expect(find.text('Safety Numbers'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('On this Mac'), findsOneWidget);
    expect(find.text('Standard Professional License'), findsNothing);
  });

  testWidgets('connect AI host via picker shows Linked status', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'get_safety_number') {
        return _rpcOk(body['id'], {
          'handle': 'me',
          'fingerprint': '11111 22222 33333 44444 55555 66666',
          'uri': 'mutande:safety:me:11111 22222',
        });
      }
      if (method == 'connect_host') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        final host = params['host'] as String? ?? 'cursor';
        return _rpcOk(body['id'], {
          'command': '/Users/dev/bin/mutande-core',
          'args': ['mcp'],
          'hosts': [
            {
              'host': host,
              'path': '/Users/dev/.cursor/mcp.json',
              'ok': true,
            },
          ],
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final connect = find.text('Connect new host');
    await tester.ensureVisible(connect);
    await tester.pumpAndSettle();
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.text('Connect AI host'), findsOneWidget);

    await tester.tap(find.text('Cursor').last);
    await tester.pump();
    await _finishConnectHostFlow(tester);

    expect(find.textContaining('Linked Cursor'), findsWidgets);
    expect(find.text('Linked'), findsWidgets);
    expect(find.text('Not linked'), findsAtLeastNWidgets(2));
    expect(find.text('Connected 3 AI hosts'), findsNothing);
    expect(find.text('Details'), findsNothing);
  });

  testWidgets('agents Add opens idle host picker', (WidgetTester tester) async {
    String? connectedHost;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        if (connectedHost == null) {
          return _rpcOk(body['id'], {
            'agents': <Map<String, dynamic>>[],
            'default_agent_id': null,
          });
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': connectedHost},
          ],
          'default_agent_id': 'a1',
        });
      }
      if (method == 'connect_host') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        connectedHost = params['host'] as String? ?? 'cursor';
        return _rpcOk(body['id'], {
          'command': '/Users/dev/bin/mutande-core',
          'args': ['mcp'],
          'hosts': [
            {
              'host': connectedHost,
              'path': '/Users/dev/.cursor/mcp.json',
              'ok': true,
            },
          ],
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await _openNetworkAgents(tester);

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    expect(find.text('Add AI host'), findsOneWidget);
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Claude (Anthropic)'), findsOneWidget);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('Not linked'), findsAtLeastNWidgets(3));

    await tester.tap(find.text('Cursor'));
    await tester.pump();
    await _finishConnectHostFlow(tester);

    expect(connectedHost, 'cursor');
    expect(find.text('Added Cursor'), findsWidgets);
    expect(find.text('cursor'), findsWidgets);
    expect(
      find.text('Connect an AI host in Settings, then return here to Add.'),
      findsNothing,
    );
  });

  testWidgets('settings shows verify UI', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'get_safety_number') {
        return _rpcOk(body['id'], {
          'handle': 'me',
          'fingerprint': '11111 22222 33333 44444 55555 66666 77777 88888 99999 00000 12345 67890',
          'uri': 'mutande:safety:me:11111 22222',
          'pubkey': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        });
      }
      if (method == 'register_device') {
        return _rpcOk(body['id'], {
          'ok': true,
          'pubkey': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Safety Numbers'));
    expect(find.text('Safety Numbers'), findsOneWidget);
    expect(find.text('Compare safety numbers'), findsOneWidget);
    expect(find.text('This device pubkey'), findsOneWidget);
    expect(find.text('Register this device'), findsOneWidget);
    expect(find.text('11111'), findsOneWidget);
    expect(find.text('22222'), findsOneWidget);

    final compare = find.text('Compare safety numbers');
    await tester.ensureVisible(compare);
    await tester.pumpAndSettle();
    await tester.tap(compare);
    await tester.pumpAndSettle();
    expect(find.text('Your number'), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
  });

  testWidgets('onboarding sign-in smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        seedStatus: const DaemonStatusResult(configured: false),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pump(); // splash dismisses after bootstrap post-frame

    expect(find.text('Step 1 of 4 — Sign in'), findsOneWidget);
    expect(find.text('Sign in with Auth0'), findsOneWidget);
  });

  testWidgets('onboarding choose step when signed in', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _rpcOk(body['id'], {
        'configured': false,
        'signed_in': true,
        'needs_onboarding': true,
        'email': 'a@x.com',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        seedStatus: const DaemonStatusResult(
          configured: false,
          signedIn: true,
          needsOnboarding: true,
          email: 'a@x.com',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pump(); // post-frame org re-check

    expect(find.text('Pick the org half of your address.'), findsOneWidget);
    expect(find.text('Create a team'), findsOneWidget);
    expect(find.text('I have an invite'), findsOneWidget);
  });

  testWidgets('web-joined user refreshes past create/join', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _rpcOk(body['id'], {
        'configured': true,
        'signed_in': true,
        'needs_onboarding': false,
        'handle': 'alice@acme',
        'org_id': 'org-1',
        'email': 'a@x.com',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        seedStatus: const DaemonStatusResult(
          configured: false,
          signedIn: true,
          needsOnboarding: true,
          email: 'a@x.com',
        ),
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        hostLinkStore: HostLinkStore.memory(),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Create a team'), findsNothing);
    expect(find.text('I have an invite'), findsNothing);
    expect(find.text('Sign in with Auth0'), findsNothing);
  });

  testWidgets('already onboarded status skips create/join', (WidgetTester tester) async {
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        seedStatus: const DaemonStatusResult(
          configured: true,
          signedIn: true,
          needsOnboarding: false,
          handle: 'alice@acme',
          orgId: 'org-1',
          email: 'a@x.com',
        ),
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        hostLinkStore: HostLinkStore.memory(),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pump();

    expect(find.text('Create a team'), findsNothing);
    expect(find.text('I have an invite'), findsNothing);
    expect(find.text('Sign in with Auth0'), findsNothing);
  });

  testWidgets('daemon transport failure shows error not Join', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      throw Exception('connection refused');
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Waiting for Keychain'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Restart courier'), findsNothing);
    expect(find.text('Sign in with Auth0'), findsNothing);
    expect(find.textContaining('ClientException'), findsNothing);
  });

  testWidgets('daemon error shows restart courier when handler set', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      throw Exception('connection refused');
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
        onRestartCourier: () async => null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restart courier'), findsOneWidget);
  });

  testWidgets('slow get_status with healthy daemon is not unreachable', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'health') {
        return _rpcOk(body['id'], {
          'ok': true,
          'service': 'mutande-core',
          'version': '0.0.0',
        });
      }
      throw Exception('TimeoutException after 0:00:03.000000: Future not completed');
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hub is taking too long'), findsOneWidget);
    expect(find.text('Courier still starting'), findsNothing);
    expect(find.text('Waiting for Keychain'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Restart courier'), findsNothing);
  });

  testWidgets('hub 401 shows sign in not courier starting', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'health') {
        return _rpcOk(body['id'], {
          'ok': true,
          'service': 'mutande-core',
          'version': '0.0.0',
        });
      }
      throw Exception('GET /v1/me for status: hub error 401 Unauthorized');
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
        onRestartCourier: () async => null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('Courier still starting'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Restart courier'), findsNothing);
    expect(find.text('Create a team'), findsNothing);
  });

  testWidgets('error screen Sign in recovers a hub 401', (
    WidgetTester tester,
  ) async {
    var signedIn = false;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'health') {
        return _rpcOk(body['id'], {
          'ok': true,
          'service': 'mutande-core',
          'version': '0.0.0',
        });
      }
      if (method == 'auth_login') {
        signedIn = true;
        return _rpcOk(body['id'], {
          'configured': true,
          'signed_in': true,
          'needs_onboarding': false,
          'handle': 'alice@acme',
          'hub_url': 'http://localhost:8000',
        });
      }
      if (!signedIn) {
        throw Exception('GET /v1/me for status: hub error 401 Unauthorized');
      }
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      return _rpcOk(body['id'], {
        'configured': true,
        'signed_in': true,
        'needs_onboarding': false,
        'handle': 'alice@acme',
        'hub_url': 'http://localhost:8000',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        hostLinkStore: HostLinkStore.memory(),
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in again'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Threads').evaluate().isNotEmpty) break;
    }

    expect(find.text('Sign in again'), findsNothing);
    expect(find.text('Threads'), findsWidgets);
  });

  testWidgets('error screen Sign in failure shows banner and stays', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'health') {
        return _rpcOk(body['id'], {
          'ok': true,
          'service': 'mutande-core',
          'version': '0.0.0',
        });
      }
      if (method == 'auth_login') {
        throw Exception('hub error 401: expired');
      }
      throw Exception('GET /v1/me for status: hub error 401 Unauthorized');
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        welcomeDuration: Duration.zero,
        startupRetryAttempts: 0,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Sign-in was rejected').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.textContaining('Sign-in was rejected'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create a team'), findsNothing);
  });

test('validateHandle and validateHubUrl', () {
    expect(validateHandle('alice@acme'), isNull);
    expect(validateHandle('nope'), isNotNull);
    expect(validateHandle('@acme'), isNotNull);
    expect(validateHubUrl('http://localhost:8000'), isNull);
    expect(validateHubUrl('https://hub.example'), isNull);
    expect(validateHubUrl('not-a-url'), isNotNull);
    expect(validateHubUrl('ftp://x'), isNotNull);
  });

  test('validateAgentSlug matches hub rules', () {
    expect(validateAgentSlug('claude'), isNull);
    expect(validateAgentSlug('a'), isNull);
    expect(validateAgentSlug('default'), isNotNull);
    expect(validateAgentSlug('all'), isNotNull);
    expect(validateAgentSlug('Bad_Case'), isNotNull);
    expect(validateAgentSlug('a' * 33), isNotNull);
    expect(validateAgentSlug('cursor', taken: {'cursor'}), isNotNull);
  });

  test('friendlyAgentsError distinguishes hub vs daemon', () {
    expect(
      friendlyAgentsError('TimeoutException after 0:00:03.000000'),
      contains('hub took too long'),
    );
    expect(friendlyAgentsError('HTTP 404 not found'), contains('hub'));
    expect(
      friendlyAgentsError('Missing HTTP token at ~/.mutande/daemon_http_token'),
      contains('local mutande daemon'),
    );
  });

  test('friendlyDaemonError hides raw TimeoutException', () {
    expect(
      friendlyDaemonError('TimeoutException after 0:00:03.000000: Future not completed',
          what: 'Threads'),
      allOf(contains('took too long'), isNot(contains('TimeoutException'))),
    );
  });

  test('friendlyDaemonError hides ClientException transport dumps', () {
    const raw =
        'ClientException: Connection closed before full header was received, '
        'uri=http://127.0.0.1:3847/rpc';
    expect(
      friendlyDaemonError(raw, what: 'Threads'),
      allOf(
        contains('local mutande daemon'),
        isNot(contains('ClientException')),
        isNot(contains('127.0.0.1')),
        isNot(contains('uri=')),
      ),
    );
  });

  test('friendlyDaemonError splits local daemon vs hub auth', () {
    expect(
      friendlyDaemonError('Missing HTTP token at ~/.mutande/daemon_http_token'),
      contains('local mutande daemon'),
    );
    expect(
      friendlyDaemonError(
        'HTTP 401 unauthorized — check ~/.mutande/daemon_http_token matches the running daemon',
      ),
      contains('local mutande daemon'),
    );
    expect(
      friendlyDaemonError('hub error 401: expired'),
      allOf(contains('Sign-in'), isNot(contains('local mutande daemon'))),
    );
  });

  test('friendlyDaemonError 404 is not a sign-in prompt', () {
    expect(
      friendlyDaemonError(
        'hub error 404 Not Found: {"error":"not_found"}',
        what: 'Create collab',
      ),
      allOf(
        contains("doesn't support collab"),
        isNot(contains('signed in')),
      ),
    );
    expect(
      friendlyDaemonError(
        'hub error 404 Not Found: {"error":"not_found","message":"User not found"}',
        what: 'Create collab',
      ),
      allOf(
        contains('Retry'),
        isNot(contains('signed in')),
      ),
    );
    expect(
      friendlyDaemonError('method not found: create_collab', what: 'Create collab'),
      contains("doesn't support collab"),
    );
  });

  test('ThreadMessageView empty body and answers harden', () {
    const empty = ThreadMessageView(
      id: 'm1',
      fromHandle: 'tawanda@tbhco/claude',
      createdAt: '2026-07-30T00:00:00Z',
    );
    expect(empty.isEmptyBody, isTrue);
    expect(empty.displayBody, 'No message body');

    const withAnswers = ThreadMessageView(
      id: 'm2',
      fromHandle: 'tawanda@tbhco/claude',
      createdAt: '2026-07-30T00:00:00Z',
      answerTexts: ['Tailored CTO CV notes'],
    );
    expect(withAnswers.isEmptyBody, isFalse);
    expect(withAnswers.displayBody, 'Tailored CTO CV notes');

    const withQuestion = ThreadMessageView(
      id: 'm3',
      fromHandle: 'tawanda@tbhco/cursor',
      createdAt: '2026-07-30T00:00:00Z',
      questionPrompts: ['What are the must-haves for a good CTO CV?'],
    );
    expect(withQuestion.isEmptyBody, isFalse);
    expect(withQuestion.displayBody, contains('must-haves'));

    const errored = ThreadMessageView(
      id: 'm4',
      fromHandle: 'tawanda@tbhco/claude',
      createdAt: '2026-07-30T00:00:00Z',
      openError: 'Could not decrypt',
    );
    expect(errored.isEmptyBody, isFalse);
    expect(errored.displayBody, 'Could not decrypt');
  });

  test('ThreadMessageView surfaces attachments and hides stub notes', () {
    const stub = ThreadMessageView(
      id: 'm5',
      fromHandle: 'tawanda@tbhco/cursor',
      createdAt: '2026-08-05T20:09:12.297Z',
      bundleSubject: 'Landing intro sample render',
      bundleNotes:
          'Binary artifact (3127062 bytes); too large to inline in opened bundle.',
      resources: [
        BundleResourceView(
          name: 'landing-intro.mp4',
          mime: 'video/mp4',
        ),
      ],
    );
    expect(stub.isEmptyBody, isFalse);
    expect(stub.displayBody, 'Landing intro sample render');
    expect(stub.displayBody.contains('too large'), isFalse);
    expect(stub.resources.single.isAvailable, isFalse);
    expect(stub.resources.single.isVideo, isTrue);

    const ready = ThreadMessageView(
      id: 'm6',
      fromHandle: 'tawanda@tbhco/cursor',
      createdAt: '2026-08-05T20:09:12.297Z',
      bundleNotes: 'Artifact available on this device: landing-intro.mp4',
      resources: [
        BundleResourceView(
          name: 'landing-intro.mp4',
          mime: 'video/mp4',
          path: '/tmp/landing-intro.mp4',
          size: 3127062,
        ),
      ],
    );
    expect(ready.displayBody, '');
    expect(ready.resources.single.isAvailable, isTrue);
    expect(ready.resources.single.sizeLabel, '3.0 MB');

    const textInline = BundleResourceView(
      name: 'notes.md',
      mime: 'text/markdown',
      content: '# hello',
      size: 7,
    );
    expect(textInline.isText, isTrue);
    expect(textInline.isAvailable, isTrue);

    final hostedPrd = BundleResourceView.fromJson({
      'name': 'mutande-organisations-prd.md',
      'content': '# PRD — Mutande Organizations\n',
    });
    expect(hostedPrd.isText, isTrue);
    expect(hostedPrd.isAvailable, isTrue);
    expect(hostedPrd.mime, 'text/markdown');
    expect(hostedPrd.size, isNotNull);
  });

  testWidgets('agent inspector harden paths', (WidgetTester tester) async {
    String claudeSlug = 'claude';
    String? renamedTo;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a-default', 'slug': 'cursor'},
            {'id': 'a-claude', 'slug': claudeSlug},
          ],
          'default_agent_id': 'a-default',
        });
      }
      if (method == 'rename_agent') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        renamedTo = params['slug'] as String?;
        claudeSlug = renamedTo ?? claudeSlug;
        return _rpcOk(body['id'], {
          'id': params['agent_id'],
          'slug': claudeSlug,
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await _openNetworkAgents(tester);

    await _tapGraphAgent(tester, 'claude');

    expect(find.text('Address'), findsOneWidget);
    expect(find.text('alice@acme/claude'), findsOneWidget);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.text('Not linked'), findsWidgets);
    expect(find.text('Connect host'), findsOneWidget);
    expect(find.text('View threads'), findsNothing);
    expect(find.text('Set as default'), findsNothing);
    expect(find.text('Disconnect host'), findsNothing);

    await tester.tap(find.text('Rename slug'));
    await tester.pumpAndSettle();
    expect(find.text('Rename slug'), findsWidgets);
    final renameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(renameField, 'default');
    await tester.pumpAndSettle();
    expect(find.text('"default" is reserved.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );

    await tester.enterText(renameField, 'codex');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(renamedTo, 'codex');
  });

  testWidgets('agent inspector Connect host links MCP', (
    WidgetTester tester,
  ) async {
    String? connectedHost;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a-default', 'slug': 'cursor'},
            {'id': 'a-claude', 'slug': 'claude'},
          ],
          'default_agent_id': 'a-default',
        });
      }
      if (method == 'connect_host') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        connectedHost = params['host'] as String? ?? 'claude';
        return _rpcOk(body['id'], {
          'command': '/Users/dev/bin/mutande-core',
          'args': ['mcp'],
          'hosts': [
            {
              'host': connectedHost,
              'path': '/Users/dev/Library/Application Support/Claude/claude_desktop_config.json',
              'ok': true,
            },
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    final hostLinks = HostLinkStore.memory();
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: hostLinks,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await _openNetworkAgents(tester);
    await _tapGraphAgent(tester, 'claude');

    expect(find.text('Connect host'), findsOneWidget);
    await tester.tap(find.text('Connect host'));
    await tester.pump();
    await _finishConnectHostFlow(tester);
    expect(connectedHost, 'claude');
    expect(find.textContaining('Linked Claude'), findsWidgets);

    await _tapGraphAgent(tester, 'claude');
    expect(find.text('Linked'), findsWidgets);
    expect(find.text('View threads'), findsOneWidget);
    expect(find.text('Set as default'), findsOneWidget);
    expect(find.text('Disconnect host'), findsOneWidget);
    expect(find.text('Connect host'), findsNothing);
  });

  testWidgets('agent inspector linked shows Set as default', (
    WidgetTester tester,
  ) async {
    String? setDefaultId;
    final hostLinks = HostLinkStore.memory();
    await hostLinks.record(
      const HostWriteResult(
        host: 'claude',
        path: '/tmp/claude.json',
        ok: true,
      ),
    );
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a-default', 'slug': 'cursor'},
            {'id': 'a-claude', 'slug': 'claude'},
          ],
          'default_agent_id': 'a-default',
        });
      }
      if (method == 'set_default_agent') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        setDefaultId = params['agent_id'] as String?;
        return _rpcOk(body['id'], {
          'id': setDefaultId,
          'slug': 'claude',
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: hostLinks,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await _openNetworkAgents(tester);
    await _tapGraphAgent(tester, 'claude');

    expect(find.text('View threads'), findsOneWidget);
    expect(find.text('Set as default'), findsOneWidget);
    await tester.ensureVisible(find.text('Set as default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as default'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(setDefaultId, 'a-claude');
  });

  testWidgets('agent inspector shows Default for linked primary', (
    WidgetTester tester,
  ) async {
    final hostLinks = HostLinkStore.memory();
    await hostLinks.record(
      const HostWriteResult(
        host: 'cursor',
        path: '/tmp/cursor.json',
        ok: true,
      ),
    );
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor'},
          ],
          'default_agent_id': 'a1',
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: hostLinks,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await _openNetworkAgents(tester);
    await _tapGraphAgent(tester, 'cursor');

    expect(find.text('alice@acme'), findsWidgets);
    expect(find.text('alice@acme/cursor'), findsNothing);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Set as default'), findsNothing);
    expect(find.text('Linked'), findsWidgets);
    expect(find.text('Connect host'), findsNothing);
  });

  testWidgets('contacts tab loads hub list and solo invite', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': '@all@acme', 'pubkey': null, 'devices': []},
          ],
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await _openNetworkPeople(tester);
    await tester.pumpAndSettle();

    expect(find.text('you'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice@acme'), findsWidgets);
    expect(find.text('@all@acme'), findsOneWidget);
    expect(find.text('Broadcast to each member’s default agent'), findsOneWidget);
    expect(find.text('You’re the only member of acme'), findsOneWidget);
    expect(find.text('Invite teammates'), findsOneWidget);
  });

  testWidgets('contacts tab shows teammate display name', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': '@all@acme', 'pubkey': null, 'devices': []},
            {
              'handle': 'alice@acme',
              'kind': 'org',
              'display_name': 'Alice Acme',
              'devices': [],
            },
            {
              'handle': 'bob@acme',
              'kind': 'org',
              'display_name': 'Bob Builder',
              'devices': [],
            },
          ],
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await _openNetworkPeople(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice Acme'), findsOneWidget);
    expect(find.text('you'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('bob@acme'), findsOneWidget);
    expect(find.text('You’re the only member of acme'), findsNothing);
  });

  testWidgets('first-run connect gate shows when incomplete', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'alice@acme', 'kind': 'member'},
          ],
        });
      }
      if (method == 'detect_ai_hosts') {
        return _rpcOk(body['id'], {
          'hosts': [
            {'host': 'cursor', 'installed': true, 'config_present': false},
            {'host': 'claude', 'installed': false, 'config_present': false},
            {'host': 'chatgpt', 'installed': false, 'config_present': false},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        firstRunStore: FirstRunStore.memory(),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 — Your team'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 — Connect a host'), findsOneWidget);
    expect(find.text('Pick a host to connect.'), findsOneWidget);
    // The verb rides on the row that still needs it.
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    // Undetected hosts collapse to one line instead of dead tiles.
    expect(
      find.textContaining('installed on this Mac'),
      findsOneWidget,
    );
    expect(find.text('Threads'), findsNothing);
  });

  testWidgets('first-run ping wizard shows after connect complete', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          notificationsComplete: true,
        ),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paste this into your connected host.'), findsOneWidget);
    expect(find.text(FirstRunPingWizard.prompt), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets('ping wizard skip marks complete and shows home', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    final firstRun = FirstRunStore.memory(
      connectComplete: true,
      notificationsComplete: true,
    );
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        hostLinkStore: HostLinkStore.memory(),
        firstRunStore: firstRun,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip for now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(firstRun.pingComplete, isTrue);
    expect(find.text('Threads'), findsWidgets);
  });

  testWidgets('collab tab shows empty create shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = _mockDaemon((request) async {
      return _rpcOk(
        jsonDecode(request.body)['id'],
        {'ok': true, 'service': 'mutande-core', 'version': '0.0.0'},
      );
    });
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collab').first);
    await tester.pumpAndSettle();
    expect(find.text('No collabs yet'), findsOneWidget);
    expect(find.text('Create'), findsWidgets);
  });

  testWidgets('collab list timeout stays on pane, not courier screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] == 'list_collabs') {
        throw TimeoutException('Future not completed');
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collab').first);
    await tester.pumpAndSettle();

    expect(find.text('Hub is taking too long'), findsNothing);
    expect(find.text('Courier still starting'), findsNothing);
    expect(find.text("Couldn't load collabs"), findsOneWidget);
    expect(find.text('Collab'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('create collab sheet opens with people and agent chips', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme'},
          ],
        });
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        firstRunStore: FirstRunStore.memory(
          connectComplete: true,
          pingComplete: true,
          notificationsComplete: true,
        ),
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collab').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('PEOPLE').evaluate().isNotEmpty) break;
    }
    expect(find.text('Create collab'), findsOneWidget);
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('Roster (agent addresses)'), findsNothing);
  });

  testWidgets('network people segment shows contacts', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': '@all@acme', 'pubkey': null, 'devices': []},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        daemon: daemon,
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await _openNetworkPeople(tester);
    expect(find.text('People'), findsWidgets);
    expect(find.text('Agents'), findsWidgets);
    expect(find.text('you'), findsOneWidget);
  });

  test('collab encryption copy names the cause, never insecure', () {
    expect(
      collabEncryptionCopy(e2e: true),
      contains('sealed to steerer devices'),
    );
    final copy = collabEncryptionCopy(
      e2e: false,
      causeAddress: 'tawanda@acme/chatgpt',
    );
    expect(copy.toLowerCase().contains('insecure'), isFalse);
    expect(copy, contains("E2E isn't available"));
    expect(copy, contains('tawanda@acme/chatgpt'));
    expect(copy, contains('reads mail through the hub'));
  });
}
