import 'dart:async';

import 'package:app/screens/collab_screen.dart';
import 'package:app/screens/threads_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/daemon_errors.dart';
import 'fake_daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/util/clock_format.dart';
import 'package:app/widgets/ai_host_icon.dart';
import 'package:app/widgets/collab/collab_overview.dart';
import 'package:app/widgets/collab/collab_project_dossier.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:app/widgets/mutande_stagger.dart';
import 'package:app/widgets/thread_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    final daemon = rpcDaemon((method, params) async {
        expect(method, 'get_collab');
        return {
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
            };
      });
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
    final daemon = rpcDaemon((method, params) async {
        if (method == 'get_collab') {
          return {
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
              };
        }
        return {'collabs': [], 'portfolio': {}};
      });
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
    expect(find.byKey(const Key('collab-mode-board')), findsOneWidget);
    expect(find.byKey(const Key('collab-mode-brain')), findsOneWidget);
    expect(find.byKey(const Key('collab-mode-manage')), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Brain'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.byIcon(LucideIcons.squareKanban), findsOneWidget);
    expect(find.byIcon(LucideIcons.brain), findsOneWidget);
    expect(find.byIcon(LucideIcons.settings2), findsOneWidget);
    expect(find.byKey(const Key('collab-manage-menu')), findsNothing);
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
    final backlog = tester.getSize(find.byKey(const Key('collab-lane-l1')));
    final doing = tester.getSize(find.byKey(const Key('collab-lane-l2')));
    final done = tester.getSize(find.byKey(const Key('collab-lane-l3')));
    expect(backlog.width, closeTo(doing.width, 1.5));
    expect(doing.width, closeTo(done.width, 1.5));
    expect(backlog.width, greaterThan(300));
    expect(backlog.width + doing.width + done.width, greaterThan(900));
    await tester.tap(find.byKey(const Key('collab-mode-brain')));
    await tester.pumpAndSettle();
    expect(find.text('A one-line learning'), findsOneWidget);
    expect(find.text('PROTOTYPE'), findsNothing);
    expect(find.text('ARTIFACTS'), findsNothing);
    await tester.tap(find.byKey(const Key('collab-mode-board')));
    await tester.pumpAndSettle();
    expect(find.text('CURRENT POSITION'), findsOneWidget);
    expect(find.text('Learnings'), findsNothing);
    await tester.tap(find.byKey(const Key('collab-mode-manage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collab-manage-pane')), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('CURRENT POSITION'), findsNothing);
    expect(find.text('Learnings'), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.text('Launch'), findsOneWidget);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('collab-mode-board')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collab-manage-pane')), findsNothing);
    expect(find.text('CURRENT POSITION'), findsOneWidget);
  });

  testWidgets('null artifacts do not paint Flutter ErrorWidget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = rpcDaemon((method, params) async {
        if (method == 'get_collab') {
          return {
                'collab': {
                  'id': 'c1',
                  'name': 'Launch',
                  'encryption_mode': 'e2e',
                  'lists': [
                    {'id': 'l1', 'name': 'Backlog', 'position': 0},
                  ],
                  'artifacts': null,
                },
              };
        }
        return {'collabs': [], 'portfolio': {}};
      });
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

  testWidgets('open card uses a fullscreen modal with close', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = rpcDaemon((method, params) async {
        if (method == 'get_collab') {
          return {
                'id': 'c1',
                'name': 'Launch',
                'encryption_mode': 'e2e',
                'lists': [
                  {'id': 'l1', 'name': 'Backlog', 'position': 0},
                  {'id': 'l2', 'name': 'Doing', 'position': 1},
                  {'id': 'l3', 'name': 'Done', 'position': 2},
                ],
                'cards': [
                  {
                    'id': 't1',
                    'lane_id': 'l1',
                    'status': 'open',
                    'audience': 'alice@acme/claude',
                    'last_subject': 'Pilot brief',
                  },
                ],
              };
        }
        if (method == 'get_thread') {
          return {
                'thread': {
                  'id': 't1',
                  'kind': 'direct',
                  'status': 'open',
                  'from': 'alice@acme',
                  'audience': 'alice@acme/claude',
                },
                'messages': [],
              };
        }
        return {'collabs': [], 'portfolio': {}, 'contacts': []};
      });
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
    expect(find.text('Pilot brief'), findsOneWidget);
    await tester.ensureVisible(find.text('Pilot brief'));
    await tester.tap(find.text('Pilot brief'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collab-card-close')), findsOneWidget);
    expect(find.byType(ThreadDetailPanel), findsOneWidget);
    expect(find.byKey(const Key('collab-mode-brain')), findsOneWidget);
    expect(find.text('Brain'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collab-card-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collab-card-close')), findsNothing);
    expect(find.byType(ThreadDetailPanel), findsNothing);
    expect(find.text('Pilot brief'), findsOneWidget);
    expect(find.text('Brain'), findsOneWidget);
  });

  testWidgets('board cards use ticket rail chrome', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final updatedAt = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 2))
        .toIso8601String();
    final daemon = rpcDaemon((method, params) async {
        if (method == 'get_collab') {
          return {
                'id': 'c1',
                'name': 'Launch',
                'encryption_mode': 'e2e',
                'lists': [
                  {'id': 'l1', 'name': 'Backlog', 'position': 0},
                  {'id': 'l2', 'name': 'Doing', 'position': 1},
                  {'id': 'l3', 'name': 'Done', 'position': 2},
                ],
                'cards': [
                  {
                    'id': 't1',
                    'lane_id': 'l1',
                    'status': 'open',
                    'from': 'alice@acme/claude',
                    'assigned_to': 'bob@acme/cursor',
                    'last_subject': 'Pilot brief',
                    'your_status': 'pending',
                    'due_on': '2026-09-01',
                    'updated_at': updatedAt,
                    'tags': ['urgent'],
                    'checklist': [
                      {'id': 'i1', 'text': 'Draft', 'done': true},
                      {'id': 'i2', 'text': 'Ship', 'done': false},
                    ],
                  },
                ],
              };
        }
        return {'collabs': [], 'portfolio': {}};
      });
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
    expect(find.text('Pilot brief'), findsOneWidget);
    final due = formatDueOn('2026-09-01');
    final time = formatRelativeTime(updatedAt);
    expect(find.text('$due · $time'), findsOneWidget);
    expect(find.byType(PersonAvatar), findsWidgets);
    expect(find.byType(AiHostIcon), findsWidgets);
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('urgent'), findsNothing);
    expect(find.text('1/2'), findsNothing);
    expect(find.byKey(const Key('collab-card-close')), findsNothing);
  });

  testWidgets('board loading keeps header and dossier chrome', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<void>();
    final daemon = rpcDaemon((method, params) async {
        if (method == 'get_collab') {
          await gate.future;
          return {
                'id': 'c1',
                'name': 'Launch',
                'encryption_mode': 'e2e',
                'instructions': 'Ship the alpha.',
                'lists': [
                  {'id': 'l1', 'name': 'Backlog', 'position': 0},
                  {'id': 'l2', 'name': 'Doing', 'position': 1},
                  {'id': 'l3', 'name': 'Done', 'position': 2},
                ],
                'cards': const [],
              };
        }
        return {'collabs': [], 'portfolio': {}};
      });
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
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
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Boards'), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Brain'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.byKey(const Key('collab-mode-manage')), findsOneWidget);
    expect(find.byKey(const Key('collab-manage-menu')), findsNothing);
    expect(find.text('PROJECT INSTRUCTIONS'), findsOneWidget);
    expect(find.text('ARTIFACTS'), findsOneWidget);
    expect(find.text('What this collab remembers'), findsOneWidget);
    expect(find.text('CURRENT POSITION'), findsOneWidget);
    expect(find.byType(CollabBoardSkeleton), findsOneWidget);
    expect(find.text('Launch'), findsNothing);
    expect(find.text('Ship the alpha.'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CollabBoardSkeleton), findsNothing);
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('PROJECT INSTRUCTIONS'), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Brain'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
  });

  test('isCreator uses user id, not handle', () {
    final collab = CollabDetail.fromJson({
      'id': 'c1',
      'name': 'Launch',
      'encryption_mode': 'app_envelope',
      'created_by': 'u-alice',
      'lists': const [],
      'steerers': [
        {'user_id': 'u-alice', 'handle': 'alice@acme'},
        {'user_id': 'u-bob', 'handle': 'bob@acme'},
      ],
    });
    expect(collab.isCreator(userId: 'u-alice'), isTrue);
    expect(collab.isCreator(userId: 'u-bob'), isFalse);
    expect(collab.isCreator(handle: 'alice@acme'), isTrue);
    expect(collab.isCreator(handle: 'bob@acme'), isFalse);
    expect(collab.isCreator(handle: 'alice@acme', userId: 'u-bob'), isFalse);
    expect(collab.isCreator(handle: 'u-alice'), isFalse);
  });

  testWidgets('brain lets the creator edit instructions', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: CollabPanel(
              daemon: _brainDaemon(creator: true),
              handle: 'alice@acme',
              userId: 'u-alice',
              initialCollabId: 'c1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collab-mode-brain')));
    await tester.pumpAndSettle();
    expect(find.text('PROTOTYPE'), findsNothing);
    expect(find.text('Ship the alpha.'), findsOneWidget);
    expect(find.text('Ship Friday.'), findsOneWidget);
    expect(find.text('A one-line learning'), findsOneWidget);
    expect(find.byType(MutandeStaggerIn), findsOneWidget);
    expect(
      find.byKey(const Key('collab-brain-instructions-edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-field')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-save')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-letter')),
      findsNothing,
    );
    expect(
      find.text('Only the creator can change instructions.'),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('collab-brain-instructions-edit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('collab-brain-instructions-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-save')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-letter')),
      findsNothing,
    );
  });

  testWidgets('brain keeps instructions read-only for a steerer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: CollabPanel(
              daemon: _brainDaemon(creator: false),
              handle: 'bob@acme',
              userId: 'u-bob',
              initialCollabId: 'c1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collab-mode-brain')));
    await tester.pumpAndSettle();
    expect(find.text('PROTOTYPE'), findsNothing);
    expect(
      find.byKey(const Key('collab-brain-instructions-edit')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-field')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-save')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('collab-brain-instructions-letter')),
      findsOneWidget,
    );
    expect(
      find.text('Only the creator can change instructions.'),
      findsOneWidget,
    );
    expect(find.text('Ship the alpha.'), findsOneWidget);
    expect(find.text('A one-line learning'), findsOneWidget);
  });
}

