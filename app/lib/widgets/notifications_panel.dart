import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/notification_history_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../util/clock_format.dart';
import 'ai_host_icon.dart';
import 'home_chrome_pills.dart';
import 'home_chrome_strip.dart';
import 'mutande_sheet.dart';
import 'pane_quiet_state.dart';
import 'thinking_orb.dart';

enum NotificationScope { all, unread, needsYou, agents }

class NotificationSection {
  const NotificationSection({required this.label, required this.entries});

  final String label;
  final List<NotificationEntry> entries;
}

List<NotificationEntry> filterNotificationEntries(
  Iterable<NotificationEntry> entries,
  NotificationScope scope,
) {
  return [
    for (final e in entries)
      if (switch (scope) {
        NotificationScope.all => true,
        NotificationScope.unread => !e.read,
        NotificationScope.needsYou => e.needsYou,
        NotificationScope.agents => !e.needsYou,
      })
        e,
  ];
}

List<NotificationSection> groupNotificationEntries(
  List<NotificationEntry> entries, {
  DateTime? now,
}) {
  if (entries.isEmpty) return const [];
  final today = <NotificationEntry>[];
  final earlier = <NotificationEntry>[];
  final pivot = (now ?? DateTime.now()).toLocal();
  for (final e in entries) {
    final local = e.at.toLocal();
    if (local.year == pivot.year &&
        local.month == pivot.month &&
        local.day == pivot.day) {
      today.add(e);
    } else {
      earlier.add(e);
    }
  }
  return [
    if (today.isNotEmpty) NotificationSection(label: 'Today', entries: today),
    if (earlier.isNotEmpty)
      NotificationSection(label: 'Earlier', entries: earlier),
  ];
}

String? notificationFromAddress(String body) {
  final i = body.toLowerCase().lastIndexOf(' from ');
  if (i < 0) return null;
  final from = body.substring(i + 6).trim();
  return from.isEmpty ? null : from;
}

String notificationHeadline(NotificationEntry entry) {
  if (entry.needsYou) return 'Needs you';
  final slug = entry.agentSlug?.trim().toLowerCase();
  if (slug != null && slug.isNotEmpty) return '@$slug';
  final match = RegExp(
    r'new mail for (@[^\s]+)',
    caseSensitive: false,
  ).firstMatch(entry.body);
  if (match != null) return match.group(1)!.toLowerCase();
  return 'Mail';
}

String notificationDetail(NotificationEntry entry, {String? myHandle}) {
  final from = notificationFromAddress(entry.body);
  final fromLabel = from == null
      ? null
      : 'from ${formatMailAddress(from, myHandle: myHandle)}';
  final subject = entry.title.trim();
  final hasSubject = subject.isNotEmpty && subject.toLowerCase() != 'mutande';
  if (hasSubject && fromLabel != null) return '$subject · $fromLabel';
  if (hasSubject) return subject;
  return fromLabel ?? '';
}

Future<String?> showNotificationsPanel({
  required BuildContext context,
  required NotificationHistoryStore history,
  Rect? origin,
  String? myHandle,
}) async {
  try {
    return await showMutandeSheet<String>(
      context: context,
      barrierLabel: 'Notifications',
      origin: origin,
      width: 420,
      height: 560,
      child: NotificationsPanel(history: history, myHandle: myHandle),
    );
  } finally {
    await history.markAllRead();
  }
}

