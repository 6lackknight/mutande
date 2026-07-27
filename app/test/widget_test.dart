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
  testWidgets('home shell smoke test', (WidgetTester tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mutande'), findsOneWidget);
    expect(find.text('Check daemon'), findsOneWidget);
    expect(find.text('http://localhost:8000'), findsOneWidget);
    expect(find.text('alice@acme'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(
      find.textContaining('Transport: http · http://127.0.0.1:3847'),
      findsOneWidget,
    );
  });

  testWidgets('onboarding form smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MutandeApp(
        config: const AppConfig(hubUrl: 'http://localhost:8000'),
        seedStatus: const DaemonStatusResult(configured: false),
      ),
    );

    expect(find.text('Mutande'), findsOneWidget);
    expect(find.text('Join with an invite.'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(find.text('http://localhost:8000'), findsOneWidget);
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daemon unreachable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Join with an invite.'), findsNothing);
    expect(find.text('Join'), findsNothing);
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
