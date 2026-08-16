import 'dart:async';
import 'dart:convert';

import 'package:app/screens/collab_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/collab/collab_activity_calendar.dart';
import 'package:app/widgets/collab/collab_dash_card.dart';
import 'package:app/widgets/collab/collab_lane_donut.dart';
import 'package:app/widgets/collab/collab_metric_row.dart';
import 'package:app/widgets/collab/collab_projects_table.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:app/widgets/home_chrome_pills.dart';
import 'package:app/widgets/thread_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<CollabSummary> _collabs() {
  return [
    CollabSummary.fromJson({
      'id': 'c1',
      'name': 'Launch',
      'encryption_mode': 'e2e',
      'card_count': 4,
      'open': 3,
      'backlog': 1,
      'doing': 2,
      'done': 0,
      'needs_you': 1,
      'last_card_updated_at': '2026-08-15T12:00:00Z',
      'steerers': [
        {'user_id': 'u1', 'handle': 'alice@acme'},
        {'user_id': 'u2', 'handle': 'bob@acme'},
      ],
      'roster': [
        {
          'user_id': 'u1',
          'agent_id': 'a1',
          'address': 'alice@acme/cursor',
        },
      ],
    }),
    CollabSummary.fromJson({
      'id': 'c2',
      'name': 'Ops',
      'encryption_mode': 'app_envelope',
      'card_count': 2,
      'open': 2,
      'backlog': 2,
      'doing': 0,
      'done': 0,
      'needs_you': 0,
      'updated_at': '2026-08-14T12:00:00Z',
      'steerers': [
        {'user_id': 'u1', 'handle': 'alice@acme'},
      ],
    }),
  ];
}

CollabPortfolio _portfolio() {
  return CollabPortfolio.fromJson({
    'activity': [
      {'date': '2026-08-15', 'count': 4},
    ],
    'lane_totals': {'backlog': 2, 'doing': 2, 'done': 1},
    'totals': {'collabs': 2, 'open': 5, 'doing': 2, 'needs_you': 1},
    'recent': [
      {
        'thread_id': 't1',
        'collab_id': 'c1',
        'collab_name': 'Launch',
        'from': 'alice@acme/cursor',
        'audience': 'bob@acme',
        'last_subject': 'Pilot brief',
        'updated_at': '2026-08-16T13:26:00Z',
        'needs_you': true,
      },
      {
        'thread_id': 't2',
        'collab_id': 'c2',
        'collab_name': 'Ops',
        'from': 'bob@acme',
        'audience': 'alice@acme/claude',
        'updated_at': '2026-08-16T09:00:00Z',
        'needs_you': false,
      },
    ],
  }, _collabs());
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: Scaffold(body: SizedBox(width: 1280, height: 800, child: child)),
    ),
  );
}

