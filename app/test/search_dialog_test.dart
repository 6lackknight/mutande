import 'dart:async';
import 'dart:convert';

import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/search_dialog.dart';
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

ThreadSummary _thread({
  required String id,
  required String from,
  String subject = '',
  String audience = 'alice@acme',
}) {
  return ThreadSummary(
    id: id,
    kind: 'direct',
    status: 'open',
    from: from,
    audience: audience,
    lastSubject: subject,
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required DaemonClient daemon,
  List<String> recent = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: Scaffold(
        body: SearchDialog(
          daemon: daemon,
          myHandle: 'alice@acme',
          recentQueries: recent,
        ),
      ),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Searching…').evaluate().isEmpty) return;
  }
}

void main() {
  test('filterSearchHits matches threads collabs and contacts', () {
    final hits = filterSearchHits(
      query: 'board',
      scope: SearchScope.all,
      threads: [
        _thread(id: 't1', from: 'bob@acme', subject: 'Board kickoff'),
        _thread(id: 't2', from: 'cara@acme', subject: 'Unrelated'),
      ],
      collabs: const [
        CollabSummary(id: 'c1', name: 'Launch board', encryptionMode: 'e2e'),
      ],
      contacts: const [
        ContactView(handle: 'dana@acme', displayName: 'Dana'),
      ],
    );
    expect(hits.map((h) => h.id), ['t1', 'c1']);
  });

  test('filterSearchHits scope chips isolate kind', () {
    final threads = [_thread(id: 't1', from: 'bob@acme', subject: 'Hello')];
    final collabs = const [
      CollabSummary(id: 'c1', name: 'Hello collab', encryptionMode: 'e2e'),
    ];
    final contacts = const [
      ContactView(handle: 'hello@acme', displayName: 'Hello'),
    ];
    expect(
      filterSearchHits(
        query: 'hello',
        scope: SearchScope.threads,
        threads: threads,
        collabs: collabs,
        contacts: contacts,
      ).single.kind,
      SearchHitKind.thread,
    );
    expect(
      filterSearchHits(
        query: 'hello',
        scope: SearchScope.collab,
        threads: threads,
        collabs: collabs,
        contacts: contacts,
      ).single.kind,
      SearchHitKind.collab,
    );
    expect(
      filterSearchHits(
        query: 'hello',
        scope: SearchScope.contacts,
        threads: threads,
        collabs: collabs,
        contacts: contacts,
      ).single.kind,
      SearchHitKind.contact,
    );
  });

  testWidgets('typing filters results as the query changes', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (body['method'] as String?) {
        case 'list_threads':
          return _rpcOk(body['id'], {
            'threads': [
              {
                'id': 't1',
                'kind': 'direct',
                'status': 'open',
                'from': 'bob@acme',
                'audience': 'alice@acme',
                'last_subject': 'Ship the alpha',
              },
              {
                'id': 't2',
                'kind': 'direct',
                'status': 'open',
                'from': 'cara@acme',
                'audience': 'alice@acme',
                'last_subject': 'Lunch',
              },
            ],
          });
        case 'list_collabs':
          return _rpcOk(body['id'], {
            'collabs': [
              {'id': 'c1', 'name': 'Alpha board', 'encryption_mode': 'e2e'},
            ],
          });
        case 'list_contacts':
          return _rpcOk(body['id'], {
            'contacts': [
              {'handle': 'dana@acme', 'display_name': 'Dana'},
            ],
          });
        case 'list_external_contacts':
          return _rpcOk(body['id'], {'contacts': []});
        default:
          return _rpcOk(body['id'], {});
      }
    });

    await _pumpDialog(tester, daemon: daemon);

    expect(find.text('Type to search collabs, threads, and contacts'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump();

    expect(find.text('Ship the alpha'), findsOneWidget);
    expect(find.text('Alpha board'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
    expect(find.text('Dana'), findsNothing);

    await tester.tap(find.byKey(const Key('search-scope-contacts')));
    await tester.pump();
    expect(find.text('No contacts match “alpha”'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-scope-collab')));
    await tester.pump();
    expect(find.text('Alpha board'), findsOneWidget);
    expect(find.text('Ship the alpha'), findsNothing);
  });

  testWidgets('empty collab chip lists all collabs', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (body['method'] as String?) {
        case 'list_threads':
          return _rpcOk(body['id'], {'threads': []});
        case 'list_collabs':
          return _rpcOk(body['id'], {
            'collabs': [
              {'id': 'c1', 'name': 'Launch', 'encryption_mode': 'e2e'},
            ],
          });
        case 'list_contacts':
        case 'list_external_contacts':
          return _rpcOk(body['id'], {'contacts': []});
        default:
          return _rpcOk(body['id'], {});
      }
    });

    await _pumpDialog(tester, daemon: daemon);
    await tester.tap(find.byKey(const Key('search-scope-collab')));
    await tester.pump();
    expect(find.text('Launch'), findsOneWidget);
  });
}
