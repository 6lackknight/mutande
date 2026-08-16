import 'package:app/services/daemon_client.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/mutande_stagger.dart';
import 'package:app/widgets/thread_relay_reading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadMessageView _msg(
  String id,
  String from,
  String notes, {
  String? parent,
}) {
  return ThreadMessageView(
    id: id,
    fromHandle: from,
    createdAt: '2026-01-01T00:00:00Z',
    bundleNotes: notes,
    parentMessageId: parent,
  );
}

ThreadDetailResult _detail(
  List<ThreadMessageView> messages, {
  String id = 't1',
}) {
  return ThreadDetailResult(
    id: id,
    kind: 'direct',
    status: 'open',
    from: 'alice@acme',
    messages: messages,
  );
}

ThreadRelayReading _reading(
  ThreadDetailResult detail,
  TextEditingController reply, {
  String? replyToHandle,
  VoidCallback? onClearTarget,
}) {
  return ThreadRelayReading(
    detail: detail,
    myHandle: 'alice@acme',
    muted: false,
    reply: reply,
    sending: false,
    replyToHandle: replyToHandle,
    nested: replyToHandle != null,
    onSend: () {},
    onClearTarget: onClearTarget ?? () {},
    onReply: (_) {},
    onUpvote: (_) {},
    upvotingId: null,
    onRefresh: () {},
    onClose: () {},
    onDelete: () {},
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduce = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          body: SizedBox(width: 480, height: 640, child: child),
        ),
      ),
    ),
  );
}

Finder _opacityAround(Finder of) {
  return find.ancestor(of: of, matching: find.byType(Opacity));
}

void main() {
  late TextEditingController reply;

  setUp(() => reply = TextEditingController());
  tearDown(() => reply.dispose());

  testWidgets('rail messages fade in on open; later append stays at rest', (
    WidgetTester tester,
  ) async {
    var messages = <ThreadMessageView>[
      _msg('m1', 'alice@acme', 'op-notes'),
      _msg('m2', 'alice@acme/cursor', 'reply-notes', parent: 'm1'),
    ];
    late void Function(ThreadMessageView) add;

    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          add = (m) => setState(() => messages = [...messages, m]);
          return _reading(_detail(messages), reply);
        },
      ),
    );

    expect(find.byType(MutandeStaggerScope), findsOneWidget);
    expect(find.byType(MutandeStaggerIn), findsNWidgets(2));

    final firstOpacity = tester.widget<Opacity>(
      _opacityAround(find.textContaining('op-notes')).first,
    );
    expect(firstOpacity.opacity, lessThan(0.2));

    await tester.pump(MutandeMotion.ui);
    final settled = tester.widget<Opacity>(
      _opacityAround(find.textContaining('op-notes')).first,
    );
    expect(settled.opacity, closeTo(1, 0.02));

    await tester.pump(); // freeze
    add(_msg('m3', 'alice@acme/claude', 'late-notes', parent: 'm1'));
    await tester.pump();

    expect(find.textContaining('late-notes'), findsOneWidget);
    expect(
      _opacityAround(find.textContaining('late-notes')),
      findsNothing,
    );
  });

  testWidgets('reduced motion shows messages at rest', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _reading(
        _detail([
          _msg('m1', 'alice@acme', 'op-notes'),
          _msg('m2', 'alice@acme/cursor', 'reply-notes', parent: 'm1'),
        ]),
        reply,
      ),
      reduce: true,
    );

    expect(find.textContaining('op-notes'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Transform && w.transform.getTranslation().y != 0,
      ),
      findsNothing,
    );
  });

  testWidgets('switching threads remounts stagger', (
    WidgetTester tester,
  ) async {
    var detail = _detail([
      _msg('a1', 'alice@acme', 'thread-a-notes'),
    ], id: 'ta');
    late void Function(ThreadDetailResult) replace;

    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          replace = (next) => setState(() => detail = next);
          return _reading(detail, reply);
        },
      ),
    );

    await tester.pump(MutandeMotion.ui);
    await tester.pump();

    replace(
      _detail([_msg('b1', 'alice@acme', 'thread-b-notes')], id: 'tb'),
    );
    await tester.pump();

    final opacity = tester.widget<Opacity>(
      _opacityAround(find.textContaining('thread-b-notes')).first,
    );
    expect(opacity.opacity, lessThan(0.2));
  });

  testWidgets('idle composer is a single capsule', (WidgetTester tester) async {
    await _pump(
      tester,
      _reading(_detail([_msg('m1', 'alice@acme', 'op-notes')]), reply),
      reduce: true,
    );

    expect(find.text('Write a reply…'), findsOneWidget);
    expect(find.textContaining('Replying to'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(const Key('relay-composer-send')), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.filled, isFalse);
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.enabledBorder, InputBorder.none);
    expect(field.decoration?.focusedBorder, InputBorder.none);
  });

  testWidgets('threaded reply sits inside the capsule', (
    WidgetTester tester,
  ) async {
    var cleared = false;
    await _pump(
      tester,
      _reading(
        _detail([_msg('m1', 'alice@acme', 'op-notes')]),
        reply,
        replyToHandle: '@chatgpt',
        onClearTarget: () => cleared = true,
      ),
      reduce: true,
    );

    expect(find.text('Replying to @chatgpt'), findsOneWidget);
    expect(find.text('Reply to @chatgpt…'), findsOneWidget);
    expect(find.text('Write a reply…'), findsNothing);

    final capsule = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(AnimatedContainer),
    );
    expect(
      find.descendant(
        of: capsule,
        matching: find.text('Replying to @chatgpt'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: capsule, matching: find.text('Cancel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('relay-composer-cancel')));
    expect(cleared, isTrue);
  });
}
