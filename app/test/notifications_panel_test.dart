import 'package:app/services/notification_history_store.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/notifications_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationEntry _entry({
  required String id,
  String threadId = 't1',
  String title = 'mutande',
  String body = 'new mail for @chatgpt from tawanda@tbhco/cursor',
  DateTime? at,
  bool read = false,
  bool needsYou = false,
  String? agentSlug = 'chatgpt',
}) {
  return NotificationEntry(
    id: id,
    threadId: threadId,
    title: title,
    body: body,
    at: at ?? DateTime.utc(2026, 8, 24, 18, 15),
    read: read,
    needsYou: needsYou,
    agentSlug: agentSlug,
  );
}

void main() {
  test('notificationPanelSize is one-third width at 420:560', () {
    final panel = notificationPanelSize(const Size(1280, 720));
    expect(panel.width, closeTo(1280 / 3, 0.01));
    expect(panel.height / panel.width, closeTo(560 / 420, 0.01));
  });

  test('notificationHeadline prefers agent slug over banner copy', () {
    expect(
      notificationHeadline(_entry(id: '1', agentSlug: 'chatgpt')),
      '@chatgpt',
    );
    expect(notificationHeadline(_entry(id: '2', agentSlug: 'all')), '@all');
    expect(
      notificationHeadline(
        _entry(
          id: '3',
          needsYou: true,
          body: 'Needs you — from tawanda@tbhco/cursor',
          agentSlug: null,
        ),
      ),
      'Needs you',
    );
  });

  test('notificationDetail drops new-mail prefix and formats from', () {
    expect(
      notificationDetail(_entry(id: '1'), myHandle: 'tawanda@tbhco'),
      'from @cursor',
    );
    expect(
      notificationDetail(
        _entry(
          id: '2',
          title: 'handoff notes',
          body: 'new mail for @all from roy@berrydeep/chatgpt',
          agentSlug: 'all',
        ),
      ),
      'handoff notes · from roy@berrydeep/chatgpt',
    );
  });

  test('filterNotificationEntries slices unread needs-you and agents', () {
    final entries = [
      _entry(id: 'u', read: false, agentSlug: 'cursor'),
      _entry(id: 'r', read: true, agentSlug: 'chatgpt'),
      _entry(
        id: 'n',
        needsYou: true,
        read: false,
        agentSlug: null,
        body: 'Needs you — from alice@acme/claude',
      ),
    ];
    expect(
      filterNotificationEntries(
        entries,
        NotificationScope.all,
      ).map((e) => e.id),
      ['u', 'r', 'n'],
    );
    expect(
      filterNotificationEntries(
        entries,
        NotificationScope.unread,
      ).map((e) => e.id),
      ['u', 'n'],
    );
    expect(
      filterNotificationEntries(
        entries,
        NotificationScope.needsYou,
      ).map((e) => e.id),
      ['n'],
    );
    expect(
      filterNotificationEntries(
        entries,
        NotificationScope.agents,
      ).map((e) => e.id),
      ['u', 'r'],
    );
  });

  test('groupNotificationEntries splits today from earlier', () {
    final now = DateTime(2026, 8, 24, 12);
    final grouped = groupNotificationEntries([
      _entry(id: 'today', at: DateTime(2026, 8, 24, 9, 1)),
      _entry(id: 'old', at: DateTime(2026, 8, 18, 8)),
    ], now: now);
    expect(grouped.map((s) => s.label), ['Today', 'Earlier']);
    expect(grouped[0].entries.single.id, 'today');
    expect(grouped[1].entries.single.id, 'old');
  });

  testWidgets('panel shows pills and mail rows, not banner cards', (
    tester,
  ) async {
    final history = NotificationHistoryStore.memory([
      _entry(id: '1', agentSlug: 'chatgpt'),
      _entry(
        id: '2',
        agentSlug: 'all',
        body: 'new mail for @all from tawanda@tbhco/cursor',
      ),
      _entry(
        id: '3',
        needsYou: true,
        agentSlug: null,
        body: 'Needs you — from roy@berrydeep/chatgpt',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: Scaffold(
          body: NotificationsPanel(history: history, myHandle: 'tawanda@tbhco'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('notifications-scope-all')), findsOneWidget);
    expect(find.byKey(const Key('notifications-scope-unread')), findsOneWidget);
    expect(
      find.byKey(const Key('notifications-scope-needs-you')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notifications-scope-agents')), findsOneWidget);

    expect(
      find.text('new mail for @chatgpt from tawanda@tbhco/cursor'),
      findsNothing,
    );
    expect(find.text('@chatgpt'), findsOneWidget);
    expect(find.text('@all'), findsOneWidget);
    expect(find.text('Needs you'), findsWidgets);
    expect(find.text('from @cursor'), findsWidgets);

    await tester.tap(find.byKey(const Key('notifications-scope-needs-you')));
    await tester.pump();
    expect(find.text('@chatgpt'), findsNothing);
    expect(find.text('Needs you'), findsWidgets);
  });
}
