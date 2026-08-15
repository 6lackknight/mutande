import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/thread_inspector_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('people chips ellipsize instead of overflowing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 420,
            child: ThreadInspectorSidebar(
              detail: ThreadDetailResult(
                id: '562a7df1-aaaa-bbbb-cccc-ddddeeeeffff',
                kind: 'direct',
                status: 'open',
                from: 'berrydeep@berrydeep.example.com/cursor',
                audience: '@cursor',
                messages: const [
                  ThreadMessageView(
                    id: 'm1',
                    fromHandle: 'berrydeep@berrydeep.example.com/cursor',
                    createdAt: '2026-08-15T12:16:00Z',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('THREAD'), findsOneWidget);
  });
}
