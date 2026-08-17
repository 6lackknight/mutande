import 'package:app/models/agent_transport.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'fake_daemon_client.dart';
import 'package:app/services/host_link_store.dart';
import 'package:app/services/notification_prefs_store.dart';
import 'package:app/services/transport_prefs_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Settings default transport picker when dual slots present', (
    tester,
  ) async {
    final transportPrefs = TransportPrefsStore.memory();
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_agents') {
        return {
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
        };
      }
      if (method == 'get_transport_defaults') {
        return {
          'defaults': {'chatgpt': 'sidecar'},
        };
      }
      if (method == 'set_transport_default') {
        final slug = params?['slug'];
        final transport = params?['transport'];
        return {
          'defaults': {slug: transport},
        };
      }
      if (method == 'get_safety_number') {
        return {
          'handle': 'alice@acme',
          'fingerprint': 'aa',
          'uri': 'mutande:aa',
        };
      }
      return {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      };
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'chatgpt'},
            {'id': 'a2', 'slug': 'claude'},
          ],
          'default_agent_id': 'a1',
        };
      }
      if (method == 'get_safety_number') {
        return {
          'handle': 'alice@acme',
          'fingerprint': 'aa',
          'uri': 'mutande:aa',
        };
      }
      return {
        'ok': true,
        'service': 'mutande-core',
        'version': '0.0.0',
      };
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
