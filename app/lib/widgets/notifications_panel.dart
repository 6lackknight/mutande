import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/notification_history_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/clock_format.dart';
import 'ai_host_icon.dart';
import 'mutande_sheet.dart';
import 'pane_quiet_state.dart';
import 'thinking_orb.dart';

Future<String?> showNotificationsPanel({
  required BuildContext context,
  required NotificationHistoryStore history,
  Rect? origin,
}) {
  return showMutandeSheet<String>(
    context: context,
    barrierLabel: 'Notifications',
    origin: origin,
    width: 420,
    height: 520,
    child: NotificationsPanel(history: history),
  );
}

class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({super.key, required this.history});

  final NotificationHistoryStore history;

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  bool _loading = true;

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
    await widget.history.markAllRead();
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

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: MutandeColors.stone50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
              child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => _close(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: MutandeColors.stone800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (entries.any((e) => !e.read))
                      TextButton(
                        onPressed: () => widget.history.markAllRead(),
                        child: const Text('Mark all read'),
                      ),
                  ],
                ),
              ),
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
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _NotificationRow(
                            entry: entry,
                            onTap: () => _openEntry(entry),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.entry, required this.onTap});

  final NotificationEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final slug = entry.agentSlug;
    final hostIcon = slug != null && AiHostIcon.assetFor(slug) != null
        ? AiHostIcon(slug, size: 14, showPlate: false)
        : null;
    final time = formatRelativeTime(entry.at.toUtc().toIso8601String());

    return Material(
      color: entry.read ? Colors.white : MutandeColors.stone100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: entry.read ? MutandeColors.stone200 : MutandeColors.stone400,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!entry.read)
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: MutandeColors.bronze,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (hostIcon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 8),
                  child: hostIcon,
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.body,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: entry.read
                            ? FontWeight.w500
                            : FontWeight.w600,
                        color: MutandeColors.stone800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: MutandeColors.stone500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
