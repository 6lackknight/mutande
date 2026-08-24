import 'dart:async';
import 'dart:convert';

import 'package:app/screens/settings_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/host_link_store.dart';
import 'package:app/services/notification_prefs_store.dart';
import 'package:app/services/transport_prefs_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _rpcOk(Object? id, Object result) {
  return http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    }),
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
    requestTimeout: const Duration(milliseconds: 200),
  );
}

Map<String, dynamic> _connector({
  String id = 'c-1',
  String label = 'Grok Bot',
  String prefix = 'mtc_abcd1234',
}) {
  return {
    'id': id,
    'prefix': prefix,
    'label': label,
    'slug': 'grok',
    'created_at': '2026-08-24T12:00:00Z',
  };
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required DaemonClient daemon,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        daemon: daemon,
        checking: false,
        connecting: false,
        health: const DaemonHealthResult(
          connected: true,
          service: 'mutande-core',
          version: '0.0.0',
        ),
        onCheckDaemon: () {},
        handle: 'alice@acme',
        hostLinkStore: HostLinkStore.memory(),
        notificationPrefs: NotificationPrefsStore.memory(),
        transportPrefs: TransportPrefsStore.memory(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings lists connector keys without the secret', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_mcp_connectors') {
        return _rpcOk(body['id'], {
          'connectors': [_connector()],
        });
      }
      if (method == 'get_safety_number') {
        return _rpcOk(body['id'], {
          'handle': 'alice@acme',
          'fingerprint': 'aa',
          'uri': 'mutande:aa',
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await _pumpSettings(tester, daemon: daemon);

    expect(find.text('CONNECTORS'), findsOneWidget);
    expect(find.text('Grok Bot'), findsWidgets);
    expect(find.textContaining('mtc_abcd1234'), findsOneWidget);
    expect(find.textContaining('mtc_plaintext'), findsNothing);
    expect(find.text('Revoke'), findsOneWidget);
  });

  testWidgets('Settings mints a key once then dismisses the secret', (
    tester,
  ) async {
    var listed = <Map<String, dynamic>>[];
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_mcp_connectors') {
        return _rpcOk(body['id'], {'connectors': listed});
      }
      if (method == 'create_mcp_connector') {
        final connector = _connector();
        listed = [connector];
        return _rpcOk(body['id'], {
          'connector': connector,
          'token': 'mtc_plaintext_once',
        });
      }
      if (method == 'get_safety_number') {
        return _rpcOk(body['id'], {
          'handle': 'alice@acme',
          'fingerprint': 'aa',
          'uri': 'mutande:aa',
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await _pumpSettings(tester, daemon: daemon);

    expect(find.text('No keys yet.'), findsOneWidget);

    await tester.ensureVisible(find.text('Mint key'));
    await tester.tap(find.text('Mint key'));
    await tester.pumpAndSettle();

    expect(find.text('mtc_plaintext_once'), findsOneWidget);
    expect(
      find.textContaining('mutande will not show it again'),
      findsOneWidget,
    );
    expect(find.textContaining('X-Mutande-Connector'), findsOneWidget);
    expect(find.textContaining('mcp.mutande.online/mcp'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('mtc_plaintext_once'), findsNothing);
    expect(find.text('Grok Bot'), findsWidgets);
    expect(find.textContaining('mtc_abcd1234'), findsOneWidget);
  });

  testWidgets('Settings revokes a listed connector key', (tester) async {
    var listed = [_connector()];
    var revokedId = '';
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_mcp_connectors') {
        return _rpcOk(body['id'], {'connectors': listed});
      }
      if (method == 'revoke_mcp_connector') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        revokedId = params['connector_id'] as String? ?? '';
        listed = [];
        return _rpcOk(body['id'], {'ok': true});
      }
      if (method == 'get_safety_number') {
        return _rpcOk(body['id'], {
          'handle': 'alice@acme',
          'fingerprint': 'aa',
          'uri': 'mutande:aa',
        });
      }
      return _rpcOk(body['id'], {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      });
    });

    await _pumpSettings(tester, daemon: daemon);

    await tester.ensureVisible(find.text('Revoke'));
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(find.text('Revoke connector key?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Revoke').last);
    await tester.pumpAndSettle();

    expect(revokedId, 'c-1');
    expect(find.text('No keys yet.'), findsOneWidget);
    expect(find.text('Revoke'), findsNothing);
  });

  test('friendlyDaemonError maps connector quota', () {
    expect(
      friendlyDaemonError(
        Exception('Too many MCP connector keys (max 8); revoke one first'),
        what: 'Mint key',
      ),
      'You already have 8 connector keys. Revoke one first.',
    );
  });
}
