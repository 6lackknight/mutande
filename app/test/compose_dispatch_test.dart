import 'dart:convert';

import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/compose_dispatch.dart';
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

Future<void> _pumpDispatch(
  WidgetTester tester, {
  required DaemonClient daemon,
  String? myHandle,
  String? initialRecipient,
  Future<List<CollabPendingFile>> Function()? pickFiles,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: Scaffold(
        body: ComposeDispatchSheet(
          daemon: daemon,
          myHandle: myHandle ?? 'tawanda@acme',
          initialRecipient: initialRecipient,
          pickFiles: pickFiles,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('composeAddressHint', () {
    expect(composeAddressHint('@all'), 'your agents');
    expect(composeAddressHint('@all@acme'), 'broadcast');
    expect(composeAddressHint('@claude'), 'claude');
    expect(composeAddressHint('alice@acme'), 'teammate');
    expect(composeAddressHint('alice@acme/claude'), 'claude');
  });

  test('orgBroadcastFromHandle / bareHandleFromInput', () {
    expect(orgBroadcastFromHandle('tawanda@acme'), '@all@acme');
    expect(orgBroadcastFromHandle('tawanda@acme/cursor'), '@all@acme');
    expect(bareHandleFromInput('@claude'), isNull);
    expect(bareHandleFromInput('alice@acme/claude'), 'alice@acme');
  });

  testWidgets('pick phase lists self agents', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
            {'id': 'a2', 'slug': 'chatgpt'},
          ],
        });
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(tester, daemon: daemon);

    expect(find.text('Dispatch'), findsOneWidget);
    expect(find.text('Who should get this?'), findsOneWidget);
    expect(find.text('@all'), findsOneWidget);
    expect(find.text('@claude'), findsOneWidget);
    expect(find.text('@chatgpt'), findsOneWidget);
    expect(find.text('@all@acme'), findsOneWidget);
    expect(find.text('Subject'), findsNothing);
  });

  testWidgets('pick then write shows subject, note, attach', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
          ],
        });
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(tester, daemon: daemon);
    await tester.tap(find.text('@claude'));
    await tester.pump();

    expect(find.byKey(const Key('compose-to-chip')), findsOneWidget);
    expect(find.text('@claude'), findsWidgets);
    expect(find.byKey(const Key('compose-subject-field')), findsOneWidget);
    expect(find.byKey(const Key('compose-note-field')), findsOneWidget);
    expect(find.byKey(const Key('compose-attach-file')), findsOneWidget);
    expect(find.byKey(const Key('compose-send')), findsOneWidget);
  });

  testWidgets('adding a second address keeps subject and note', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
            {'id': 'a2', 'slug': 'chatgpt'},
          ],
        });
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(tester, daemon: daemon, initialRecipient: '@claude');
    await tester.enterText(
      find.byKey(const Key('compose-subject-field')),
      'Q3 plan',
    );
    await tester.enterText(
      find.byKey(const Key('compose-note-field')),
      'One risk, please.',
    );
    await tester.tap(find.byKey(const Key('compose-who-field')));
    await tester.pump();
    await tester.tap(find.text('@chatgpt'));
    await tester.pump();

    expect(find.byKey(const Key('compose-to-chip-@claude')), findsOneWidget);
    expect(find.byKey(const Key('compose-to-chip-@chatgpt')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('compose-subject-field')))
          .controller
          ?.text,
      'Q3 plan',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('compose-note-field')))
          .controller
          ?.text,
      'One risk, please.',
    );
  });

  testWidgets('send fans out once per recipient', (tester) async {
    final drafts = <String>[];
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
            {'id': 'a2', 'slug': 'chatgpt'},
          ],
        });
      }
      if (body['method'] == 'forward_draft') {
        final params = Map<String, dynamic>.from(body['params'] as Map);
        drafts.add(params['recipient'] as String);
        return _rpcOk(body['id'], {'thread_id': 't-${drafts.length}'});
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(tester, daemon: daemon, initialRecipient: '@claude');
    await tester.tap(find.byKey(const Key('compose-who-field')));
    await tester.pump();
    await tester.tap(find.text('@chatgpt'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('compose-note-field')),
      'Please both look.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('compose-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(drafts, ['@claude', '@chatgpt']);
  });

  testWidgets('chip tap removes that address only', (tester) async {
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
            {'id': 'a2', 'slug': 'chatgpt'},
          ],
        });
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(tester, daemon: daemon, initialRecipient: '@claude');
    await tester.tap(find.byKey(const Key('compose-who-field')));
    await tester.pump();
    await tester.tap(find.text('@chatgpt'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('compose-note-field')),
      'Keep this.',
    );
    await tester.tap(find.byKey(const Key('compose-to-chip-@chatgpt')));
    await tester.pump();

    expect(find.byKey(const Key('compose-to-chip-@claude')), findsOneWidget);
    expect(find.byKey(const Key('compose-to-chip-@chatgpt')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('compose-note-field')))
          .controller
          ?.text,
      'Keep this.',
    );
  });

  testWidgets('send forwards subject and notes', (tester) async {
    Map<String, dynamic>? forwarded;
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      if (body['method'] == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
          ],
        });
      }
      if (body['method'] == 'forward_draft') {
        forwarded = Map<String, dynamic>.from(body['params'] as Map);
        return _rpcOk(body['id'], {'thread_id': 't1'});
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(tester, daemon: daemon, initialRecipient: '@claude');
    await tester.enterText(
      find.byKey(const Key('compose-subject-field')),
      'Q3 plan',
    );
    await tester.enterText(
      find.byKey(const Key('compose-note-field')),
      'One risk, please.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('compose-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(forwarded, isNotNull);
    expect(forwarded!['recipient'], '@claude');
    expect(forwarded!['subject'], 'Q3 plan');
    expect(forwarded!['notes'], 'One risk, please.');
  });

  testWidgets('attachments go out as forward_blob after the draft', (
    tester,
  ) async {
    final calls = <String>[];
    Map<String, dynamic>? blob;
    final daemon = _mockDaemon((request) async {
      final body = _rpc(request);
      final method = body['method'] as String? ?? '';
      calls.add(method);
      if (method == 'list_agents') {
        return _rpcOk(body['id'], {
          'agents': [
            {'id': 'a1', 'slug': 'claude'},
          ],
        });
      }
      if (method == 'forward_draft') {
        return _rpcOk(body['id'], {'thread_id': 't1'});
      }
      if (method == 'forward_blob') {
        blob = Map<String, dynamic>.from(body['params'] as Map);
        return _rpcOk(body['id'], {'thread_id': 't1'});
      }
      return _rpcOk(body['id'], {});
    });

    await _pumpDispatch(
      tester,
      daemon: daemon,
      initialRecipient: '@claude',
      pickFiles: () async => const [
        CollabPendingFile(name: 'brief.pdf', path: '/tmp/brief.pdf', size: 2048),
      ],
    );
    await tester.enterText(
      find.byKey(const Key('compose-note-field')),
      'See attached.',
    );
    await tester.tap(find.byKey(const Key('compose-attach-file')));
    await tester.pump();
    expect(find.text('brief.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('compose-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls.where((c) => c == 'forward_draft'), isNotEmpty);
    expect(blob, isNotNull);
    expect(blob!['thread_id'], 't1');
    expect(blob!['path'], '/tmp/brief.pdf');
    expect(blob!.containsKey('recipient'), isFalse);
  });
}
