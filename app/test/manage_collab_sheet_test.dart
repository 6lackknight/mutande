import 'dart:async';
import 'dart:convert';

import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/manage_collab_sheet.dart';
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

DaemonClient _mockDaemon(
  FutureOr<http.Response> Function(http.Request) handler,
) {
  return DaemonClient(
    httpClient: MockClient((request) async => handler(request)),
    httpToken: 'test-token',
    requestTimeout: const Duration(seconds: 2),
  );
}

DaemonClient _listOnlyDaemon() {
  return _mockDaemon((request) async {
    final body = _rpc(request);
    final method = body['method'] as String?;
    if (method == 'list_contacts' || method == 'list_external_contacts') {
      return _rpcOk(body['id'], {'contacts': []});
    }
    if (method == 'list_agents') {
      return _rpcOk(body['id'], {'agents': []});
    }
    return _rpcOk(body['id'], {'ok': true});
  });
}

Map<String, dynamic> _rpc(http.Request request) {
  return jsonDecode(request.body) as Map<String, dynamic>;
}

Map<String, dynamic> _collabJson({
  String status = 'open',
  List<Map<String, dynamic>>? steerers,
  List<Map<String, dynamic>>? roster,
}) {
  return {
    'id': 'c1',
    'name': 'Launch',
    'encryption_mode': 'e2e',
    'status': status,
    'created_by': 'u-alice',
    'steerers':
        steerers ??
        [
          {'user_id': 'u-alice', 'handle': 'alice@acme'},
          {'user_id': 'u-bob', 'handle': 'bob@acme'},
        ],
    'roster':
        roster ??
        [
          {
            'user_id': 'u-alice',
            'agent_id': 'a1',
            'address': 'alice@acme/cursor',
          },
        ],
    'lists': [
      {'id': 'l1', 'name': 'Backlog', 'position': 0},
    ],
  };
}

Future<void> _waitUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('People').evaluate().isNotEmpty &&
        (find.byKey(const Key('manage-layout-stack')).evaluate().isNotEmpty ||
            find
                .byKey(const Key('manage-layout-columns'))
                .evaluate()
                .isNotEmpty)) {
      if (find.text('Add').evaluate().isNotEmpty ||
          find.text('Archive').evaluate().isNotEmpty ||
          find.text('Unarchive').evaluate().isNotEmpty) {
        return;
      }
    }
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required DaemonClient daemon,
  Map<String, dynamic>? collab,
  Size size = const Size(480, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: Builder(
        builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: ManageCollabSheet(
                  daemon: daemon,
                  collab: CollabDetail.fromJson(collab ?? _collabJson()),
                  handle: 'alice@acme',
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await _waitUntilLoaded(tester);
}

void main() {
  testWidgets('adds and removes people; creator stays locked', (tester) async {
    final calls = <String>[];
    var steerers = [
      {'user_id': 'u-alice', 'handle': 'alice@acme'},
      {'user_id': 'u-bob', 'handle': 'bob@acme'},
    ];
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      calls.add(method ?? '');
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme', 'display_name': 'Bob', 'kind': 'org'},
            {'handle': 'cara@acme', 'display_name': 'Cara', 'kind': 'org'},
          ],
        });
      }
      if (method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {'agents': []});
      }
      if (method == 'add_collab_steerer') {
        steerers = [
          ...steerers,
          {'user_id': 'u-cara', 'handle': 'cara@acme'},
        ];
        return _rpcOk(body['id'], {'collab': _collabJson(steerers: steerers)});
      }
      if (method == 'remove_collab_steerer') {
        steerers = steerers.where((s) => s['user_id'] != 'u-bob').toList();
        return _rpcOk(body['id'], {'collab': _collabJson(steerers: steerers)});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.byKey(const Key('collab-manage-pane')), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.byKey(const Key('manage-layout-stack')), findsOneWidget);
    final creatorRemove = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('manage-person-alice@acme')),
        matching: find.byType(IconButton),
      ),
    );
    expect(creatorRemove.onPressed, isNull);

    await tester.ensureVisible(
      find.byKey(const Key('manage-person-cara@acme')),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('manage-person-cara@acme')),
        matching: find.text('Add'),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('add_collab_steerer'));

    await tester.ensureVisible(find.byKey(const Key('manage-person-bob@acme')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('manage-person-bob@acme')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('remove_collab_steerer'));
  });

  testWidgets('picking an external on an E2E board shows hub-mail copy', (
    tester,
  ) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      if (method == 'list_contacts') {
        return _rpcOk(body['id'], {
          'contacts': [
            {'handle': 'bob@acme', 'kind': 'org'},
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
            },
          ],
        });
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {'agents': []});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);

    expect(find.textContaining('external'), findsOneWidget);
    expect(
      find.textContaining('outside the org — mail goes through the hub'),
      findsOneWidget,
    );
    expect(find.textContaining('insecure'), findsNothing);
    expect(
      find.text('Mail in this collab is sealed to steerer devices.'),
      findsOneWidget,
    );
  });

  testWidgets('archive asks to confirm then calls archive_collab', (
    tester,
  ) async {
    final calls = <String>[];
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String?;
      calls.add(method ?? '');
      if (method == 'list_contacts' || method == 'list_external_contacts') {
        return _rpcOk(body['id'], {'contacts': []});
      }
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {'agents': []});
      }
      if (method == 'archive_collab') {
        return _rpcOk(body['id'], {'collab': _collabJson(status: 'archived')});
      }
      return _rpcOk(body['id'], {'ok': true});
    });

    await _pumpSheet(tester, daemon: daemon);
    await tester.tap(find.byKey(const Key('manage-archive')));
    await tester.pumpAndSettle();
    expect(find.text('Archive this board?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Archive').last);
    await tester.pumpAndSettle();
    expect(calls, contains('archive_collab'));
  });

  testWidgets('archived board freezes membership except unarchive', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      daemon: _listOnlyDaemon(),
      collab: _collabJson(status: 'archived'),
    );

    expect(find.text('Unarchive'), findsOneWidget);
    expect(
      find.text('Membership is frozen until you unarchive.'),
      findsOneWidget,
    );
    final bobRemove = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('manage-person-bob@acme')),
        matching: find.byType(IconButton),
      ),
    );
    expect(bobRemove.onPressed, isNull);
  });

  testWidgets('wide layout uses people and agents columns', (tester) async {
    await _pumpSheet(
      tester,
      daemon: _listOnlyDaemon(),
      size: const Size(1280, 720),
    );

    expect(find.byKey(const Key('manage-layout-columns')), findsOneWidget);
    expect(find.byKey(const Key('manage-layout-stack')), findsNothing);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
  });

  testWidgets('manage pane has no sheet close chrome', (tester) async {
    await _pumpSheet(tester, daemon: _listOnlyDaemon());

    expect(find.byKey(const Key('collab-manage-pane')), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
