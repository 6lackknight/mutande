import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/app.dart';
import 'package:app/config/app_config.dart';
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
    expect(find.text('alice@acme'), findsOneWidget);
    expect(find.textContaining('Connected'), findsOneWidget);
    expect(find.text('Threads'), findsWidgets);
    expect(find.text('bob@acme'), findsOneWidget);
    expect(find.textContaining('pending'), findsOneWidget);
  });

  testWidgets('session tab still has Check daemon', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_threads') {
        return _rpcOk(body['id'], {'threads': []});
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

    await tester.tap(find.text('Session'));
    await tester.pumpAndSettle();
    expect(find.text('Check daemon'), findsOneWidget);
    expect(find.text('Connect AI hosts'), findsOneWidget);
  });

  testWidgets('verify tab shows safety UI', (WidgetTester tester) async {
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

    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Verify contact'), findsOneWidget);
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

test('validateHandle and validateHubUrl', () {
    expect(validateHandle('alice@acme'), isNull);
    expect(validateHandle('nope'), isNotNull);
    expect(validateHandle('@acme'), isNotNull);
    expect(validateHubUrl('http://localhost:8000'), isNull);
    expect(validateHubUrl('https://hub.example'), isNull);
    expect(validateHubUrl('not-a-url'), isNotNull);
    expect(validateHubUrl('ftp://x'), isNotNull);
  });
}
