import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/collab/collab_activity_calendar.dart';
import 'package:app/widgets/collab/collab_lane_donut.dart';
import 'package:app/widgets/collab/collab_metric_row.dart';
import 'package:app/widgets/collab/collab_projects_table.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(collabs[0].isActive, isTrue);
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
    expect(find.text('Active'), findsWidgets);
    expect(find.text('3 open'), findsOneWidget);
    expect(find.text('2 doing'), findsOneWidget);
    expect(find.text('1 needs you'), findsOneWidget);
    expect(find.text('2 open'), findsOneWidget);
    expect(find.text('0 doing'), findsNothing);
    expect(find.text('0 needs you'), findsNothing);
    expect(find.byType(PersonAvatar), findsWidgets);
    expect(find.byKey(const Key('collab-lane-bar-c1')), findsOneWidget);
    expect(find.byKey(const Key('collab-lane-bar-c2')), findsOneWidget);
    final launch = tester.getTopLeft(find.text('Launch'));
    final ops = tester.getTopLeft(find.text('Ops'));
    expect(launch.dy < ops.dy, isTrue);
    await tester.tap(find.byKey(const Key('collab-row-c1')));
    expect(opened, 'c1');
  });
}
