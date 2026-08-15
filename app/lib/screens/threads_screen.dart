import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_resizable_container/flutter_resizable_container.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../services/daemon_event_client.dart';
import '../services/notification_prefs_store.dart';
import '../services/thread_list_cache_store.dart';
import '../services/transport_prefs_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../util/clock_format.dart';
import '../util/compose_transport.dart';
import '../util/thread_peer.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thread_status_badge.dart';
import '../widgets/downgrade_consent_banner.dart';
import '../widgets/enterprise_warn_banner.dart';
import '../widgets/transport_chip.dart';
import '../widgets/thread_relay_reading.dart';
import '../widgets/thread_inspector_sidebar.dart';

/// Inbox poll when WebSocket is down — push is primary (see PRD-INBOX-EVENTS).
const Duration _threadsFallbackPollInterval = Duration(seconds: 30);

Future<bool?> confirmThreadAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x660C0A09),
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFFFAFAF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Stitch home threads — filters, list rows, compose.
class ThreadsPanel extends StatefulWidget {
  ThreadsPanel({
    super.key,
    required this.daemon,
    this.inboxEvents,
    this.onReloadReady,
    this.myHandle,
    this.composeRecipient,
    this.onComposeRecipientHandled,
    this.initialThreadId,
    this.onInitialThreadHandled,
    NotificationPrefsStore? notificationPrefs,
  }) : notificationPrefs = notificationPrefs ?? NotificationPrefsStore();

  final DaemonClient daemon;

  /// Session-level WebSocket inbox push (null in tests / when unavailable).
  final DaemonEventClient? inboxEvents;

  final ValueChanged<VoidCallback?>? onReloadReady;

  /// Current user handle (`alice@acme`) for self-shorthand display.
  final String? myHandle;

  /// When set, opens compose addressed to this handle.
  final String? composeRecipient;
  final VoidCallback? onComposeRecipientHandled;

  /// When set, opens this thread (e.g. after first-run ping).
  final String? initialThreadId;
  final VoidCallback? onInitialThreadHandled;

  final NotificationPrefsStore notificationPrefs;

  @override
  State<ThreadsPanel> createState() => _ThreadsPanelState();
}

class _ThreadsPanelState extends State<ThreadsPanel> {
  String _filter = 'all';
  bool _loading = true;
  bool _silentRefreshInFlight = false;
  String? _error;
  List<ThreadSummary> _threads = const [];
  Map<String, String> _avatarsByHandle = const {};
  String? _openId;
  bool _composeOpen = false;
  String? _composePrefillRecipient;
  int? _hotDivider;
  Timer? _pollTimer;
  StreamSubscription? _inboxSub;
  final GlobalKey<_ThreadDetailPanelState> _detailKey =
      GlobalKey<_ThreadDetailPanelState>();
  final ScrollController _listScroll = ScrollController();
  Set<String> _mutedIds = {};
  final ThreadListCacheStore _threadCache = ThreadListCacheStore();

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  String get _filterKey => _filter == 'all' ? 'all' : _filter;

