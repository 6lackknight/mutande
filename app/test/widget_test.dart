import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/app.dart';
import 'package:app/config/app_config.dart';
import 'package:app/screens/agents_screen.dart';
import 'package:app/services/daemon_client.dart';

DaemonClient _mockDaemon(
  Future<http.Response> Function(http.Request) handler,
) {
  return DaemonClient(
    httpClient: MockClient(handler),
    httpToken: 'test-token',
    requestTimeout: const Duration(milliseconds: 200),
  );
}

http.Response _rpcOk(Object? id, Map<String, dynamic> result) {
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: {'Content-Type': 'application/json'},
  );
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
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('mutande'), findsOneWidget);
    expect(find.text('Threads'), findsWidgets);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('bob@acme'), findsOneWidget);
    expect(find.byTooltip('alice@acme'), findsOneWidget);
    expect(find.textContaining('ACTION REQUIRED'), findsOneWidget);
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
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Check daemon'), findsOneWidget);
    expect(find.text('Connect new host'), findsOneWidget);
    expect(find.text('CONNECTED'), findsOneWidget);
    expect(find.text('Safety Numbers'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('alice@acme'), findsOneWidget);
  });

  testWidgets('connect AI hosts shows friendly success rows', (
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
        return _rpcOk(body['id'], {
          'command': '/Users/dev/bin/mutande-core',
          'args': ['mcp'],
          'hosts': [
            {
              'host': 'cursor',
              'path': '/Users/dev/.cursor/mcp.json',
              'ok': true,
            },
            {
              'host': 'claude',
              'path':
                  '/Users/dev/Library/Application Support/Claude/claude_desktop_config.json',
              'ok': true,
            },
            {
              'host': 'chatgpt',
              'path':
                  '/Users/dev/Library/Application Support/ChatGPT/mcp.json',
              'ok': true,
              'note':
                  'ChatGPT path unconfirmed; also seen: mcp_config.json. Prefer Settings -> MCP if the file is ignored.',
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final connect = find.text('Connect new host');
    await tester.ensureVisible(connect);
    await tester.pumpAndSettle();
    await tester.tap(connect);
    // Allow the connect_host future to complete past the loading orb tickers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Connected 3 AI hosts'), findsOneWidget);
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Claude (Anthropic)'), findsOneWidget);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('Connected'), findsAtLeastNWidgets(3));
    expect(find.textContaining('Wrote '), findsNothing);
    expect(find.textContaining('/Users/dev/bin/mutande-core'), findsNothing);
    expect(find.textContaining('Settings'), findsWidgets);

    final details = find.text('Details');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.textContaining('.cursor/mcp.json'), findsOneWidget);
    expect(find.textContaining('MCP'), findsWidgets);
  });

  testWidgets('agents Add opens idle host picker', (WidgetTester tester) async {
    String? connectedHost;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
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
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add an AI host for your primary agent.'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Add AI host'), findsOneWidget);
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Claude (Anthropic)'), findsOneWidget);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('Idle'), findsAtLeastNWidgets(3));

    await tester.tap(find.text('Cursor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(connectedHost, 'cursor');
    expect(find.text('Added Cursor'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Safety Numbers'), findsOneWidget);
    expect(find.text('Compare safety numbers'), findsOneWidget);
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

    expect(find.text('mutande'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in with Auth0'), findsOneWidget);
  });

  testWidgets('onboarding choose step when signed in', (WidgetTester tester) async {
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        seedStatus: const DaemonStatusResult(
          configured: false,
          signedIn: true,
          needsOnboarding: true,
          email: 'a@x.com',
        ),
        welcomeDuration: Duration.zero,
      ),
    );

    expect(find.text('Create a team'), findsOneWidget);
    expect(find.text('I have an invite'), findsOneWidget);
    expect(find.text('a@x.com'), findsOneWidget);
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daemon unreachable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign in with Auth0'), findsNothing);
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load session"), findsOneWidget);
    expect(find.text('Daemon unreachable'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
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

  testWidgets('agent inspector harden paths', (WidgetTester tester) async {
    String claudeSlug = 'claude';
    String? defaultAgentId = 'a-default';
    String? renamedTo;
    String? setDefaultId;
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a-default', 'slug': 'cursor'},
            {'id': 'a-claude', 'slug': claudeSlug},
          ],
          'default_agent_id': defaultAgentId,
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
      if (method == 'set_default_agent') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        setDefaultId = params['agent_id'] as String?;
        defaultAgentId = setDefaultId;
        return _rpcOk(body['id'], {
          'id': setDefaultId,
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
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('claude').first);
    await tester.pumpAndSettle();

    expect(find.text('Agent Inspector'), findsOneWidget);
    expect(find.text('alice@acme/claude'), findsOneWidget);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.text('Idle'), findsWidgets);
    expect(find.text('Set as default'), findsOneWidget);
    expect(find.text('Default'), findsNothing);

    await tester.tap(find.text('Disconnect host'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect host?'), findsOneWidget);
    expect(find.textContaining('mutande'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Agent Inspector'), findsOneWidget);

    await tester.tap(find.text('Rename slug'));
    await tester.pumpAndSettle();
    expect(find.text('Rename slug'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'default');
    await tester.pumpAndSettle();
    expect(find.text('"default" is reserved.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'codex');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(renamedTo, 'codex');

    await tester.tap(find.text('codex').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as default'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(setDefaultId, 'a-claude');
  });

  testWidgets('agent inspector shows Default for primary', (
    WidgetTester tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
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
        seedStatus: const DaemonStatusResult(
          configured: true,
          hubUrl: 'http://localhost:8000',
          handle: 'alice@acme',
        ),
        welcomeDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cursor').first);
    await tester.pumpAndSettle();

    expect(find.text('alice@acme'), findsWidgets);
    expect(find.text('alice@acme/cursor'), findsNothing);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Set as default'), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
  });
}
