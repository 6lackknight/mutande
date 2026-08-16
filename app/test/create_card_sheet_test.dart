import 'dart:convert';

import 'package:app/screens/collab_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/create_card_sheet.dart';
import 'package:app/widgets/mutande_sheet.dart';
import 'package:app/widgets/mutande_stagger.dart';
import 'package:app/widgets/thread_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:macos_ui/macos_ui.dart';

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

DaemonClient _mockDaemon(Future<http.Response> Function(http.Request) handler) {
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
  String collabId = 'c1',
  String laneId = 'doing',
  String laneName = 'Doing',
  bool reduce = false,
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
          width: 420,
          height: 400,
          child: CreateCardSheet(
            daemon: daemon,
            collabId: collabId,
            laneId: laneId,
            laneName: laneName,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('mutandeSheetAlignment grows from the source control', () {
    expect(mutandeSheetAlignment(Rect.zero, Size.zero), Alignment.center);
    final bottomRight = mutandeSheetAlignment(
      const Rect.fromLTWH(1100, 600, 80, 36),
      const Size(1280, 720),
    );
    expect(bottomRight.x, greaterThan(0));
    expect(bottomRight.y, greaterThan(0));
  });

  testWidgets('chrome is visible immediately — title is not a bone', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.text('New card'), findsOneWidget);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('FIRST MESSAGE'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('e.g. ship invites'), findsOneWidget);
    expect(find.text('Filed in Doing.'), findsOneWidget);
    expect(find.byType(CreateCollabChipSkeleton), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MutandeStaggerIn),
        matching: find.byKey(const Key('card-title-field')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('card-notes-field')), findsNothing);
  });

  testWidgets('create with title files a thread on collab + lane', (
    tester,
  ) async {
    Map<String, dynamic>? created;
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'create_collab_card') {
        created = body['params'] as Map<String, dynamic>?;
        return _rpcOk(body['id'], {'thread_id': 'th-card-1'});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(
      tester,
      daemon: daemon,
      collabId: 'c-launch',
      laneId: 'l-doing',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(created, isNull);
    expect(find.text('Title this card.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('card-title-field')),
      'Ship invites',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(created, isNotNull);
    expect(created!['collab_id'], 'c-launch');
    expect(created!['lane_id'], 'l-doing');
    expect(created!['subject'], 'Ship invites');
    expect(created!.containsKey('notes'), isFalse);
  });

  testWidgets('create failure keeps title and shows copy', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'create_collab_card') {
        return _rpcErr(
          body['id'],
          'hub error 404 Not Found: {"error":"not_found"}',
        );
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);
    await tester.enterText(
      find.byKey(const Key('card-title-field')),
      'Keep me',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(find.text("This hub doesn't support collab yet."), findsOneWidget);
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('disableAnimations snaps inner stagger without throw', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon, reduce: true);
    expect(find.text('New card'), findsOneWidget);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Filed in Doing.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MutandeStaggerIn),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  testWidgets('board New card opens stone sheet not AlertDialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'get_collab') {
        return _rpcOk(body['id'], {
          'collab': {
            'id': 'c1',
            'name': 'Launch',
            'encryption_mode': 'e2e',
            'lists': [
              {'id': 'l1', 'name': 'Backlog', 'position': 0},
              {'id': 'l2', 'name': 'Doing', 'position': 1},
              {'id': 'l3', 'name': 'Done', 'position': 2},
            ],
            'cards': [],
          },
        });
      }
      return _rpcOk(body['id'], {'collabs': [], 'portfolio': {}});
    });

    await tester.pumpWidget(
      MacosTheme(
        data: mutandeMacosTheme(),
        child: MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collab-new-card-l2')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('collab-new-card-l2')));
    await tester.tap(find.byKey(const Key('collab-new-card-l2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CreateCardSheet), findsOneWidget);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('Filed in Doing.'), findsOneWidget);
  });
}