class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({super.key, required this.history, this.myHandle});

  final NotificationHistoryStore history;
  final String? myHandle;

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  bool _loading = true;
  NotificationScope _scope = NotificationScope.all;

  @override
  void initState() {
    super.initState();
    widget.history.addListener(_onHistoryChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.history.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await widget.history.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _close([String? threadId]) {
    Navigator.of(context, rootNavigator: true).pop(threadId);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openEntry(NotificationEntry entry) async {
    await widget.history.markRead(entry.id);
    _close(entry.threadId);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.history.entries;
    final unreadCount = entries.where((e) => !e.read).length;
    final needsYouCount = entries.where((e) => e.needsYou).length;
    final visible = filterNotificationEntries(entries, _scope);
    final sections = groupNotificationEntries(visible);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: MutandeColors.stone50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _CloseButton(onPressed: () => _close()),
                  const SizedBox(width: 12),
                  Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: MutandeColors.stone800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'esc',
                    style: TextStyle(
                      color: MutandeColors.stone400,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    MutandeScopePill(
                      key: const Key('notifications-scope-all'),
                      label: 'All',
                      selected: _scope == NotificationScope.all,
                      onTap: () =>
                          setState(() => _scope = NotificationScope.all),
                    ),
                    const SizedBox(width: 4),
                    MutandeScopePill(
                      key: const Key('notifications-scope-unread'),
                      label: 'Unread',
                      selected: _scope == NotificationScope.unread,
                      badge: unreadCount,
                      onTap: () =>
                          setState(() => _scope = NotificationScope.unread),
                    ),
                    const SizedBox(width: 4),
                    MutandeScopePill(
                      key: const Key('notifications-scope-needs-you'),
                      label: 'Needs you',
                      selected: _scope == NotificationScope.needsYou,
                      badge: needsYouCount,
                      onTap: () =>
                          setState(() => _scope = NotificationScope.needsYou),
                    ),
                    const SizedBox(width: 4),
                    MutandeScopePill(
                      key: const Key('notifications-scope-agents'),
                      label: 'Agents',
                      selected: _scope == NotificationScope.agents,
                      onTap: () =>
                          setState(() => _scope = NotificationScope.agents),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: MutandeOrb.standard(
                        semanticLabel: 'Loading notifications…',
                      ),
                    )
                  : entries.isEmpty
                  ? const PaneQuietState(
                      title: 'No notifications yet',
                      body:
                          'When mail needs you or reaches an agent, it shows up here.',
                    )
                  : visible.isEmpty
                  ? PaneQuietState(
                      title: switch (_scope) {
                        NotificationScope.unread => 'Caught up',
                        NotificationScope.needsYou => 'Nothing needs you',
                        NotificationScope.agents => 'No agent mail',
                        NotificationScope.all => 'No notifications yet',
                      },
                      body: switch (_scope) {
                        NotificationScope.unread =>
                          'New mail for you or an agent will land here.',
                        NotificationScope.needsYou =>
                          'Threads waiting on you show up in this list.',
                        NotificationScope.agents =>
                          'Mail for your agents shows up in this list.',
                        NotificationScope.all =>
                          'When mail needs you or reaches an agent, it shows up here.',
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      itemCount: sections.fold<int>(
                        0,
                        (n, s) => n + 1 + s.entries.length,
                      ),
                      itemBuilder: (context, index) {
                        var cursor = 0;
                        for (final section in sections) {
                          if (index == cursor) {
                            return _SectionHeader(
                              label: section.label,
                              padTop: cursor > 0,
                            );
                          }
                          cursor += 1;
                          final last = cursor + section.entries.length;
                          if (index < last) {
                            final entry = section.entries[index - cursor];
                            return _NotificationRow(
                              entry: entry,
                              myHandle: widget.myHandle,
                              onTap: () => _openEntry(entry),
                            );
                          }
                          cursor = last;
                        }
                        return const SizedBox.shrink();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.padTop});

  final String label;
  final bool padTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, padTop ? 14 : 6, 10, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: MutandeColors.stone500,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close notifications',
      child: Tooltip(
        message: 'Close',
        child: Material(
          color: MutandeColors.stone50,
          shape: const CircleBorder(
            side: BorderSide(color: MutandeColors.stone200),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox(
              width: HomeChrome.thumbHeight,
              height: HomeChrome.thumbHeight,
              child: Icon(
                CupertinoIcons.xmark,
                size: 13,
                color: MutandeColors.stone600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.entry,
    required this.onTap,
    this.myHandle,
  });

  final NotificationEntry entry;
  final VoidCallback onTap;
  final String? myHandle;

  static const _markSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final unread = !entry.read;
    final needsYou = entry.needsYou;
    final headline = notificationHeadline(entry);
    final detail = notificationDetail(entry, myHandle: myHandle);
    final time = formatRelativeTime(entry.at.toUtc().toIso8601String());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        hoverColor: MutandeColors.stone100,
        highlightColor: MutandeColors.stone100,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          child: Row(
            children: [
              SizedBox(
                width: 8,
                child: unread
                    ? Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: needsYou
                                ? MutandeColors.amber
                                : MutandeColors.bronze,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              _HostMark(entry: entry, needsYou: needsYou),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: needsYou
                            ? MutandeColors.amber
                            : MutandeColors.stone800,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: unread
                              ? MutandeColors.stone600
                              : MutandeColors.stone400,
                          fontWeight: unread
                              ? FontWeight.w500
                              : FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  time,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: unread && needsYou
                        ? MutandeColors.amber
                        : MutandeColors.stone400,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HostMark extends StatelessWidget {
  const _HostMark({required this.entry, required this.needsYou});

  final NotificationEntry entry;
  final bool needsYou;

  static const _size = _NotificationRow._markSize;

  @override
  Widget build(BuildContext context) {
    final slug = entry.agentSlug?.trim().toLowerCase();
    final plate = needsYou
        ? MutandeColors.amberSoft.withValues(alpha: 0.8)
        : MutandeColors.stone100;
    final border = needsYou
        ? MutandeColors.amber.withValues(alpha: 0.35)
        : MutandeColors.stone200;

    Widget mark;
    if (slug != null && AiHostIcon.assetFor(slug) != null) {
      mark = AiHostIcon(slug, size: _size, showPlate: false);
    } else if (slug == 'all') {
      mark = const Text(
        '@',
        style: TextStyle(
          color: MutandeColors.stone500,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          height: 1,
        ),
      );
    } else {
      mark = Icon(
        needsYou ? CupertinoIcons.person : CupertinoIcons.envelope,
        size: 14,
        color: MutandeColors.stone500,
      );
    }

    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: plate,
        shape: BoxShape.circle,
        border: Border.all(color: border),
      ),
      child: mark,
    );
  }
}
