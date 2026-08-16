import 'dart:convert';

import 'package:app/screens/collab_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/collab/collab_overview.dart';
import 'package:app/widgets/collab/collab_project_dossier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

CollabDetail _detail({
  List<Map<String, dynamic>> lists = const [
    {'id': 'l1', 'name': 'Backlog', 'position': 0},
    {'id': 'l2', 'name': 'Doing', 'position': 1},
    {'id': 'l3', 'name': 'Done', 'position': 2},
  ],
  List<Map<String, dynamic>> cards = const [],
  List<String> steerers = const ['alice@acme'],
  List<Map<String, dynamic>> roster = const [
    {'user_id': 'u1', 'agent_id': 'a1', 'address': 'alice@acme/claude'},
  ],
}) {
  return CollabDetail.fromJson({
    'id': 'c1',
    'name': 'Launch',
    'encryption_mode': 'e2e',
    'lists': lists,
    'cards': cards,
    'steerers': [
      for (final h in steerers) {'user_id': 'u', 'handle': h},
    ],
    'roster': roster,
  });
}

void main() {
  test('lane bucket uses name then position', () {
    final lists = [
      const CollabListView(id: 'a', name: 'Icebox', position: 0),
      const CollabListView(id: 'b', name: 'Now', position: 1),
      const CollabListView(id: 'c', name: 'Ship', position: 2),
    ];
    expect(collabLaneBucket(lists, 'a'), CollabLaneBucket.backlog);
    expect(collabLaneBucket(lists, 'b'), CollabLaneBucket.doing);
    expect(collabLaneBucket(lists, 'c'), CollabLaneBucket.done);
    expect(collabLaneBucket(lists, null), CollabLaneBucket.backlog);
    final named = [const CollabListView(id: 'x', name: 'Doing', position: 0)];
    expect(collabLaneBucket(named, 'x'), CollabLaneBucket.doing);
  });

  test('overview tallies open / doing / needs you and latest activity', () {
    final overview = CollabOverview.fromDetail(
      _detail(
        cards: [
          {
            'id': 't1',
            'lane_id': 'l2',
            'status': 'open',
            'your_status': 'pending',
            'assigned_to': 'alice@acme/claude',
            'updated_at': '2026-08-16T12:00:00Z',
          },
          {
            'id': 't2',
            'lane_id': 'l1',
            'status': 'open',
            'updated_at': '2026-08-15T12:00:00Z',
          },
          {
            'id': 't3',
            'lane_id': 'l3',
            'status': 'closed',
            'assigned_to': 'bob@acme',
            'updated_at': '2026-08-14T12:00:00Z',
          },
        ],
      ),
    );
    expect(overview.open, 2);
    expect(overview.doing, 1);
    expect(overview.needsYou, 1);
    expect(overview.lastActivityAt, '2026-08-16T12:00:00Z');
  });

  test('collab artifacts keep resource and card provenance', () async {
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'get_collab');
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'collab': {
                'id': 't1',
                'name': 'Pilot',
                'encryption_mode': 'e2e',
                'lists': <Object?>[],
                'artifacts': [
                  {
                    'thread_id': 't1',
                    'message_id': 'm1',
                    'card_title': 'Pilot feedback triage',
                    'from_handle': 'alice@acme/claude',
                    'created_at': '2026-08-16T12:00:00Z',
                    'name': 'pilot-feedback.md',
                    'mime': 'text/markdown',
                    'size': 16,
                  },
                ],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
    );
    final artifacts = (await daemon.getCollab('t1')).artifacts;
    expect(artifacts, hasLength(1));
    expect(artifacts.single.resource.name, 'pilot-feedback.md');
    expect(artifacts.single.cardTitle, 'Pilot feedback triage');
    expect(artifacts.single.threadId, 't1');
    expect(artifacts.single.messageId, 'm1');
    expect(artifacts.single.kind, 'file');
    expect(artifacts.single.isLink, isFalse);
  });

  test('link artifacts parse distinctly from files', () {
    final arts = collabArtifactsFromJson([
      {
        'kind': 'link',
        'label': 'Staging',
        'url': 'https://staging.example.com',
        'from_handle': 'Alice@Acme',
      },
      {'kind': 'file', 'name': 'brief.md', 'mime': 'text/markdown'},
    ]);
    expect(arts, hasLength(2));
    expect(arts[0].isLink, isTrue);
    expect(arts[0].title, 'Staging');
    expect(arts[0].url, 'https://staging.example.com');
    expect(arts[0].fromHandle, 'alice@acme');
    expect(arts[1].isLink, isFalse);
    expect(arts[1].resource.name, 'brief.md');
  });

  test('null or omitted artifacts parse as empty, never throw', () {
    expect(collabArtifactsFromJson(null), isEmpty);
    expect(collabArtifactsFromJson('nope'), isEmpty);
    expect(
      CollabDetail.fromJson({
        'id': 'c1',
        'name': 'Launch',
        'encryption_mode': 'e2e',
        'lists': <Object?>[],
      }).artifacts,
      isEmpty,
    );
    expect(
      CollabDetail.fromJson({
        'id': 'c1',
        'name': 'Launch',
        'encryption_mode': 'e2e',
        'lists': <Object?>[],
        'artifacts': null,
      }).artifacts,
      isEmpty,
    );
    expect(
      CollabDetail.fromJson({
        'id': 'c1',
        'name': 'Launch',
        'lists': <Object?>[],
        'artifacts': [
          {'thread_id': 't1', 'message_id': 'm1', 'name': 'notes.md'},
          'skip-me',
          null,
        ],
      }).artifacts,
      hasLength(1),
    );
    expect(
      const CollabDetail(
        id: 'c1',
        name: 'Launch',
        encryptionMode: 'e2e',
        lists: [],
        artifacts: null,
      ).artifacts,
      isEmpty,
    );
  });

  testWidgets('artifact dossier leads into current position and board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String?;
        if (method == 'get_collab') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'id': 'c1',
                'name': 'Launch',
                'encryption_mode': 'e2e',
                'instructions':
                    'Ship the alpha to trusted hands and keep onboarding calm.',
                'lists': [
                  {'id': 'l1', 'name': 'Backlog', 'position': 0},
                  {'id': 'l2', 'name': 'Doing', 'position': 1},
                  {'id': 'l3', 'name': 'Done', 'position': 2},
                ],
                'cards': const [],
                'learnings': [
                  {
                    'id': 'm1',
                    'created_at': '2026-08-16T12:00:00Z',
                    'from_handle': 'alice@acme/claude',
                    'notes': 'Restart uses the bundled courier.',
                  },
                ],
                'steerers': [
                  {'user_id': 'u1', 'handle': 'alice@acme'},
                ],
                'roster': [
                  {
                    'user_id': 'u1',
                    'agent_id': 'a1',
                    'address': 'alice@acme/claude',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'collabs': [], 'portfolio': {}},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
      requestTimeout: const Duration(seconds: 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: CollabPanel(
              daemon: daemon,
              handle: 'alice@acme',
              initialCollabId: 'c1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Brain'), findsOneWidget);
    expect(find.byKey(const Key('collab-seal')), findsOneWidget);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsNothing,
    );
    expect(find.text('PROJECT INSTRUCTIONS'), findsOneWidget);
    expect(
      find.text('Ship the alpha to trusted hands and keep onboarding calm.'),
      findsOneWidget,
    );
    expect(find.text('ARTIFACTS'), findsNothing);
    expect(find.text('ARTIFACT DOSSIER'), findsNothing);
    expect(
      find.text('No artifacts yet. Files shared in card threads gather here.'),
      findsNothing,
    );
    expect(find.text('What this collab remembers'), findsOneWidget);
    expect(find.text('Restart uses the bundled courier.'), findsOneWidget);
    expect(find.text('CURRENT POSITION'), findsOneWidget);
    expect(find.text('Backlog'), findsOneWidget);
    await tester.tap(find.text('Brain'));
    await tester.pumpAndSettle();
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Learnings'), findsOneWidget);
    expect(find.text('ARTIFACTS'), findsNothing);
  });

  testWidgets('null artifacts do not paint Flutter ErrorWidget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'get_collab') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'collab': {
                  'id': 'c1',
                  'name': 'Launch',
                  'encryption_mode': 'e2e',
                  'lists': [
                    {'id': 'l1', 'name': 'Backlog', 'position': 0},
                  ],
                  'artifacts': null,
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'collabs': [], 'portfolio': {}},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      httpToken: 'test-token',
      requestTimeout: const Duration(seconds: 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: CollabPanel(
              daemon: daemon,
              handle: 'alice@acme',
              initialCollabId: 'c1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('ARTIFACTS'), findsNothing);
    expect(
      find.text('No artifacts yet. Files shared in card threads gather here.'),
      findsNothing,
    );
  });

  testWidgets('dossier shows a link artifact as a link chip', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final collab = CollabDetail.fromJson({
      'id': 'c1',
      'name': 'Launch',
      'encryption_mode': 'e2e',
      'lists': [
        {'id': 'l1', 'name': 'Backlog', 'position': 0},
      ],
      'artifacts': [
        {
          'kind': 'link',
          'label': 'Staging',
          'url': 'https://staging.example.com',
          'from_handle': 'alice@acme',
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: CollabProjectDossier(
              collab: collab,
              artifacts: collab.artifacts,
              artifactsLoading: false,
              board: const SizedBox.shrink(),
              onOpenBrain: () {},
              onOpenCard: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('ARTIFACTS'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('https://staging.example.com'), findsNothing);
  });
}
