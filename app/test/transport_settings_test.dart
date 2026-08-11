import 'dart:async';
import 'dart:convert';

import 'package:app/models/agent_transport.dart';
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

void main() {
  testWidgets('Settings default transport picker when dual slots present', (
    tester,
  ) async {
    final transportPrefs = TransportPrefsStore.memory();
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {
              'id': 'sidecar-1',
              'slug': 'chatgpt',
              'transport': 'sidecar',
            },
            {
              'id': 'web-1',
              'slug': 'chatgpt',
              'transport': 'mcp',
            },
            {'id': 'claude-1', 'slug': 'claude', 'transport': 'sidecar'},
          ],
          'default_agent_id': 'sidecar-1',
        });
      }
      if (method == 'get_transport_defaults') {
        return _rpcOk(body['id'], {
          'defaults': {'chatgpt': 'sidecar'},
        });
      }
      if (method == 'set_transport_default') {
        final params = body['params'] as Map<String, dynamic>? ?? {};
        return _rpcOk(body['id'], {
          'defaults': {
            params['slug']: params['transport'],
          },
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
    transportPrefs.daemon = daemon;

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
          transportPrefs: transportPrefs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEFAULT TRANSPORT'), findsOneWidget);
    expect(find.text('chatgpt'), findsWidgets);
    expect(find.text('Sidecar'), findsWidgets);
    expect(find.text('Web'), findsWidgets);

    await tester.ensureVisible(find.text('Web').last);
    await tester.tap(find.text('Web').last);
    await tester.pumpAndSettle();

    final prefs = await transportPrefs.load();
    expect(prefs.defaultFor('chatgpt'), AgentTransport.mcp);
  });

  testWidgets('Settings hides default transport when API omits transport', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final method = body['method'] as String?;
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'chatgpt'},
            {'id': 'a2', 'slug': 'claude'},
          ],
          'default_agent_id': 'a1',
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

    expect(find.text('DEFAULT TRANSPORT'), findsNothing);
  });
}