  ResizableDivider _splitDivider(int id) {
    final hot = _hotDivider == id;
    return ResizableDivider(
      thickness: hot ? 2 : 1,
      padding: 3,
      color: hot ? MutandeColors.bronze : MutandeColors.stone200,
      cursor: SystemMouseCursors.resizeColumn,
      onHoverEnter: () => setState(() => _hotDivider = id),
      onHoverExit: () {
        if (_hotDivider == id) setState(() => _hotDivider = null);
      },
      onDragStart: () => setState(() => _hotDivider = id),
      onDragEnd: () => setState(() => _hotDivider = null),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.onReloadReady?.call(_reload);
    final initial = widget.initialThreadId?.trim();
    if (initial != null && initial.isNotEmpty) {
      _openId = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialThreadHandled?.call();
      });
    }
    _loadMuted();
    unawaited(_hydrateFromCacheThenReload());
    final events = widget.inboxEvents;
    if (events != null && !_inWidgetTest) {
      _inboxSub = events.events.listen((_) {
        unawaited(_reload(silent: true));
      });
      events.connected.addListener(_onInboxConnectionChanged);
      _syncPollingMode();
    }
  }

  void _onInboxConnectionChanged() => _syncPollingMode();

  Future<void> _hydrateFromCacheThenReload() async {
    if (!_inWidgetTest) {
      final cached = await _threadCache.load(_filterKey);
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _threads = cached;
          _loading = false;
          _error = null;
        });
        unawaited(_reload(silent: true));
        return;
      }
    }
    await _reload();
  }

  Future<void> _loadMuted() async {
    final prefs = await widget.notificationPrefs.load();
    if (!mounted) return;
    setState(() => _mutedIds = Set<String>.from(prefs.mutedThreadIds));
  }

  Future<void> _toggleMute(String threadId) async {
    final next = !_mutedIds.contains(threadId);
    await widget.notificationPrefs.setMuted(threadId, next);
    if (!mounted) return;
    setState(() {
      if (next) {
        _mutedIds = {..._mutedIds, threadId};
      } else {
        _mutedIds = {..._mutedIds}..remove(threadId);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? 'Thread muted' : 'Thread unmuted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ThreadsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onReloadReady != widget.onReloadReady) {
      widget.onReloadReady?.call(_reload);
    }
    final next = widget.composeRecipient?.trim();
    final prev = oldWidget.composeRecipient?.trim();
    if (next != null && next.isNotEmpty && next != prev) {
      setState(() {
        _composeOpen = true;
        _composePrefillRecipient = next;
      });
      widget.onComposeRecipientHandled?.call();
    }
    final openNext = widget.initialThreadId?.trim();
    final openPrev = oldWidget.initialThreadId?.trim();
    if (openNext != null && openNext.isNotEmpty && openNext != openPrev) {
      setState(() {
        _openId = openNext;
      });
      widget.onInitialThreadHandled?.call();
    }
  }

  @override
  void dispose() {
    widget.inboxEvents?.connected.removeListener(_onInboxConnectionChanged);
    unawaited(_inboxSub?.cancel());
    _pollTimer?.cancel();
    _listScroll.dispose();
    widget.onReloadReady?.call(null);
    super.dispose();
  }

  void _syncPollingMode() {
    if (_inWidgetTest) return;
    final live = widget.inboxEvents?.connected.value == true;
    if (live) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _ensureFallbackPolling();
  }

  void _ensureFallbackPolling() {
    if (_inWidgetTest) return;
    _pollTimer ??= Timer.periodic(_threadsFallbackPollInterval, (_) {
      unawaited(_reload(silent: true));
    });
  }

  Future<Map<String, String>> _loadAvatarMap() async {
    try {
      final org = await widget.daemon.listContacts();
      var external = <ContactView>[];
      try {
        external = await widget.daemon.listExternalContacts();
      } catch (_) {}
      return avatarUrlsByHandle([
        for (final c in org) (handle: c.handle, avatarUrl: c.avatarUrl),
        for (final c in external) (handle: c.handle, avatarUrl: c.avatarUrl),
      ]);
    } catch (_) {
      return const {};
    }
  }

  /// Full reload shows the orb; [silent] merges without tearing down the list.
  Future<void> _reload({bool silent = false}) async {
    if (!mounted) return;
    if (silent) {
      if (_loading || _silentRefreshInFlight) return;
      _silentRefreshInFlight = true;
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final threadsFuture = widget.daemon.listThreads(
        filter:
            (_filter == 'all' || _filter == 'collab' || _filter == 'unfiled')
            ? null
            : _filter,
      );
      final avatarsFuture = _loadAvatarMap();
      final threads = await threadsFuture;
      final avatars = await avatarsFuture;
      if (!mounted) return;
      _avatarsByHandle = avatars;
      _applyThreadList(threads, clearError: true);
      if (!_inWidgetTest) {
        unawaited(_threadCache.save(_filterKey, threads));
      }
      _syncPollingMode();
    } catch (e) {
      if (!mounted) return;
      if (silent && _threads.isNotEmpty) {
        // Keep last-known list on poll blips.
        return;
      }
      setState(() {
        _error = friendlyDaemonError(e, what: 'Threads');
        _loading = false;
      });
    } finally {
      if (silent) _silentRefreshInFlight = false;
    }
  }

  void _applyThreadList(List<ThreadSummary> next, {bool clearError = false}) {
    final openId = _openId;
    ThreadSummary? prevOpen;
    if (openId != null) {
      for (final t in _threads) {
        if (t.id == openId) {
          prevOpen = t;
          break;
        }
      }
    }

    final unchanged = _sameThreadList(_threads, next);
    final openStillPresent = openId == null || next.any((t) => t.id == openId);

    if (!unchanged || _loading || (clearError && _error != null)) {
      setState(() {
        if (!unchanged) _threads = next;
        _loading = false;
        if (clearError) _error = null;
        if (openId != null && !openStillPresent) _openId = null;
      });
    }

    if (openId != null && openStillPresent) {
      ThreadSummary? nextOpen;
      for (final t in next) {
        if (t.id == openId) {
          nextOpen = t;
          break;
        }
      }
      if (nextOpen != null &&
          (prevOpen == null || !prevOpen.sameListRow(nextOpen))) {
        _detailKey.currentState?.softRefresh();
      }
    }
  }

  static bool _sameThreadList(List<ThreadSummary> a, List<ThreadSummary> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].sameListRow(b[i])) return false;
    }
    return true;
  }

  void _removeThreadLocally(String threadId) {
    setState(() {
      _threads = [
        for (final t in _threads)
          if (t.id != threadId) t,
      ];
      if (_openId == threadId) _openId = null;
    });
  }

  void _applyClosedLocally(String threadId) {
    final dropFromFilter = _filter == 'open' || _filter == 'needs_action';
    setState(() {
      if (dropFromFilter) {
        _threads = [
          for (final t in _threads)
            if (t.id != threadId) t,
        ];
        if (_openId == threadId) _openId = null;
      } else {
        _threads = [
          for (final t in _threads)
            if (t.id == threadId) t.copyWith(status: 'closed') else t,
        ];
      }
    });
  }

  List<ThreadSummary> get _visible {
    if (_filter == 'collab') {
      return [
        for (final t in _threads)
          if (t.collabId != null && t.collabId!.isNotEmpty) t,
      ];
    }
    if (_filter == 'unfiled') {
      return [
        for (final t in _threads)
          if (t.collabId == null || t.collabId!.isEmpty) t,
      ];
    }
    return _threads;
  }

  String? _avatarForThread(ThreadSummary t) {
    final peer = threadPeerHandle(
      t.from,
      t.audience,
      myHandle: widget.myHandle,
    );
    if (peer == null) return null;
    return _avatarsByHandle[peer];
  }

  Future<void> _closeThreadFromList(String threadId) async {
    final ok = await confirmThreadAction(
      context,
      title: 'Close thread?',
      body: 'This marks the thread closed. You can still find it under Closed.',
      confirmLabel: 'Close',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.daemon.closeThread(threadId);
      if (!mounted) return;
      _applyClosedLocally(threadId);
      if (_openId == threadId) {
        _detailKey.currentState?.softRefresh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Close thread'))),
      );
    }
  }

  Future<void> _deleteThreadFromList(String threadId) async {
    final ok = await confirmThreadAction(
      context,
      title: 'Delete thread?',
      body:
          'This removes the thread from your inbox. If you started it, the messages are purged.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await widget.daemon.deleteThread(threadId);
      if (!mounted) return;
      _removeThreadLocally(threadId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Delete thread'))),
      );
    }
  }

  void _onFilterChanged(String v) {
    setState(() {
      _filter = v;
      _loading = true;
      _error = null;
    });
    unawaited(_hydrateFromCacheThenReload());
  }

  int get _needsYouCount => _threads
      .where(
        (t) =>
            ThreadStatusKindX.resolve(
              status: t.status,
              yourStatus: t.yourStatus,
            ) ==
            ThreadStatusKind.needsYou,
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final listPane = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ThreadsChrome(
            filter: _filter,
            onFilterChanged: _onFilterChanged,
            needsYouCount: _needsYouCount,
            onCompose: () => setState(() => _composeOpen = true),
          ),
          if (_composeOpen) ...[
            const SizedBox(height: 12),
            _ComposePanel(
              daemon: widget.daemon,
              myHandle: widget.myHandle,
              initialRecipient: _composePrefillRecipient,
              onSent: () {
                setState(() {
                  _composeOpen = false;
                  _composePrefillRecipient = null;
                });
                unawaited(_reload(silent: true));
              },
              onCancel: () => setState(() {
                _composeOpen = false;
                _composePrefillRecipient = null;
              }),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(child: _buildListPane(context)),
        ],
      ),
    );

    final reading = _openId == null
        ? const _EmptyReadingPane()
        : ThreadDetailPanel(
            key: _detailKey,
            daemon: widget.daemon,
            threadId: _openId!,
            myHandle: widget.myHandle,
            embedded: true,
            muted: _mutedIds.contains(_openId),
            onMuteToggle: () => _toggleMute(_openId!),
            onBack: () => setState(() => _openId = null),
            onListChanged: () => unawaited(_reload(silent: true)),
            onThreadClosed: _applyClosedLocally,
            onGone: () {
              final id = _openId;
              if (id != null) _removeThreadLocally(id);
            },
          );

    // Cursor-style drag splits: list · reading · (stats lives inside detail).
    return ResizableContainer(
      direction: Axis.horizontal,
      children: [
        ResizableChild(
          size: const ResizableSize.pixels(304, min: 220, max: 480),
          divider: _splitDivider(0),
          child: listPane,
        ),
        ResizableChild(size: const ResizableSize.expand(), child: reading),
      ],
    );
  }

  Widget _buildListPane(BuildContext context) {
    if (_loading) {
      return const Center(
        child: MutandeOrb.standard(semanticLabel: 'Loading threads…'),
      );
    }
    if (_error != null) {
      return PaneQuietState(
        title: "Couldn't load threads",
        body: _error!,
        onRetry: _reload,
        icon: Icons.cloud_off_outlined,
      );
    }
    if (_visible.isEmpty) {
      final (title, body) = switch (_filter) {
        'needs_action' => (
          'Nothing needs you',
          'Open threads waiting on a human answer show up here.',
        ),
        'open' => (
          'No open threads',
          'Closed mail is under Closed — or start one with Compose.',
        ),
        'closed' => (
          'No closed threads',
          'Finished handoffs land here after you close them.',
        ),
        'collab' => (
          'No collab threads',
          'Cards from boards still show in All. Open Collab to start a board.',
        ),
        'unfiled' => (
          'No unfiled threads',
          'Mail that isn’t on a board lands here.',
        ),
        _ => (
          'No threads yet',
          'Compose a handoff, or wait for an agent ping.',
        ),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: PaneQuietState(title: title, body: body),
      );
    }
    return ListView.builder(
      controller: _listScroll,
      padding: EdgeInsets.zero,
      itemCount: _visible.length,
      itemBuilder: (context, i) {
        final t = _visible[i];
        return _ThreadRow(
          key: ValueKey(t.id),
          thread: t,
          myHandle: widget.myHandle,
          avatarUrl: _avatarForThread(t),
          selected: t.id == _openId,
          muted: _mutedIds.contains(t.id),
          onTap: () => setState(() => _openId = t.id),
          onClose: t.status == 'closed'
              ? null
              : () => _closeThreadFromList(t.id),
          onDelete: () => _deleteThreadFromList(t.id),
          onMuteToggle: () => _toggleMute(t.id),
        );
      },
    );
  }
}

