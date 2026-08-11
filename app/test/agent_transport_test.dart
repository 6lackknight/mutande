import 'dart:convert';

import 'package:app/models/agent_transport.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/transport_prefs_store.dart';
import 'package:app/util/compose_transport.dart';
import 'package:app/widgets/transport_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AgentTransport', () {
    test('tryParse accepts sidecar and mcp/web', () {
      expect(AgentTransport.tryParse('sidecar'), AgentTransport.sidecar);
      expect(AgentTransport.tryParse('mcp'), AgentTransport.mcp);
      expect(AgentTransport.tryParse('web'), AgentTransport.mcp);
      expect(AgentTransport.tryParse(null), isNull);
      expect(AgentTransport.tryParse(''), isNull);
      expect(AgentTransport.tryParse('carrier-pigeon'), isNull);
    });

    test('chip labels', () {
      expect(AgentTransport.sidecar.chipLabel, 'via sidecar');
      expect(AgentTransport.mcp.chipLabel, 'via web');
    });
  });

  group('AgentInfo.fromJson', () {
    test('omits transport when API has no field (pre-L1)', () {
      final a = AgentInfo.fromJson({'id': 'a1', 'slug': 'cursor'});
      expect(a.transport, isNull);
      expect(a.trustTier, isNull);
      expect(a.lastSeen, isNull);
    });

    test('parses transport, trust_tier, last_seen', () {
      final a = AgentInfo.fromJson({
        'agent_id': 'b2',
        'slug': 'chatgpt',
        'transport': 'mcp',
        'trust_tier': 'org',
        'last_seen': '2026-08-11T12:00:00.000Z',
      });
      expect(a.id, 'b2');
      expect(a.transport, AgentTransport.mcp);
      expect(a.trustTier, TrustTier.org);
      expect(a.lastSeen, DateTime.parse('2026-08-11T12:00:00.000Z'));
    });

    test('parses capabilities_updated_at as lastSeen', () {
      final freshAt =
          DateTime.now().toUtc().subtract(const Duration(minutes: 2));
      final a = AgentInfo.fromJson({
        'id': 'c3',
        'slug': 'claude',
        'transport': 'sidecar',
        'trust_tier': 'org',
        'capabilities_updated_at': freshAt.toIso8601String(),
      });
      expect(a.lastSeen, isNotNull);
      expect(
        a.lastSeen!.difference(freshAt).inSeconds.abs(),
        lessThan(2),
      );
      expect(a.capabilityFresh, isTrue);
    });
  });

  group('dualTransportSlugs', () {
    test('requires both sidecar and mcp for same slug', () {
      expect(
        dualTransportSlugs([
          (slug: 'chatgpt', transport: AgentTransport.mcp),
          (slug: 'chatgpt', transport: AgentTransport.sidecar),
          (slug: 'claude', transport: AgentTransport.sidecar),
        ]),
        ['chatgpt'],
      );
      expect(
        dualTransportSlugs([
          (slug: 'chatgpt', transport: AgentTransport.mcp),
          (slug: 'claude', transport: null),
        ]),
        isEmpty,
      );
    });
  });

  group('resolveComposeTransportWarning', () {
    test('null when transport absent', () {
      expect(
        resolveComposeTransportWarning(
          recipient: '@chatgpt',
          agents: [const AgentInfo(id: '1', slug: 'chatgpt')],
        ),
        isNull,
      );
    });

    test('via web · not E2E for mcp slot', () {
      final w = resolveComposeTransportWarning(
        recipient: '@chatgpt',
        agents: const [
          AgentInfo(id: '1', slug: 'chatgpt', transport: AgentTransport.mcp),
        ],
      );
      expect(w?.label, 'via web · not E2E');
    });

    test('uses prefs default when dual slots exist', () {
      const agents = [
        AgentInfo(id: 's', slug: 'chatgpt', transport: AgentTransport.sidecar),
        AgentInfo(id: 'w', slug: 'chatgpt', transport: AgentTransport.mcp),
      ];
      expect(
        resolveComposeTransportWarning(
          recipient: '@chatgpt',
          agents: agents,
          prefs: const TransportPrefs(
            defaultBySlug: {'chatgpt': AgentTransport.sidecar},
          ),
        ),
        isNull,
      );
      expect(
        resolveComposeTransportWarning(
          recipient: '@chatgpt',
          agents: agents,
          prefs: const TransportPrefs(
            defaultBySlug: {'chatgpt': AgentTransport.mcp},
          ),
        )?.label,
        'via web · not E2E',
      );
    });

    test('enterprise / external variants', () {
      expect(
        resolveComposeTransportWarning(
          recipient: 'assistant@openai/bot',
          agents: const [
            AgentInfo(
              id: 'e',
              slug: 'bot',
              transport: AgentTransport.mcp,
              trustTier: TrustTier.enterprise,
            ),
          ],
        )?.label,
        'via enterprise · not E2E',
      );
      expect(
        ComposeTransportWarning.fromSlot(trustTier: TrustTier.external)?.label,
        'via external · not E2E',
      );
    });
  });

  group('TransportPrefsStore', () {
    test('memory round-trip', () async {
      final store = TransportPrefsStore.memory();
      await store.setDefault('chatgpt', AgentTransport.mcp);
      final loaded = await store.load();
      expect(loaded.defaultFor('chatgpt'), AgentTransport.mcp);
      expect(loaded.defaultFor('Claude'), isNull);
    });

    test('fromJson accepts hub defaults shape', () {
      final prefs = TransportPrefs.fromJson({
        'defaults': {'chatgpt': 'mcp', 'claude': 'sidecar'},
      });
      expect(prefs.defaultFor('chatgpt'), AgentTransport.mcp);
      expect(prefs.defaultFor('claude'), AgentTransport.sidecar);
    });

    test('syncFromHub pulls hub and caches', () async {
      final daemon = DaemonClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['method'], 'get_transport_defaults');
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'defaults': {'chatgpt': 'mcp'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        httpToken: 'test-token',
        requestTimeout: const Duration(milliseconds: 200),
      );
      final store = TransportPrefsStore.memory();
      store.daemon = daemon;
      final prefs = await store.syncFromHub();
      expect(prefs.defaultFor('chatgpt'), AgentTransport.mcp);
    });

    test('setDefault pushes to hub when daemon attached', () async {
      String? pushedTransport;
      final daemon = DaemonClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['method'], 'set_transport_default');
          final params = body['params'] as Map<String, dynamic>;
          pushedTransport = params['transport'] as String?;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'defaults': {params['slug']: params['transport']},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        httpToken: 'test-token',
        requestTimeout: const Duration(milliseconds: 200),
      );
      final store = TransportPrefsStore(daemon: daemon, memory: const TransportPrefs());
      final prefs = await store.setDefault('chatgpt', AgentTransport.mcp);
      expect(pushedTransport, 'mcp');
      expect(prefs.defaultFor('chatgpt'), AgentTransport.mcp);
    });
  });

  group('TransportChip', () {
    testWidgets('renders via labels; maybe hides when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TransportChip(transport: AgentTransport.sidecar),
                TransportChip(transport: AgentTransport.mcp),
              ],
            ),
          ),
        ),
      );
      expect(find.text('via sidecar'), findsOneWidget);
      expect(find.text('via web'), findsOneWidget);
      expect(TransportChip.maybe(transport: null), isNull);
    });

    testWidgets('compose non-E2E chip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComposeNonE2eChip(
              warning: ComposeTransportWarning.fromSlot(
                transport: AgentTransport.mcp,
              )!,
            ),
          ),
        ),
      );
      expect(find.text('via web · not E2E'), findsOneWidget);
    });
  });
}