DaemonClient _brainDaemon({required bool creator}) {
  return rpcDaemon((method, params) async {
      if (method == 'get_collab') {
        return {
              'id': 'c1',
              'name': 'Launch',
              'encryption_mode': 'app_envelope',
              'created_by': 'u-alice',
              'instructions': 'Ship the alpha.',
              'lists': [
                {'id': 'l1', 'name': 'Backlog', 'position': 0},
                {'id': 'l2', 'name': 'Doing', 'position': 1},
                {'id': 'l3', 'name': 'Done', 'position': 2},
              ],
              'cards': const [],
              'learnings': [
                {
                  'id': 'ln1',
                  'created_at': '2026-08-16T12:00:00Z',
                  'from_handle': 'alice@acme',
                  'notes': 'Ship Friday.',
                },
              ],
              'steerers': [
                {'user_id': 'u-alice', 'handle': 'alice@acme'},
                {'user_id': 'u-bob', 'handle': 'bob@acme'},
              ],
              'roster': [
                {
                  'user_id': creator ? 'u-alice' : 'u-bob',
                  'agent_id': 'a1',
                  'address': creator ? 'alice@acme/chatgpt' : 'bob@acme/claude',
                },
              ],
            };
      }
      return {'collabs': [], 'portfolio': {}};
    });
}
