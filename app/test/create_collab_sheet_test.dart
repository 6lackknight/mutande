import 'dart:async';
import 'dart:convert';

import 'package:app/models/agent_transport.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/create_collab_sheet.dart';
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

http.Response _rpcErr(Object? id, String message, {int code = -32000}) {
  return http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
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
    requestTimeout: const Duration(seconds: 2),
  );
}

Map<String, dynamic> _rpc(http.Request request) {
  return jsonDecode(request.body) as Map<String, dynamic>;
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required DaemonClient daemon,
  String handle = 'alice@acme',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 560,
          child: CreateCollabSheet(daemon: daemon, handle: handle),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('PEOPLE').evaluate().isNotEmpty) return;
  }
}

void main() {
  test('bareCollabHandle strips suffix and broadcast', () {
    expect(bareCollabHandle('Alice@Acme/Cursor'), 'alice@acme');
    expect(bareCollabHandle('alice@acme/default'), 'alice@acme');
    expect(bareCollabHandle('@all@acme'), isNull);
    expect(bareCollabHandle('@cursor'), isNull);
  });

  test('collabRosterSlug hides default', () {
    expect(collabRosterSlug('Cursor'), 'cursor');
    expect(collabRosterSlug('default'), isNull);
    expect(collabRosterSlug(''), isNull);
  });

  test('collabCauseAddress is full handle/slug', () {
    expect(
      collabCauseAddress(ownerHandle: 'Alice@Acme', slug: 'ChatGPT'),
      'alice@acme/chatgpt',
    );
  });

  test('collabPersonTitle prefers display name, else local-part', () {
    expect(
      collabPersonTitle(displayName: 'Tawanda Brandon', handle: 'tawanda@tbhco'),
      'Tawanda Brandon',
    );
    expect(collabPersonTitle(handle: 'alice@acme'), 'Alice');
    expect(collabPersonInitials('Tawanda Brandon'), 'TB');
    expect(collabPersonInitials('tawanda'), 'TA');
  });

  test('collapseCollabAgents one chip per id; dual transport prefers web', () {
    const sidecar = CollabPickerAgent(
      agentId: 'a1',
      address: '@chatgpt',
      ownerHandle: 'alice@acme',
      slug: 'chatgpt',
      causeAddress: 'alice@acme/chatgpt',
      transport: AgentTransport.sidecar,
    );
    const web = CollabPickerAgent(
      agentId: 'a2',
      address: '@chatgpt',
      ownerHandle: 'alice@acme',
      slug: 'chatgpt',
      causeAddress: 'alice@acme/chatgpt',
      transport: AgentTransport.mcp,
    );
    const sameId = CollabPickerAgent(
      agentId: 'a1',
      address: 'alice@acme/chatgpt',
      ownerHandle: 'alice@acme',
      slug: 'chatgpt',
      causeAddress: 'alice@acme/chatgpt',
      transport: AgentTransport.sidecar,
    );

    final dual = collapseCollabAgents([sidecar, web]);
    expect(dual, hasLength(1));
    expect(dual.single.address, '@chatgpt');
    expect(dual.single.transport, AgentTransport.mcp);

    final idDup = collapseCollabAgents([sidecar, sameId]);
    expect(idDup, hasLength(1));
    expect(idDup.single.address, '@chatgpt');
  });

  test('instructions visible when steerers ∪ roster is more than one', () {
    expect(
      collabInstructionsVisible(
        steerers: ['alice@acme'],
        roster: [],
      ),
      isFalse,
    );
    expect(
      collabInstructionsVisible(
        steerers: ['alice@acme'],
        roster: ['@cursor'],
      ),
      isTrue,
    );
    expect(
      collabInstructionsVisible(
        steerers: ['alice@acme', 'bob@acme'],
        roster: [],
      ),
      isTrue,
    );
    expect(
      collabParticipantCount(
        steerers: ['Alice@Acme'],
        roster: ['@Cursor', ' alice@acme '],
      ),
      2,
    );
  });

  test('collabRosterEncryption names hosted cause, never insecure', () {
    final sidecar = collabRosterEncryption([
      (causeAddress: 'alice@acme/cursor', transport: AgentTransport.sidecar),
    ]);
    expect(sidecar.e2e, isTrue);
    expect(sidecar.causeAddress, isNull);

    final hosted = collabRosterEncryption([
      (causeAddress: 'alice@acme/cursor', transport: AgentTransport.sidecar),
      (causeAddress: 'alice@acme/chatgpt', transport: AgentTransport.mcp),
    ]);
    expect(hosted.e2e, isFalse);
    expect(hosted.causeAddress, 'alice@acme/chatgpt');
    expect(hosted.external, isFalse);
    expect(
      collabEncryptionCopy(
        e2e: hosted.e2e,
        causeAddress: hosted.causeAddress,
      ).toLowerCase().contains('insecure'),
      isFalse,
    );

    final external = collabRosterEncryption(
      const [],
      externalHandles: ['Orinea@tbhco'],
    );
    expect(external.e2e, isFalse);
    expect(external.external, isTrue);
    expect(external.causeAddress, 'orinea@tbhco');
    expect(
      collabEncryptionCopy(
        e2e: false,
        causeAddress: 'orinea@tbhco',
        external: true,
      ),
      contains('orinea@tbhco is outside the org — mail goes through the hub'),
    );
    expect(
      collabEncryptionCopy(
        e2e: false,
        causeAddress: 'orinea@tbhco',
        external: true,
      ).toLowerCase().contains('insecure'),
      isFalse,
    );
  });

  testWidgets('sheet picks people and agents as chips, not typed roster', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': '@all@acme', 'kind': 'broadcast'},
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        });
      }
      if (method == 'list_agents') {
        final handle = (body['params'] as Map?)?['handle'] as String?;
        if (handle == 'bob@acme') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          });
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
            {'id': 'a2', 'slug': 'chatgpt', 'transport': 'mcp'},
            {'id': 'a3', 'slug': 'default', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.text('Create collab'), findsOneWidget);
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('alice@acme'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('bob@acme'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('@chatgpt'), findsOneWidget);
    expect(find.text('bob@acme/claude'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
    expect(find.text('via sidecar'), findsNothing);
    expect(find.text('Picking an agent adds their person.'), findsOneWidget);
    expect(find.text('Roster (agent addresses)'), findsNothing);
    expect(find.text('@cursor, bob@acme/claude'), findsNothing);
    expect(find.textContaining('/default'), findsNothing);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsOneWidget,
    );
    expect(find.text('INSTRUCTIONS'), findsNothing);

    await tester.tap(find.text('Bob Builder'));
    await tester.pump();
    expect(find.text('INSTRUCTIONS'), findsOneWidget);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsOneWidget,
    );
  });

  testWidgets('dual chatgpt collapses to one web chip', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 's1', 'slug': 'chatgpt', 'transport': 'sidecar'},
            {'id': 'w1', 'slug': 'chatgpt', 'transport': 'mcp'},
            {'id': 'c1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.text('@chatgpt'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);

    await tester.tap(find.text('@chatgpt'));
    await tester.pump();
    expect(
      find.textContaining('alice@acme/chatgpt reads mail through the hub'),
      findsOneWidget,
    );
    expect(find.text('INSTRUCTIONS'), findsOneWidget);
  });

  testWidgets('validates name and roster and keeps fields', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Name this collab.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Sprint 12');
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Pick at least one agent.'), findsOneWidget);
    expect(find.text('Sprint 12'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('INSTRUCTIONS'), findsNothing);

    await tester.tap(find.text('@cursor'));
    await tester.pump();
    expect(find.text('INSTRUCTIONS'), findsOneWidget);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsOneWidget,
    );
    expect(find.text('Standing context for this board'), findsOneWidget);
  });

  testWidgets('picking an agent auto-adds its human and names hosted cause', (
    tester,
  ) async {
    Map<String, dynamic>? created;
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme'},
          ],
        });
      }
      if (method == 'list_agents') {
        final handle = (body['params'] as Map?)?['handle'] as String?;
        if (handle == 'bob@acme') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          });
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a2', 'slug': 'chatgpt', 'transport': 'mcp'},
          ],
        });
      }
      if (method == 'create_collab') {
        created = body['params'] as Map<String, dynamic>?;
        return _rpcOk(body['id'], {
          'collab': {
            'id': 'c1',
            'name': 'Board',
            'encryption_mode': 'app_envelope',
            'lists': <Map<String, dynamic>>[],
          },
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    await tester.tap(find.text('bob@acme/claude'));
    await tester.pump();
    expect(find.text('bob@acme'), findsOneWidget);

    await tester.tap(find.text('@chatgpt'));
    await tester.pump();
    expect(
      find.textContaining('alice@acme/chatgpt reads mail through the hub'),
      findsOneWidget,
    );
    expect(find.text('INSTRUCTIONS'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Board');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(created, isNotNull);
    final steerers = (created!['steerer_handles'] as List).cast<String>();
    final roster = (created!['roster_addresses'] as List).cast<String>();
    expect(steerers, containsAll(['alice@acme', 'bob@acme']));
    expect(roster, containsAll(['bob@acme/claude', '@chatgpt']));
  });

  testWidgets('approved externals sit in People with a quiet mark', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder', 'kind': 'org'},
          ],
        });
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {
              'handle': 'orinea@tbhco',
              'display_name': 'Orinea',
              'kind': 'external',
              'external_link_id': 'link-1',
            },
          ],
        });
      }
      if (method == 'list_agents') {
        final handle = (body['params'] as Map?)?['handle'] as String?;
        if (handle == 'bob@acme') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          });
        }
        if (handle == 'orinea@tbhco') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'error': {'code': -32000, 'message': 'not same org'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('Orinea'), findsOneWidget);
    expect(find.text('orinea@tbhco'), findsOneWidget);
    expect(find.text('external'), findsOneWidget);
    expect(find.text('EXTERNAL'), findsNothing);
    expect(find.text('orinea@tbhco/cursor'), findsNothing);
    expect(find.text('orinea@tbhco/claude'), findsNothing);

    await tester.tap(find.text('orinea@tbhco'));
    await tester.pump();
    expect(
      find.textContaining(
        'orinea@tbhco is outside the org — mail goes through the hub',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('insecure'), findsNothing);
    expect(find.text('INSTRUCTIONS'), findsOneWidget);
  });

  testWidgets('external agents appear when list_agents allows them', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {
              'handle': 'orinea@tbhco',
              'display_name': 'Orinea',
              'kind': 'external',
            },
          ],
        });
      }
      if (method == 'list_agents') {
        final handle = (body['params'] as Map?)?['handle'] as String?;
        if (handle == 'orinea@tbhco') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'e1', 'slug': 'chatgpt', 'transport': 'mcp'},
            ],
          });
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.text('orinea@tbhco/chatgpt'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
  });

  testWidgets('create locks double-submit and keeps fields on error', (
    tester,
  ) async {
    var creates = 0;
    final gate = Completer<void>();
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      if (method == 'create_collab') {
        creates += 1;
        await gate.future;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'error': {'code': -32000, 'message': 'hub down'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);
    await tester.enterText(find.byType(TextField).first, 'Board');
    await tester.tap(find.text('@cursor'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(creates, 1);
    expect(find.text('Create'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('teammate list_agents 404 still shows people; no sign-in copy', (
    tester,
  ) async {
    String? agentsHandle;
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'Orinea@tbhco', 'display_name': 'Orinea'},
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        });
      }
      if (method == 'list_external_contacts') {
        return _rpcErr(
          body['id'],
          'hub error 404 Not Found: {"error":"not_found"}',
        );
      }
      if (method == 'list_agents') {
        final handle = (body['params'] as Map?)?['handle'] as String?;
        if (handle != null) agentsHandle ??= handle;
        if (handle == 'orinea@tbhco') {
          return _rpcErr(
            body['id'],
            'hub error 404 Not Found: {"error":"not_found","message":"User not found"}',
          );
        }
        if (handle == 'Orinea@tbhco') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'o1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          });
        }
        if (handle == 'bob@acme') {
          return _rpcOk(body['id'], {
            'agents': [
              {'id': 'b1', 'slug': 'cursor', 'transport': 'sidecar'},
            ],
          });
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon, handle: 'tawanda@tbhco');

    expect(find.text('Create collab'), findsOneWidget);
    expect(find.text('Orinea'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('bob@acme/cursor'), findsOneWidget);
    expect(find.text('orinea@tbhco/claude'), findsOneWidget);
    expect(agentsHandle, 'Orinea@tbhco');
    expect(find.textContaining('signed in'), findsNothing);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('contacts ok and own agents fail still shows people chips', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        });
      }
      if (method == 'list_agents') {
        final handle = (body['params'] as Map?)?['handle'] as String?;
        if (handle == null) {
          return _rpcErr(body['id'], 'hub error 503 Service Unavailable');
        }
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
          ],
        });
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('alice@acme'), findsOneWidget);
    expect(find.text('bob@acme/claude'), findsOneWidget);
    expect(find.textContaining('signed in'), findsNothing);
  });

  testWidgets('create_collab 404 says hub has no collab, not sign-in', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        });
      }
      if (method == 'create_collab') {
        return _rpcErr(
          body['id'],
          'hub error 404 Not Found: {"error":"not_found"}',
        );
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);
    await tester.enterText(find.byType(TextField).first, 'Launch week');
    await tester.tap(find.text('@cursor'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(find.text("This hub doesn't support collab yet."), findsOneWidget);
    expect(find.textContaining('signed in'), findsNothing);
    expect(find.text('Launch week'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('load 401 shows Sign in; retry keeps name', (tester) async {
    var contactsCalls = 0;
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        contactsCalls += 1;
        if (contactsCalls == 1) {
          return _rpcErr(body['id'], 'hub error 401 Unauthorized');
        }
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
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
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Sign-in expired'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Keep me');
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });
}