class _EmptyReadingPane extends StatelessWidget {
  const _EmptyReadingPane();

  @override
  Widget build(BuildContext context) {
    return const PaneQuietState(
      title: 'Select a thread',
      body: 'Pick one from the list — replies nest here beside it.',
      icon: Icons.mark_email_unread_outlined,
    );
  }
}

/// Pills chrome — All / Needs you / Open / Closed / Collab / Unfiled, Compose trailing.
class _ThreadsChrome extends StatelessWidget {
  const _ThreadsChrome({
    required this.filter,
    required this.onFilterChanged,
    required this.needsYouCount,
    required this.onCompose,
  });

  final String filter;
  final ValueChanged<String> onFilterChanged;
  final int needsYouCount;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ScopePill(
                  label: 'All',
                  selected: filter == 'all',
                  onTap: () => onFilterChanged('all'),
                ),
                const SizedBox(width: 4),
                _ScopePill(
                  label: 'Needs you',
                  selected: filter == 'needs_action',
                  badge: needsYouCount,
                  onTap: () => onFilterChanged('needs_action'),
                ),
                const SizedBox(width: 4),
                _ScopePill(
                  label: 'Open',
                  selected: filter == 'open',
                  onTap: () => onFilterChanged('open'),
                ),
                const SizedBox(width: 4),
                _ScopePill(
                  label: 'Closed',
                  selected: filter == 'closed',
                  onTap: () => onFilterChanged('closed'),
                ),
                const SizedBox(width: 4),
                _ScopePill(
                  label: 'Collab',
                  selected: filter == 'collab',
                  onTap: () => onFilterChanged('collab'),
                ),
                const SizedBox(width: 4),
                _ScopePill(
                  label: 'Unfiled',
                  selected: filter == 'unfiled',
                  onTap: () => onFilterChanged('unfiled'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Compose (C)',
          child: Material(
            color: MutandeColors.stone800,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onCompose,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  LucideIcons.squarePen,
                  size: 15,
                  color: MutandeColors.stone50,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? MutandeColors.stone800 : MutandeColors.stone100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? MutandeColors.stone800 : MutandeColors.stone200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? MutandeColors.stone50
                    : MutandeColors.stone600,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MutandeColors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pulse list row — unread weight, circular mark, last-author snippet, relative time.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    super.key,
    required this.thread,
    required this.onTap,
    this.myHandle,
    this.avatarUrl,
    this.selected = false,
    this.muted = false,
    this.onClose,
    this.onDelete,
    this.onMuteToggle,
  });

  final ThreadSummary thread;
  final VoidCallback onTap;
  final String? myHandle;
  final String? avatarUrl;
  final bool selected;
  final bool muted;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onMuteToggle;

  @override
  Widget build(BuildContext context) {
    final title = _rowTitle(thread, myHandle: myHandle);
    final snippet = _rowSnippet(thread, myHandle: myHandle);
    final status = _rowStatus(thread);
    final unread = status == ThreadStatusKind.needsYou;
    final time = formatRelativeTime(thread.updatedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (details) {
            final items = <PopupMenuEntry<String>>[
              if (onMuteToggle != null)
                PopupMenuItem(
                  value: 'mute',
                  child: Text(muted ? 'Unmute' : 'Mute'),
                ),
              if (onClose != null)
                const PopupMenuItem(value: 'close', child: Text('Close')),
              if (onDelete != null)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ];
            if (items.isEmpty) return;
            showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              items: items,
            ).then((value) {
              if (value == 'mute') onMuteToggle?.call();
              if (value == 'close') onClose?.call();
              if (value == 'delete') onDelete?.call();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            color: selected ? MutandeColors.stone100 : Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                  width: 8,
                  child: unread
                      ? Center(
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: MutandeColors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
                _ThreadMark(thread: thread, label: title, avatarUrl: avatarUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: MutandeColors.stone800,
                          fontWeight: unread || selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      if (thread.collabName != null &&
                          thread.collabName!.trim().isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          thread.collabName!.trim().toLowerCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: MutandeColors.stone400,
                                fontSize: 11,
                                height: 1.2,
                              ),
                        ),
                      ],
                      if (snippet.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
                const SizedBox(width: 8),
                // List pane: Muted · else relative time (+ Needs you when pending).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (muted)
                      Text(
                        'Muted',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: MutandeColors.stone400,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else if (time.isNotEmpty)
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: unread
                              ? MutandeColors.amber
                              : MutandeColors.stone400,
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (!muted && unread) ...[
                      const SizedBox(height: 4),
                      ThreadStatusBadge(kind: status, compact: true),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadMark extends StatelessWidget {
  const _ThreadMark({
    required this.thread,
    required this.label,
    this.avatarUrl,
  });

  final ThreadSummary thread;
  final String label;
  final String? avatarUrl;

  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    final host = _hostSlug(thread.agentBadge);
    final selfCollab = _selfCollabTitle(thread) != null;
    final needsYou = _rowStatus(thread) == ThreadStatusKind.needsYou;
    final live = isRecentActivity(thread.updatedAt);
    final plate = needsYou
        ? MutandeColors.amberSoft.withValues(alpha: 0.8)
        : MutandeColors.stone100;
    final border = needsYou
        ? MutandeColors.amber.withValues(alpha: 0.35)
        : MutandeColors.stone200;

    final initials = Text(
      _initialsFor(label),
      style: TextStyle(
        color: MutandeColors.stone500,
        fontWeight: FontWeight.w600,
        fontSize: _size * 0.34,
        letterSpacing: 0.2,
      ),
    );

    Widget mark;
    if (!selfCollab && avatarUrl != null) {
      mark = ContactAvatar(url: avatarUrl!, size: _size, fallback: initials);
    } else if (host != null) {
      mark = AiHostIcon(host, size: _size, showPlate: false);
    } else {
      mark = initials;
    }

    return SizedBox(
      width: _size + 4,
      height: _size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: _size,
              height: _size,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: plate,
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: mark,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _PresenceDot(live: live, attention: needsYou),
          ),
        ],
      ),
    );
  }
}

class _PresenceDot extends StatefulWidget {
  const _PresenceDot({required this.live, required this.attention});

  final bool live;
  final bool attention;

  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.live && !widget.attention) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PresenceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pulse = widget.live && !widget.attention;
    if (pulse && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.attention
        ? MutandeColors.amber
        : widget.live
        ? MutandeColors.emerald
        : MutandeColors.stone200;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final glow = widget.live && !widget.attention
            ? 0.45 + 0.55 * _c.value
            : 1.0;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: glow),
            shape: BoxShape.circle,
            border: Border.all(color: MutandeColors.stone50, width: 1.5),
          ),
        );
      },
    );
  }
}

