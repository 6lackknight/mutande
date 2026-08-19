import 'package:app/models/handshake_card.dart';
import 'package:app/widgets/handshake_intro_card.dart';
import 'package:app/widgets/handshake_thread_pane.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the mailed handshake dump', () {
    const notes = '''
Handshake
Host: Cursor
Address: tawanda@tbhco/cursor
Models: Cursor Grok 4.6
Skills: mutande, handshake
Ask me about: mutande mail, Mac onboarding, agent handoffs
Preferred files: markdown
Other tools: github
''';
    final card = HandshakeCardView.tryParseNotes(notes)!;
    expect(card.host, 'Cursor');
    expect(
      card.leadSentence,
      'Ask me about mutande mail, Mac onboarding, and agent handoffs.',
    );
    expect(
      card.extrasLine,
      'mutande · handshake · Cursor Grok 4.6 · github · markdown',
    );
  });

  test('leaves prose notes alone', () {
    expect(
      HandshakeCardView.tryParseNotes('I’m Claude. Ask me about shipping.'),
      isNull,
    );
  });

  testWidgets('handshake pane leads with the message, extras underneath', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const notes = '''
Handshake
Host: Cursor
Address: tawanda@tbhco/cursor
Models: Cursor Grok 4.6
Skills: mutande, handshake
Ask me about: mutande mail, Mac onboarding
Preferred files: markdown
Other tools: github
''';
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: const Scaffold(
          body: HandshakeThreadPane(
            myHandle: 'tawanda@tbhco',
            detail: ThreadDetailResult(
              id: 't',
              kind: 'direct',
              status: 'open',
              from: 'tawanda@tbhco/cursor',
              audience: 'tawanda@tbhco/claude',
              messages: [
                ThreadMessageView(
                  id: 'm1',
                  fromHandle: 'tawanda@tbhco/cursor',
                  createdAt: '2026-08-19T10:00:00Z',
                  bundleSubject: 'Handshake',
                  bundleNotes: notes,
                  hasHandshake: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Ask me about mutande mail and Mac onboarding.'),
      findsOneWidget,
    );
    expect(find.byType(HandshakeExtrasLine), findsOneWidget);
    expect(find.text('Host: Cursor'), findsNothing);
    expect(find.text('Skills'), findsNothing);
    expect(find.text('Ask me about'), findsNothing);
  });
}
