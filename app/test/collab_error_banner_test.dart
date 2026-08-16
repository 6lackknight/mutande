import 'dart:convert';

import 'package:app/screens/collab_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/pane_quiet_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _rpcOk(Object? id, Map<String, dynamic> result) {
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _rpcErr(Object? id, String message) {
  return http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32000, 'message': message},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

DaemonClient _daemon(
  Future<http.Response> Function(Map<String, dynamic> body) onRpc,
) {
  return DaemonClient(
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return onRpc(body);
    }),
    httpToken: 'test-token',
  );
}

bool _isSlopRed(Color? color) {
  if (color == null) return false;
  return color.toARGB32() == 0xFFFEF2F2 ||
      color.toARGB32() == 0xFFFEE2E2 ||
      color.toARGB32() == 0xFFFECACA ||
      color.toARGB32() == 0xFF991B1B;
}

Finder _pinkFill() {
  return find.byWidgetPredicate((w) {
    Color? color;
    if (w is ColoredBox) color = w.color;
    if (w is DecoratedBox) {
      final d = w.decoration;
      if (d is BoxDecoration) color = d.color;
    }
    if (w is Container) {
      final d = w.decoration;
      if (d is BoxDecoration) color = d.color;
    }
    return _isSlopRed(color);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: SizedBox(width: 1280, height: 800, child: child),
        ),
      ),
    ),
  );
}

void main() {
  test('collabFetchErrorCopy never leaks GET /v1/collabs', () {
    expect(
      collabFetchErrorCopy(Exception('GET /v1/collabs')),
      "Couldn't load collab",
    );
    expect(
      collabFetchErrorCopy(
        DaemonException('GET /v1/collabs: error sending request for url'),
      ),
      isNot(contains('/v1/')),
    );
    expect(
      collabFetchErrorCopy(DaemonException('POST /v1/threads')),
      isNot(contains('POST')),
    );
  });

  testWidgets('inline notice is stone capsule with Retry, not a pink bar', (
    WidgetTester tester,
  ) async {
    var retries = 0;
    await _pump(
      tester,
      PaneInlineError(
        message: "Couldn't load collab",
        onRetry: () => retries++,
      ),
    );

    expect(find.text("Couldn't load collab"), findsOneWidget);
    expect(find.text('GET /v1/collabs'), findsNothing);
    expect(find.textContaining('/v1/'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(_pinkFill(), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('empty collab list failure shows human copy, not the hub path', (
    WidgetTester tester,
  ) async {
    final daemon = _daemon((body) async {
      if (body['method'] == 'list_collabs') {
        return _rpcErr(body['id'], 'GET /v1/collabs');
      }
      return _rpcOk(body['id'], {'ok': true});
    });
    await _pump(tester, CollabPanel(daemon: daemon));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load collab"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('GET /v1/collabs'), findsNothing);
    expect(find.textContaining('/v1/'), findsNothing);
    expect(_pinkFill(), findsNothing);
  });

  testWidgets('refresh failure keeps last-known collabs and a quiet notice', (
    WidgetTester tester,
  ) async {
    var lists = 0;
    VoidCallback? reload;
    final daemon = _daemon((body) async {
      if (body['method'] == 'list_collabs') {
        lists++;
        if (lists == 1) {
          return _rpcOk(body['id'], {
            'collabs': [
              {
                'id': 'c1',
                'name': 'Launch',
                'encryption_mode': 'e2e',
                'card_count': 1,
              },
            ],
          });
        }
        return _rpcErr(body['id'], 'GET /v1/collabs');
      }
      return _rpcOk(body['id'], {'ok': true});
    });
    await _pump(
      tester,
      CollabPanel(
        daemon: daemon,
        onReloadReady: (fn) => reload = fn,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Launch'), findsOneWidget);

    reload?.call();
    await tester.pumpAndSettle();

    expect(find.text('Launch'), findsOneWidget);
    expect(find.text("Couldn't load collab"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('GET /v1/collabs'), findsNothing);
    expect(find.textContaining('/v1/'), findsNothing);
    expect(_pinkFill(), findsNothing);
  });
}