/// List-row status — always show so open/closed read at a glance.
ThreadStatusKind _rowStatus(ThreadSummary t) {
  return ThreadStatusKindX.resolve(status: t.status, yourStatus: t.yourStatus);
}

String _rowTitle(ThreadSummary t, {String? myHandle}) {
  final subject = t.lastSubject?.trim();
  if (subject != null && subject.isNotEmpty) return subject;
  if (t.audience.trim() == '@all') return '@all';
  final self = _selfCollabTitle(t);
  return formatMailAddress(self ?? t.from, myHandle: myHandle);
}

/// Body line: latest message preview (daemon-opened plaintext).
String _rowMeta(ThreadSummary t) {
  final preview = t.lastPreview?.trim();
  if (preview != null && preview.isNotEmpty) return preview;
  return '';
}

String _plainPreview(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(RegExp(r'^#+\s*'), '');
  s = s.replaceAll('**', '');
  s = s.replaceAll(RegExp(r'`+'), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

String _lastAuthor(ThreadSummary t, {String? myHandle}) {
  final from = (t.lastFrom ?? t.from).trim();
  if (from.isEmpty) return '';
  return formatMailAddress(from, myHandle: myHandle);
}

/// `@author` + latest preview — Pulse snippet line.
String _rowSnippet(ThreadSummary t, {String? myHandle}) {
  final preview = _plainPreview(_rowMeta(t));
  if (preview.isEmpty) return '';
  final author = _lastAuthor(t, myHandle: myHandle);
  if (author.isEmpty) return preview;
  return '$author  $preview';
}

String? _agentSlug(String? badge) {
  if (badge == null || badge.isEmpty || badge == 'default') return null;
  return badge;
}

String? _hostSlug(String? badge) {
  final slug = _agentSlug(badge);
  if (slug == null) return null;
  if (AiHostIcon.assetFor(slug) != null) return slug.toLowerCase();
  return null;
}

String _initialsFor(String label) {
  final bare = label.split('/').first;
  final local = bare.contains('@') ? bare.split('@').first : bare;
  final cleaned = local.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (cleaned.isEmpty) return '?';
  if (cleaned.length == 1) return cleaned.toUpperCase();
  return cleaned.substring(0, 2).toUpperCase();
}

/// Same-user agent handoff: title the row by audience (target agent).
String? _selfCollabTitle(ThreadSummary t) {
  final fromBare = t.from.split('/').first;
  final audBare = t.audience.split('/').first;
  if (fromBare.isEmpty || audBare.isEmpty || fromBare != audBare) return null;
  if (t.audience == t.from) return null;
  return t.audience;
}

class _ComposePanel extends StatefulWidget {
  const _ComposePanel({
    required this.daemon,
    this.myHandle,
    this.initialRecipient,
    required this.onSent,
    required this.onCancel,
  });

  final DaemonClient daemon;
  final String? myHandle;
  final String? initialRecipient;
  final VoidCallback onSent;
  final VoidCallback onCancel;

  @override
  State<_ComposePanel> createState() => _ComposePanelState();
}

class _ComposePanelState extends State<_ComposePanel> {
  TextEditingController? _recipientController;
  final _notes = TextEditingController();
  bool _sending = false;
  String? _error;
  bool _seededRecipient = false;
  ComposeTransportWarning? _transportWarning;
  bool _enterpriseWarn = false;
  List<AgentInfo> _agents = const [];
  TransportPrefs _transportPrefs = const TransportPrefs();
  Timer? _resolveDebounce;
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTransportContext());
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadTransportContext() async {
    TransportPrefs prefs = const TransportPrefs();
    List<AgentInfo> agents = const [];
    try {
      // Prefer hub defaults when courier is reachable; fall back to local cache.
      try {
        prefs = TransportPrefs.fromJson(
          await widget.daemon.getTransportDefaults(),
        );
      } catch (_) {
        prefs = await TransportPrefsStore().load();
      }
    } catch (_) {}
    try {
      agents = (await widget.daemon.listAgents()).agents;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _transportPrefs = prefs;
      _agents = agents;
    });
    unawaited(
      _resolveWarning(_recipientController?.text ?? widget.initialRecipient),
    );
  }

  void _onRecipientChanged(String text) {
    _resolveDebounce?.cancel();
    _resolveDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      unawaited(_resolveWarning(text));
    });
  }

  Future<void> _resolveWarning(String? text) async {
    final recipient = text?.trim() ?? '';
    final gen = ++_resolveGeneration;
    var warning = resolveComposeTransportWarning(
      recipient: recipient,
      agents: _agents,
      prefs: _transportPrefs,
    );

    // Registry enterprise address — not in org agent list (§7.2).
    var enterpriseWarn = warning?.isEnterprise ?? false;
    if (!enterpriseWarn) {
      final candidate = registryAddressCandidate(recipient);
      if (candidate != null) {
        final listing = await widget.daemon.getRegistryListing(candidate);
        if (!mounted || gen != _resolveGeneration) return;
        if (listing != null && listing.showBanner) {
          enterpriseWarn = true;
          warning ??= ComposeTransportWarning.fromSlot(
            transport: AgentTransport.mcp,
            trustTier: TrustTier.enterprise,
          );
        }
      }
    }

    if (!mounted || gen != _resolveGeneration) return;
    if (warning?.label == _transportWarning?.label &&
        enterpriseWarn == _enterpriseWarn) {
      return;
    }
    setState(() {
      _transportWarning = warning;
      _enterpriseWarn = enterpriseWarn;
    });
  }

  Future<List<String>> _recipientOptions(String input) async {
    final trimmed = input.trim();
    final lower = trimmed.toLowerCase();
    final orgAll = _orgBroadcastFromHandle(widget.myHandle);

    // Self-collaboration shorthand: @cursor, @claude, @all —
    // not @all@org (second @ means org broadcast / handle path below).
    final selfShorthand =
        trimmed.isEmpty ||
        (trimmed.startsWith('@') && !trimmed.substring(1).contains('@'));
    if (selfShorthand) {
      try {
        final list = await widget.daemon.listAgents();
        final suggestions = <String>[
          '@all',
          if (orgAll != null) orgAll,
          ...list.agents.map((a) => '@${a.slug.toLowerCase()}'),
        ];
        if (trimmed.isEmpty || lower == '@') return suggestions;
        return suggestions.where((s) => s.startsWith(lower)).toList();
      } catch (_) {
        if (trimmed.isEmpty || lower.startsWith('@')) {
          return ['@all', if (orgAll != null) orgAll];
        }
      }
    }

    // Org broadcast: @all@acme (gated out of self-shorthand by the second @).
    if (orgAll != null &&
        (orgAll.startsWith(lower) || lower.startsWith('@all@'))) {
      return [orgAll];
    }

    final bare = _bareHandleFromInput(trimmed);
    if (bare == null) return const [];
    try {
      final list = await widget.daemon.listAgents(handle: bare);
      return [bare, ...list.agents.map((a) => '$bare/${a.slug.toLowerCase()}')];
    } catch (_) {
      return [bare];
    }
  }

  /// `alice@acme` / `alice@acme/cursor` → `@all@acme`.
  static String? _orgBroadcastFromHandle(String? handle) {
    if (handle == null || handle.isEmpty) return null;
    final at = handle.lastIndexOf('@');
    if (at < 0 || at >= handle.length - 1) return null;
    var org = handle.substring(at + 1);
    final slash = org.indexOf('/');
    if (slash >= 0) org = org.substring(0, slash);
    if (org.isEmpty) return null;
    return '@all@${org.toLowerCase()}';
  }

  String? _bareHandleFromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // Bare @all / @slug are handled above — not user handles.
    if (trimmed.startsWith('@') && !trimmed.substring(1).contains('@')) {
      return null;
    }
    final slash = trimmed.indexOf('/');
    final base = slash >= 0 ? trimmed.substring(0, slash) : trimmed;
    final at = base.lastIndexOf('@');
    if (at <= 0 || at >= base.length - 1) return null;
    return base.toLowerCase();
  }

  Future<void> _send() async {
    final recipient = _recipientController?.text.trim() ?? '';
    final notes = _notes.text.trim();
    if (recipient.isEmpty || notes.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.daemon.forwardDraft(recipient: recipient, notes: notes);
      _recipientController?.clear();
      _notes.clear();
      widget.onSent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyDaemonError(e, what: 'Send'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Autocomplete<String>(
            optionsBuilder: (text) async => _recipientOptions(text.text),
            onSelected: (value) {
              _recipientController?.text = value;
              unawaited(_resolveWarning(value));
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              _recipientController = controller;
              final seed = widget.initialRecipient?.trim();
              if (!_seededRecipient && seed != null && seed.isNotEmpty) {
                _seededRecipient = true;
                if (controller.text.isEmpty) controller.text = seed;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  hintText: '@claude, @all, or bob@acme/claude',
                  labelText: 'Recipient',
                ),
                enabled: !_sending,
                onChanged: _onRecipientChanged,
                onSubmitted: (_) => onSubmit(),
              );
            },
          ),
          if (_transportWarning != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ComposeNonE2eChip(warning: _transportWarning!),
            ),
          ],
          if (_enterpriseWarn) ...[
            const SizedBox(height: 8),
            const EnterpriseWarnBanner(),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Short note for their agent',
            ),
            minLines: 2,
            maxLines: 4,
            enabled: !_sending,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            PaneInlineError(message: _error!),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _sending ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ThreadDetailPanel extends StatefulWidget {
  const ThreadDetailPanel({
    super.key,
    required this.daemon,
    required this.threadId,
    required this.onBack,
    this.myHandle,
    this.embedded = false,
    this.onListChanged,
    this.onThreadClosed,
    this.onGone,
    this.muted = false,
    this.onMuteToggle,
  });

  final DaemonClient daemon;
  final String threadId;
  final VoidCallback onBack;
  final String? myHandle;

  /// Side-panel mode: close control instead of full-page back chrome.
  final bool embedded;

  /// Quiet list refresh after reply / activity (no full-panel orb).
  final VoidCallback? onListChanged;

  /// Local list patch after close succeeds.
  final ValueChanged<String>? onThreadClosed;

  /// Remove from list + clear selection after delete.
  final VoidCallback? onGone;

  final bool muted;
  final VoidCallback? onMuteToggle;

  @override
  State<ThreadDetailPanel> createState() => _ThreadDetailPanelState();
}

class _ThreadDetailPanelState extends State<ThreadDetailPanel> {
  bool _loading = true;
  bool _silentLoadInFlight = false;
  String? _error;
  ThreadDetailResult? _detail;
  final _reply = TextEditingController();
  bool _sending = false;
  String? _replyToMessageId;
  String? _replyToHandle;
  String? _upvotingMessageId;
  bool _downgradeBusy = false;
  int? _hotDivider;

  ResizableDivider _splitDivider(int id) {
    final hot = _hotDivider == id;
    return ResizableDivider(
      thickness: hot ? 2 : 1,
      padding: 3,
      color: hot ? MutandeColors.bronze : MutandeColors.stone200,
      cursor: SystemMouseCursors.resizeColumn,
      onHoverEnter: () => setState(() => _hotDivider = id),
      onHoverExit: () {
        if (_hotDivider == id) setState(() => _hotDivider = null);
      },
      onDragStart: () => setState(() => _hotDivider = id),
      onDragEnd: () => setState(() => _hotDivider = null),
    );
  }

  Future<void> _toggleUpvote(ThreadMessageView message) async {
    if (_upvotingMessageId != null) return;
    setState(() => _upvotingMessageId = message.id);
    try {
      final summary = await widget.daemon.toggleMessageUpvote(
        threadId: widget.threadId,
        messageId: message.id,
      );
      if (!mounted) return;
      setState(() {
        _detail = ThreadDetailResult(
          id: _detail!.id,
          kind: _detail!.kind,
          status: _detail!.status,
          from: _detail!.from,
          audience: _detail!.audience,
          yourStatus: _detail!.yourStatus,
          enterpriseListingId: _detail!.enterpriseListingId,
          pendingDowngrade: _detail!.pendingDowngrade,
          messages: _detail!.messages
              .map((m) => m.id == message.id ? m.copyWithUpvotes(summary) : m)
              .toList(),
        );
      });
      // Stats panel reads upvote totals from detail — already patched locally.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Upvote'))),
      );
    } finally {
      if (mounted) setState(() => _upvotingMessageId = null);
    }
  }

  Future<void> _approveDowngrade(ThreadDowngradeProposalView proposal) async {
    final ok = await confirmThreadAction(
      context,
      title: 'End E2E for this thread?',
      body:
          proposal.prompt ??
          'Adding @${proposal.proposedSlug} (web) ends E2E for this thread',
      confirmLabel: 'Approve',
    );
    if (ok != true || !mounted) return;
    setState(() => _downgradeBusy = true);
    try {
      await widget.daemon.approveThreadDowngrade(
        threadId: widget.threadId,
        proposalId: proposal.id,
      );
      if (!mounted) return;
      await _load(silent: true);
      widget.onListChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Approve'))),
      );
    } finally {
      if (mounted) setState(() => _downgradeBusy = false);
    }
  }

  Future<void> _denyDowngrade(ThreadDowngradeProposalView proposal) async {
    setState(() => _downgradeBusy = true);
    try {
      await widget.daemon.denyThreadDowngrade(
        threadId: widget.threadId,
        proposalId: proposal.id,
      );
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyDaemonError(e, what: 'Deny'))),
      );
    } finally {
      if (mounted) setState(() => _downgradeBusy = false);
    }
  }

  void _startReplyTo(ThreadMessageView message) {
    setState(() {
      _replyToMessageId = message.id;
      _replyToHandle = message.fromHandle;
    });
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToMessageId = null;
      _replyToHandle = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ThreadDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _reply.clear();
      _replyToMessageId = null;
      _replyToHandle = null;
      _load();
    }
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  /// Quiet refresh when the list row fingerprint for this thread changes.
  void softRefresh() => unawaited(_load(silent: true));

  Future<void> _load({bool silent = false}) async {
    if (silent) {
      if (_loading || _silentLoadInFlight) return;
      _silentLoadInFlight = true;
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await widget.daemon.getThread(widget.threadId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        if (silent) _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _detail != null) return;
      setState(() {
        _error = friendlyDaemonError(e, what: 'This thread');
        _loading = false;
      });
    } finally {
      if (silent) _silentLoadInFlight = false;
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.daemon.replyToThread(
        threadId: widget.threadId,
        notes: text,
        inReplyTo: _replyToMessageId,
      );
      if (!mounted) return;
      _reply.clear();
      _clearReplyTarget();
      await _load(silent: true);
      widget.onListChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyDaemonError(e, what: 'Reply'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _closeThread() async {
    final ok = await confirmThreadAction(
      context,
      title: 'Close thread?',
      body: 'This marks the thread closed. You can still find it under Closed.',
      confirmLabel: 'Close',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.daemon.closeThread(widget.threadId);
      if (!mounted) return;
      if (widget.onThreadClosed != null) {
        widget.onThreadClosed!(widget.threadId);
      } else {
        widget.onListChanged?.call();
      }
      // Parent may have cleared selection (filter dropped this row).
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyDaemonError(e, what: 'Close thread'));
    }
  }

  Future<void> _deleteThread() async {
    final ok = await confirmThreadAction(
      context,
      title: 'Delete thread?',
      body:
          'This removes the thread from your inbox. If you started it, the messages are purged.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await widget.daemon.deleteThread(widget.threadId);
      if (!mounted) return;
      if (widget.onGone != null) {
        widget.onGone!();
      } else {
        widget.onBack();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyDaemonError(e, what: 'Delete thread'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          Row(
            children: [
              IconButton(
                tooltip: 'Back to threads',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 20),
                color: const Color(0xFF57534E),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                'Thread',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF78716C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
                color: const Color(0xFF78716C),
                visualDensity: VisualDensity.compact,
              ),
              if (_detail != null)
                PopupMenuButton<String>(
                  tooltip: 'Thread actions',
                  onSelected: (value) {
                    if (value == 'mute') widget.onMuteToggle?.call();
                    if (value == 'close') _closeThread();
                    if (value == 'delete') _deleteThread();
                  },
                  itemBuilder: (context) => [
                    if (widget.onMuteToggle != null)
                      PopupMenuItem(
                        value: 'mute',
                        child: Text(widget.muted ? 'Unmute' : 'Mute'),
                      ),
                    if (_detail!.status != 'closed')
                      const PopupMenuItem(value: 'close', child: Text('Close')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        if (_loading)
          const Expanded(
            child: Center(
              child: MutandeOrb.standard(semanticLabel: 'Loading thread…'),
            ),
          )
        else if (_detail == null)
          Expanded(
            child: PaneQuietState(
              title: 'Thread unavailable',
              body: _error ?? 'This thread couldn’t be opened.',
              onRetry: _load,
              icon: Icons.mark_email_unread_outlined,
            ),
          )
        else ...[
          Expanded(
            child: ThreadRelayReading(
              detail: _detail!,
              myHandle: widget.myHandle,
              muted: widget.muted,
              reply: _reply,
              sending: _sending,
              replyToHandle: _replyToHandle == null
                  ? null
                  : formatMailAddress(
                      _replyToHandle!,
                      myHandle: widget.myHandle,
                    ),
              nested: _replyToMessageId != null,
              onSend: _sendReply,
              onClearTarget: _clearReplyTarget,
              onReply: _startReplyTo,
              onUpvote: _toggleUpvote,
              upvotingId: _upvotingMessageId,
              onRefresh: () =>
                  unawaited(_load(silent: widget.embedded && _detail != null)),
              onClose: _detail!.status == 'closed' ? null : _closeThread,
              onDelete: _deleteThread,
              onMuteToggle: widget.onMuteToggle,
              leading: [
                if (_detail!.isEnterpriseThread) const EnterpriseWarnBanner(),
                if (_detail!.pendingDowngrade?.isPending == true)
                  DowngradeConsentBanner(
                    prompt:
                        _detail!.pendingDowngrade!.prompt ??
                        'Adding @${_detail!.pendingDowngrade!.proposedSlug} (web) ends E2E for this thread',
                    busy: _downgradeBusy,
                    onApprove: () =>
                        _approveDowngrade(_detail!.pendingDowngrade!),
                    onDeny: () => _denyDowngrade(_detail!.pendingDowngrade!),
                  ),
                if (_error != null)
                  PaneInlineError(message: _error!, onRetry: () => _load()),
              ],
            ),
          ),
        ],
      ],
    );

    if (!widget.embedded) return pane;

    if (_loading || _detail == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: pane,
      );
    }

    return ResizableContainer(
      direction: Axis.horizontal,
      children: [
        ResizableChild(
          size: const ResizableSize.expand(),
          divider: _splitDivider(1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: pane,
          ),
        ),
        ResizableChild(
          size: const ResizableSize.pixels(200, min: 180, max: 360),
          child: ThreadInspectorSidebar(
            detail: _detail!,
            myHandle: widget.myHandle,
          ),
        ),
      ],
    );
  }
}