void main() {
  test('CollabPortfolio.fromJson falls back to collab tallies', () {
    final collabs = _collabs();
    final portfolio = CollabPortfolio.fromJson(null, collabs);
    expect(portfolio.totals.collabs, 2);
    expect(portfolio.totals.open, 5);
    expect(portfolio.totals.doing, 2);
    expect(portfolio.totals.needsYou, 1);
    expect(portfolio.recent, isEmpty);
    expect(collabs[0].isActive, isTrue);
  });

  test('CollabPortfolio.fromJson without recent key yields empty list', () {
    final portfolio = CollabPortfolio.fromJson({
      'totals': {'collabs': 1, 'open': 0, 'doing': 0, 'needs_you': 0},
    }, const []);
    expect(portfolio.recent, isEmpty);
  });

  test('CollabPortfolio.fromJson keeps recent threads', () {
    final p = _portfolio();
    expect(p.recent, hasLength(2));
    expect(p.recent.first.threadId, 't1');
    expect(p.recent.first.lastSubject, 'Pilot brief');
    expect(p.recent.first.needsYou, isTrue);
    expect(p.recent[1].collabName, 'Ops');
  });

  test('recentFromThreads maps filed threads newest first', () {
    final recent = recentFromThreads([
      ThreadSummary(
        id: 'old',
        kind: 'direct',
        status: 'open',
        from: 'alice@acme',
        audience: 'bob@acme',
        lastSubject: 'Old',
        updatedAt: '2026-08-14T12:00:00Z',
        collabId: 'c1',
        collabName: 'Launch',
      ),
      ThreadSummary(
        id: 'plain',
        kind: 'direct',
        status: 'open',
        from: 'alice@acme',
        audience: 'bob@acme',
        updatedAt: '2026-08-16T12:00:00Z',
      ),
      ThreadSummary(
        id: 'new',
        kind: 'direct',
        status: 'open',
        from: 'alice@acme',
        audience: 'bob@acme',
        yourStatus: 'pending',
        lastFrom: 'bob@acme/cursor',
        lastSubject: 'Pilot brief',
        updatedAt: '2026-08-16T13:00:00Z',
        collabId: 'c2',
        collabName: 'Ops',
      ),
    ]);
    expect(recent, hasLength(2));
    expect(recent.first.threadId, 'new');
    expect(recent.first.from, 'bob@acme/cursor');
    expect(recent.first.needsYou, isTrue);
    expect(recent.first.lastSubject, 'Pilot brief');
    expect(recent.last.threadId, 'old');
    expect(recent.last.from, 'alice@acme');
    expect(recent.last.needsYou, isFalse);
  });

  test('recentFromThreads caps at six and skips empty collab fields', () {
    final threads = [
      for (var i = 0; i < 8; i++)
        ThreadSummary(
          id: 't$i',
          kind: 'direct',
          status: 'open',
          from: 'alice@acme',
          audience: 'bob@acme',
          updatedAt: '2026-08-16T0$i:00:00Z',
          collabId: 'c1',
          collabName: 'Launch',
        ),
    ];
    expect(recentFromThreads(threads), hasLength(6));
    expect(recentFromThreads(threads).first.threadId, 't7');
    expect(recentFromThreads(const []), isEmpty);
  });

  test('CollabSummary.fromJson keeps steerers and roster for faces', () {
    final launch = _collabs()[0];
    expect(launch.steererHandles, ['alice@acme', 'bob@acme']);
    expect(launch.roster.single.address, 'alice@acme/cursor');
    expect(launch.backlogCount, 1);
    expect(launch.doingCount, 2);
    expect(launch.doneCount, 0);
  });

  test('CollabSummary.fromJson treats missing backlog as remainder of open', () {
    final row = CollabSummary.fromJson({
      'id': 'c3',
      'name': 'Legacy',
      'encryption_mode': 'e2e',
      'open': 5,
      'doing': 2,
    });
    expect(row.backlogCount, 3);
    expect(row.doneCount, 0);
  });

  testWidgets('metric row shows portfolio counts and create tile', (
    WidgetTester tester,
  ) async {
    var created = false;
    await _pump(
      tester,
      CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollabMetricRow(
              totals: _portfolio().totals,
              onCreate: (_) => created = true,
            ),
          ),
        ],
      ),
    );
    expect(find.text('Collabs'), findsOneWidget);
    expect(find.text('Open cards'), findsOneWidget);
    expect(find.text('In Doing'), findsOneWidget);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('New collab'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collab-create-tile')));
    expect(created, isTrue);
  });

  testWidgets('calendar and donut render activity copy', (
    WidgetTester tester,
  ) async {
    final p = _portfolio();
    await _pump(
      tester,
      Column(
        children: [
          CollabActivityCalendar(activity: p.activity),
          CollabLaneDonut(lanes: p.laneTotals),
        ],
      ),
    );
    expect(find.text('Card updates across all collabs'), findsOneWidget);
    expect(find.text('Open cards by lane'), findsOneWidget);
    expect(find.text('Backlog'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.byType(CollabActivityCalendar), findsOneWidget);
  });

  testWidgets('activity card lists latest threads beside the heatmap', (
    WidgetTester tester,
  ) async {
    final p = _portfolio();
    CollabRecentThread? opened;
    await _pump(
      tester,
      CollabActivityCalendar(
        activity: p.activity,
        recent: p.recent,
        myHandle: 'alice@acme',
        now: DateTime.utc(2026, 8, 16, 14),
        onOpenThread: (item) => opened = item,
      ),
    );
    expect(find.text('Pilot brief'), findsOneWidget);
    expect(find.text('@cursor · launch'), findsOneWidget);
    expect(find.text('bob@acme · ops'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collab-activity-thread-t1')));
    expect(opened?.threadId, 't1');
    expect(opened?.collabId, 'c1');
  });

  testWidgets('activity and lanes share a fixed chart-row height', (
    WidgetTester tester,
  ) async {
    final p = _portfolio();
    final recent = [
      for (var i = 0; i < 5; i++)
        CollabRecentThread(
          threadId: 't$i',
          collabId: 'c1',
          collabName: 'Launch',
          from: 'alice@acme/cursor',
          audience: 'bob@acme',
          lastSubject: 'Update $i',
          updatedAt: '2026-08-16T13:0$i:00Z',
          needsYou: i == 0,
        ),
    ];
    await _pump(
      tester,
      Row(
        children: [
          Expanded(
            flex: 3,
            child: CollabActivityCalendar(
              activity: p.activity,
              recent: recent,
              now: DateTime.utc(2026, 8, 16, 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: CollabLaneDonut(lanes: p.laneTotals),
          ),
        ],
      ),
    );
    expect(
      tester.getSize(find.byType(CollabActivityCalendar)).height,
      kCollabChartCardHeight,
    );
    expect(
      tester.getSize(find.byType(CollabLaneDonut)).height,
      kCollabChartCardHeight,
    );
    final heat = tester.getSize(
      find.byKey(const Key('collab-activity-heatmap-pane')),
    );
    final feed = tester.getSize(
      find.byKey(const Key('collab-activity-feed-pane')),
    );
    expect(heat.width, closeTo(feed.width, 0.5));
    expect(find.text('Update 0'), findsOneWidget);
    expect(
      find.byKey(const Key('collab-activity-thread-t4'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('projects table sorts needs-you first and opens on tap', (
    WidgetTester tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      SingleChildScrollView(
        child: CollabProjectsTable(
          collabs: _collabs(),
          onOpen: (c) => opened = c.id,
        ),
      ),
    );
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Ops'), findsOneWidget);
    expect(find.text('Collabs'), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-recent')), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-name')), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Collab'), findsNothing);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Lanes'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('active'), findsWidgets);
    expect(find.text('Active'), findsNothing);
    expect(find.text('3 open'), findsOneWidget);
    expect(find.text('2 doing'), findsOneWidget);
    expect(find.text('1 needs you'), findsOneWidget);
    expect(find.text('2 open'), findsOneWidget);
    expect(find.text('0 doing'), findsNothing);
    expect(find.text('0 needs you'), findsNothing);
    expect(find.byType(PersonAvatar), findsWidgets);
    expect(find.byKey(const Key('collab-lane-bar-c1')), findsOneWidget);
    expect(find.byKey(const Key('collab-lane-bar-c2')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('collab-row-c1'))).height,
      greaterThanOrEqualTo(56),
    );
    final launch = tester.getTopLeft(find.text('Launch'));
    final ops = tester.getTopLeft(find.text('Ops'));
    expect(launch.dy < ops.dy, isTrue);
    await tester.tap(find.byKey(const Key('collab-row-c1')));
    expect(opened, 'c1');
  });

  testWidgets('sort toggles reorder collabs by recent then name', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      SingleChildScrollView(
        child: CollabProjectsTable(
          collabs: [
            CollabSummary.fromJson({
              'id': 'c-b',
              'name': 'Bravo',
              'encryption_mode': 'e2e',
              'updated_at': '2026-08-16T12:00:00Z',
            }),
            CollabSummary.fromJson({
              'id': 'c-a',
              'name': 'Alpha',
              'encryption_mode': 'e2e',
              'updated_at': '2026-08-10T12:00:00Z',
            }),
          ],
          sort: MutandeListSort.name,
          onOpen: (_) {},
        ),
      ),
    );
    final alpha = tester.getTopLeft(find.text('Alpha'));
    final bravo = tester.getTopLeft(find.text('Bravo'));
    expect(alpha.dy < bravo.dy, isTrue);
  });

  testWidgets('collab home loading keeps filters and skeletons the table', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<void>();
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        await gate.future;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'collabs': [
                {
                  'id': 'c1',
                  'name': 'Launch',
                  'encryption_mode': 'e2e',
                  'card_count': 1,
                },
              ],
              'portfolio': {
                'totals': {
                  'collabs': 1,
                  'open': 1,
                  'doing': 0,
                  'needs_you': 0,
                },
              },
              'threads': <Object?>[],
              'contacts': <Object?>[],
            },
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
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 800,
              child: CollabPanel(daemon: daemon, handle: 'alice@acme'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('collab-archived-filter')), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-recent')), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-name')), findsOneWidget);
    expect(find.text('Collabs'), findsWidgets);
    expect(find.text('Open cards'), findsOneWidget);
    expect(find.text('New collab'), findsOneWidget);
    expect(find.byType(CollabTableRowsSkeleton), findsOneWidget);
    expect(find.text('Launch'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CollabTableRowsSkeleton), findsNothing);
    expect(find.text('Launch'), findsWidgets);
    expect(find.byKey(const Key('collab-archived-filter')), findsOneWidget);
  });

  testWidgets('collab home sort control switches name order', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'collabs': [
                {
                  'id': 'c-b',
                  'name': 'Bravo',
                  'encryption_mode': 'e2e',
                  'updated_at': '2026-08-16T12:00:00Z',
                },
                {
                  'id': 'c-a',
                  'name': 'Alpha',
                  'encryption_mode': 'e2e',
                  'updated_at': '2026-08-10T12:00:00Z',
                },
              ],
              'portfolio': {
                'totals': {
                  'collabs': 2,
                  'open': 0,
                  'doing': 0,
                  'needs_you': 0,
                },
              },
              'threads': <Object?>[],
              'contacts': <Object?>[],
            },
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
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 800,
              child: CollabPanel(daemon: daemon, handle: 'alice@acme'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collab-sort-recent')), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-name')), findsOneWidget);
    var alpha = tester.getTopLeft(find.text('Alpha'));
    var bravo = tester.getTopLeft(find.text('Bravo'));
    expect(bravo.dy < alpha.dy, isTrue);
    await tester.tap(find.byKey(const Key('collab-sort-name')));
    await tester.pump();
    alpha = tester.getTopLeft(find.text('Alpha'));
    bravo = tester.getTopLeft(find.text('Bravo'));
    expect(alpha.dy < bravo.dy, isTrue);
  });

  testWidgets('Archived filter lists archived boards only', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = DaemonClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String?;
        if (method == 'list_collabs') {
          final params = body['params'] as Map<String, dynamic>? ?? {};
          final archived = params['include_archived'] == true;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'collabs': [
                  {
                    'id': archived ? 'c-old' : 'c1',
                    'name': archived ? 'Old launch' : 'Launch',
                    'encryption_mode': 'e2e',
                    'status': archived ? 'archived' : 'open',
                    'card_count': 1,
                  },
                ],
                'portfolio': {
                  'totals': {
                    'collabs': 1,
                    'open': archived ? 0 : 1,
                    'doing': 0,
                    'needs_you': 0,
                  },
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
            'result': method == 'list_threads'
                ? {'threads': []}
                : {'contacts': []},
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
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 800,
              child: CollabPanel(daemon: daemon, handle: 'alice@acme'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Launch'), findsWidgets);
    expect(find.text('Old launch'), findsNothing);
    expect(find.text('Title'), findsOneWidget);
    expect(find.byKey(const Key('collab-archived-filter')), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-recent')), findsOneWidget);
    expect(find.byKey(const Key('collab-sort-name')), findsOneWidget);
    final archivedFilter = tester.getRect(
      find.byKey(const Key('collab-archived-filter')),
    );
    final sortRecent = tester.getRect(
      find.byKey(const Key('collab-sort-recent')),
    );
    final sortName = tester.getRect(find.byKey(const Key('collab-sort-name')));
    final tableTitle = find
        .text('Collabs')
        .evaluate()
        .map((el) => tester.getRect(find.byWidget(el.widget)))
        .reduce((a, b) => a.top > b.top ? a : b);
    expect(archivedFilter.center.dy, closeTo(tableTitle.center.dy, 12));
    expect(sortRecent.center.dy, closeTo(tableTitle.center.dy, 12));
    expect(sortName.center.dy, closeTo(tableTitle.center.dy, 12));
    expect(tableTitle.left < sortRecent.left, isTrue);
    expect(sortRecent.left < sortName.left, isTrue);
    expect(sortName.right < archivedFilter.left, isTrue);
    expect(
      archivedFilter.right,
      closeTo(tester.getRect(find.text('Updated')).right, 16),
    );
    await tester.tap(find.byKey(const Key('collab-archived-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Old launch'), findsOneWidget);
    expect(find.text('Launch'), findsNothing);
    expect(find.text('Archived'), findsWidgets);
    expect(find.text('New collab'), findsNothing);
  });
}
