import 'dart:async';

import 'package:app/models/agent_transport.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/daemon_errors.dart';
import 'fake_daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/create_collab_sheet.dart';
import 'package:app/widgets/mutande_stagger.dart';
import 'package:app/widgets/thread_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpSheet(
  WidgetTester tester, {
  required DaemonClient daemon,
  String handle = 'alice@acme',
  bool reduce = false,
  bool waitForForm = true,
  Future<List<CollabPendingFile>> Function()? pickFiles,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      builder: (context, child) {
        if (!reduce) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 560,
          child: CreateCollabSheet(
            daemon: daemon,
            handle: handle,
            pickFiles: pickFiles,
          ),
        ),
      ),
    ),
  );
  if (!waitForForm) {
    await tester.pump();
    return;
  }
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text(handle).evaluate().isNotEmpty) return;
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
      collabPersonTitle(
        displayName: 'Tawanda Brandon',
        handle: 'tawanda@tbhco',
      ),
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
      collabInstructionsVisible(steerers: ['alice@acme'], roster: []),
      isFalse,
    );
    expect(
      collabInstructionsVisible(steerers: ['alice@acme'], roster: ['@cursor']),
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {
          'contacts': [
            {'handle': '@all@acme', 'kind': 'broadcast'},
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        };
      }
      if (method == 'list_agents') {
        final handle = params?['handle'] as String?;
        if (handle == 'bob@acme') {
          return {
            'agents': [
              {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          };
        }
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
            {'id': 'a2', 'slug': 'chatgpt', 'transport': 'mcp'},
            {'id': 'a3', 'slug': 'default', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 's1', 'slug': 'chatgpt', 'transport': 'sidecar'},
            {'id': 'w1', 'slug': 'chatgpt', 'transport': 'mcp'},
            {'id': 'c1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {
          'contacts': [
            {'handle': 'bob@acme'},
          ],
        };
      }
      if (method == 'list_agents') {
        final handle = params?['handle'] as String?;
        if (handle == 'bob@acme') {
          return {
            'agents': [
              {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          };
        }
        return {
          'agents': [
            {'id': 'a2', 'slug': 'chatgpt', 'transport': 'mcp'},
          ],
        };
      }
      if (method == 'create_collab') {
        created = params;
        return {
          'collab': {
            'id': 'c1',
            'name': 'Board',
            'encryption_mode': 'app_envelope',
            'lists': <Map<String, dynamic>>[],
          },
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {
          'contacts': [
            {
              'handle': 'bob@acme',
              'display_name': 'Bob Builder',
              'kind': 'org',
            },
          ],
        };
      }
      if (method == 'list_external_contacts') {
        return {
          'contacts': [
            {
              'handle': 'orinea@tbhco',
              'display_name': 'Orinea',
              'kind': 'external',
              'external_link_id': 'link-1',
            },
          ],
        };
      }
      if (method == 'list_agents') {
        final handle = params?['handle'] as String?;
        if (handle == 'bob@acme') {
          return {
            'agents': [
              {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          };
        }
        if (handle == 'orinea@tbhco') {
          throw DaemonException('not same org');
        }
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_external_contacts') {
        return {
          'contacts': [
            {
              'handle': 'orinea@tbhco',
              'display_name': 'Orinea',
              'kind': 'external',
            },
          ],
        };
      }
      if (method == 'list_agents') {
        final handle = params?['handle'] as String?;
        if (handle == 'orinea@tbhco') {
          return {
            'agents': [
              {'id': 'e1', 'slug': 'chatgpt', 'transport': 'mcp'},
            ],
          };
        }
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      if (method == 'create_collab') {
        creates += 1;
        await gate.future;
        throw DaemonException('hub down');
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {
          'contacts': [
            {'handle': 'Orinea@tbhco', 'display_name': 'Orinea'},
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        };
      }
      if (method == 'list_external_contacts') {
        throw DaemonException('hub error 404 Not Found: {"error":"not_found"}');
      }
      if (method == 'list_agents') {
        final handle = params?['handle'] as String?;
        if (handle != null) agentsHandle ??= handle;
        if (handle == 'orinea@tbhco') {
          return {
            'agents': [
              {'id': 'o1', 'slug': 'claude', 'transport': 'sidecar'},
            ],
          };
        }
        if (handle == 'Orinea@tbhco') {
          throw DaemonException('hub error 404 Not Found: {"error":"not_found","message":"User not found"}');
        }
        if (handle == 'bob@acme') {
          return {
            'agents': [
              {'id': 'b1', 'slug': 'cursor', 'transport': 'sidecar'},
            ],
          };
        }
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(tester, daemon: daemon, handle: 'tawanda@tbhco');

    expect(find.text('Create collab'), findsOneWidget);
    expect(find.text('Orinea'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('bob@acme/cursor'), findsOneWidget);
    expect(find.text('orinea@tbhco/claude'), findsOneWidget);
    expect(agentsHandle, 'orinea@tbhco');
    expect(find.textContaining('signed in'), findsNothing);
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('contacts ok and own agents fail still shows people chips', (
    tester,
  ) async {
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        };
      }
      if (method == 'list_agents') {
        final handle = params?['handle'] as String?;
        if (handle == null) {
          throw DaemonException('hub error 503 Service Unavailable');
        }
        return {
          'agents': [
            {'id': 'b1', 'slug': 'claude', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      if (method == 'create_collab') {
        throw DaemonException('hub error 404 Not Found: {"error":"not_found"}');
      }
      return {'ok': true};
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

  testWidgets('create_collab user-not-found is not load Create collab', (
    tester,
  ) async {
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      if (method == 'create_collab') {
        throw DaemonException('hub error 404 Not Found: {"error":"not_found","message":"User not found"}');
      }
      return {'ok': true};
    });

    await _pumpSheet(tester, daemon: daemon);
    await tester.enterText(find.byType(TextField).first, 'Launch week');
    await tester.tap(find.text('@cursor'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(find.textContaining("Couldn't load Create collab"), findsNothing);
    expect(
      find.text(
        "A selected person wasn't found. Check their handle, then retry.",
      ),
      findsOneWidget,
    );
    expect(find.text('Launch week'), findsOneWidget);
    expect(find.text('INSTRUCTIONS'), findsOneWidget);
    expect(find.textContaining('signed in'), findsNothing);
  });

  testWidgets('load 401 shows Sign in; retry keeps name', (tester) async {
    var contactsCalls = 0;
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        contactsCalls += 1;
        if (contactsCalls == 1) {
          throw DaemonException('hub error 401 Unauthorized');
        }
        return {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        };
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
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

  testWidgets('stone skeleton while people and agents load', (tester) async {
    final gate = Completer<void>();
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts' || method == 'list_external_contacts') {
        await gate.future;
        return {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        };
      }
      if (method == 'list_agents') {
        await gate.future;
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(tester, daemon: daemon, waitForForm: false);

    expect(find.byType(CreateCollabChipSkeleton), findsNWidgets(2));
    expect(find.text('Create collab'), findsOneWidget);
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('ARTIFACTS'), findsOneWidget);
    expect(find.text('Attach file'), findsOneWidget);
    expect(find.text('Add link'), findsOneWidget);
    expect(find.text('e.g. launch week'), findsOneWidget);
    expect(find.text('Picking an agent adds their person.'), findsOneWidget);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Bob Builder'), findsNothing);

    gate.complete();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('Bob Builder').evaluate().isNotEmpty) break;
    }
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('NAME'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MutandeStaggerIn),
        matching: find.text('Bob Builder'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(MutandeStaggerIn),
        matching: find.text('@cursor'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('chips fade and rise when pickers resolve', (tester) async {
    final gate = Completer<void>();
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        await gate.future;
        return {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob Builder'},
          ],
        };
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(tester, daemon: daemon, waitForForm: false);
    gate.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      if (find.text('Bob Builder').evaluate().isNotEmpty) break;
    }

    final bobFade = find.ancestor(
      of: find.text('Bob Builder'),
      matching: find.byType(Opacity),
    );
    expect(bobFade, findsWidgets);
    expect(tester.widget<Opacity>(bobFade.first).opacity, lessThan(0.2));

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bob Builder'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
  });

  testWidgets('disableAnimations snaps skeleton and form without throw', (
    tester,
  ) async {
    final gate = Completer<void>();
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        await gate.future;
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(tester, daemon: daemon, reduce: true, waitForForm: false);
    expect(find.byType(CreateCollabChipSkeleton), findsNWidgets(2));
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(MutandeMotion.ui);

    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('@cursor'), findsOneWidget);
    expect(find.byType(CreateCollabChipSkeleton), findsNothing);
    expect(find.byType(MutandeStaggerScope), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(MutandeStaggerIn),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  test('collabFileSizeLabel formats bytes', () {
    expect(collabFileSizeLabel(null), isNull);
    expect(collabFileSizeLabel(400), '400 B');
    expect(collabFileSizeLabel(2048), '2.0 KB');
    expect(collabFileSizeLabel(12000), '12 KB');
  });

  testWidgets('create collab sends a link artifact', (tester) async {
    Map<String, dynamic>? created;
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      if (method == 'create_collab') {
        created = params;
        return {
          'collab': {
            'id': 'c1',
            'name': 'Launch',
            'encryption_mode': 'e2e',
            'lists': <Map<String, dynamic>>[],
            'artifacts': [
              {
                'kind': 'link',
                'label': 'Staging',
                'url': 'https://staging.example.com',
              },
            ],
          },
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(tester, daemon: daemon);

    await tester.tap(find.text('@cursor'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Launch');

    await tester.ensureVisible(find.byKey(const Key('collab-artifact-label')));
    await tester.enterText(
      find.byKey(const Key('collab-artifact-label')),
      'Staging',
    );
    await tester.enterText(
      find.byKey(const Key('collab-artifact-url')),
      'https://staging.example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('collab-add-link')));
    await tester.tap(find.byKey(const Key('collab-add-link')));
    await tester.pump();
    expect(find.text('Staging'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(created, isNotNull);
    final artifacts = (created!['artifacts'] as List).cast<Map>();
    expect(
      artifacts.any(
        (a) => a['kind'] == 'link' && a['url'] == 'https://staging.example.com',
      ),
      isTrue,
    );
  });

  testWidgets('picking a local file shows a chip and create includes it', (
    tester,
  ) async {
    Map<String, dynamic>? created;
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      if (method == 'create_collab') {
        created = params;
        return {
          'collab': {
            'id': 'c1',
            'name': 'Launch',
            'encryption_mode': 'e2e',
            'lists': <Map<String, dynamic>>[],
            'artifacts': [
              {'kind': 'file', 'name': 'brief.md', 'path': '/tmp/brief.md'},
            ],
          },
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(
      tester,
      daemon: daemon,
      pickFiles: () async => [
        const CollabPendingFile(
          name: 'brief.md',
          path: '/tmp/brief.md',
          mime: 'text/markdown',
          size: 2048,
        ),
      ],
    );

    await tester.tap(find.text('@cursor'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Launch');

    await tester.ensureVisible(find.byKey(const Key('collab-attach-file')));
    await tester.tap(find.byKey(const Key('collab-attach-file')));
    await tester.pump();

    expect(
      find.byKey(const Key('collab-file-chip-/tmp/brief.md')),
      findsOneWidget,
    );
    expect(find.text('brief.md'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(created, isNotNull);
    final artifacts = (created!['artifacts'] as List).cast<Map>();
    expect(
      artifacts.any(
        (a) =>
            a['kind'] == 'file' &&
            a['path'] == '/tmp/brief.md' &&
            a['name'] == 'brief.md',
      ),
      isTrue,
    );
  });

  testWidgets('file and link artifacts both round-trip on create', (
    tester,
  ) async {
    Map<String, dynamic>? created;
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_contacts') {
        return {'contacts': []};
      }
      if (method == 'list_agents') {
        return {
          'agents': [
            {'id': 'a1', 'slug': 'cursor', 'transport': 'sidecar'},
          ],
        };
      }
      if (method == 'create_collab') {
        created = params;
        return {
          'collab': {
            'id': 'c1',
            'name': 'Launch',
            'encryption_mode': 'e2e',
            'lists': <Map<String, dynamic>>[],
            'artifacts': <Map<String, dynamic>>[],
          },
        };
      }
      return {'ok': true};
    });

    await _pumpSheet(
      tester,
      daemon: daemon,
      pickFiles: () async => [
        const CollabPendingFile(
          name: 'notes.txt',
          path: '/tmp/notes.txt',
          size: 400,
        ),
      ],
    );

    await tester.tap(find.text('@cursor'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Launch');

    await tester.ensureVisible(find.byKey(const Key('collab-attach-file')));
    await tester.tap(find.byKey(const Key('collab-attach-file')));
    await tester.pump();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('400 B'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('collab-artifact-label')));
    await tester.enterText(
      find.byKey(const Key('collab-artifact-label')),
      'Staging',
    );
    await tester.enterText(
      find.byKey(const Key('collab-artifact-url')),
      'https://staging.example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('collab-add-link')));
    await tester.tap(find.byKey(const Key('collab-add-link')));
    await tester.pump();
    expect(
      find.byKey(const Key('collab-link-chip-https://staging.example.com')),
      findsOneWidget,
    );
    expect(find.text('Staging'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    final artifacts = (created!['artifacts'] as List).cast<Map>();
    expect(
      artifacts.any(
        (a) => a['kind'] == 'file' && a['path'] == '/tmp/notes.txt',
      ),
      isTrue,
    );
    expect(
      artifacts.any(
        (a) => a['kind'] == 'link' && a['url'] == 'https://staging.example.com',
      ),
      isTrue,
    );
  });
}
