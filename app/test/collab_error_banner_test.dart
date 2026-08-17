
import 'package:app/screens/collab_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/daemon_errors.dart';
import 'fake_daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/pane_quiet_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_collabs') {
        throw DaemonException('GET /v1/collabs');
      }
      return {'ok': true};
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
    final daemon = rpcDaemon((method, params) async {
      if (method == 'list_collabs') {
        lists++;
        if (lists == 1) {
          return {
            'collabs': [
              {
                'id': 'c1',
                'name': 'Launch',
                'encryption_mode': 'e2e',
                'card_count': 1,
              },
            ],
          };
        }
        throw DaemonException('GET /v1/collabs');
      }
      return {'ok': true};
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
