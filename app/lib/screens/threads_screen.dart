import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/ai_host_icon.dart';
import '../widgets/home_search_field.dart';
import '../widgets/message_attachments.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thread_message_tree.dart';
import '../widgets/thread_status_badge.dart';
import '../widgets/downgrade_consent_banner.dart';
import '../widgets/enterprise_warn_banner.dart';
import '../widgets/transport_chip.dart';

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

/// Stitch home threads — filters, list rows, search + new thread footer.
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
    this.searchController,
    this.searchFocus,
    this.onSearchQueryChanged,
    this.onSearchSubmit,
    this.onClearSearch,
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

  /// Home search — Compose + Search row (Penpot Threads).
  final TextEditingController? searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearchQueryChanged;
  final VoidCallback? onSearchSubmit;
  final VoidCallback? onClearSearch;

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
      final threads = await widget.daemon.listThreads(
        filter: _filter == 'all' ? null : _filter,
      );
      if (!mounted) return;
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
    final openStillPresent =
        openId == null || next.any((t) => t.id == openId);

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
      _threads = [for (final t in _threads) if (t.id != threadId) t];
      if (_openId == threadId) _openId = null;
    });
  }

  void _applyClosedLocally(String threadId) {
    final dropFromFilter =
        _filter == 'open' || _filter == 'needs_action';
    setState(() {
      if (dropFromFilter) {
        _threads = [for (final t in _threads) if (t.id != threadId) t];
        if (_openId == threadId) _openId = null;
      } else {
        _threads = [
          for (final t in _threads)
            if (t.id == threadId) t.copyWith(status: 'closed') else t,
        ];
      }
    });
  }

  List<ThreadSummary> get _visible => _threads;

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

  @override
  Widget build(BuildContext context) {
    final listPane = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ThreadsToolbar(
            filter: _filter,
            onFilterChanged: (v) {
              setState(() {
                _filter = v;
                _loading = true;
                _error = null;
              });
              unawaited(_hydrateFromCacheThenReload());
            },
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
          _ThreadsListToolbar(
            onCompose: () => setState(() => _composeOpen = true),
            searchController: widget.searchController,
            searchFocus: widget.searchFocus,
            onSearchQueryChanged: widget.onSearchQueryChanged,
            onSearchSubmit: widget.onSearchSubmit,
            onClearSearch: widget.onClearSearch,
          ),
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
        _ => (
          'No threads yet',
          'Compose a handoff, or wait for an agent ping.',
        ),
      };
      return PaneQuietState(title: title, body: body);
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

/// Inbox filter scope (search lives on the home chrome strip).
class _ThreadsToolbar extends StatelessWidget {
  const _ThreadsToolbar({required this.filter, required this.onFilterChanged});

  final String filter;
  final ValueChanged<String> onFilterChanged;

  String get _filterLabel => switch (filter) {
    'needs_action' => 'Needs you',
    'open' => 'Open',
    'closed' => 'Closed',
    _ => 'All',
  };

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: 'Filter scope',
        padding: EdgeInsets.zero,
        onSelected: onFilterChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'all', child: Text('All')),
          PopupMenuItem(value: 'needs_action', child: Text('Needs you')),
          PopupMenuItem(value: 'open', child: Text('Open')),
          PopupMenuItem(value: 'closed', child: Text('Closed')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _filterLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF57534E),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 16, color: Color(0xFFA8A29E)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadsListToolbar extends StatelessWidget {
  const _ThreadsListToolbar({
    required this.onCompose,
    this.searchController,
    this.searchFocus,
    this.onSearchQueryChanged,
    this.onSearchSubmit,
    this.onClearSearch,
  });

  final VoidCallback onCompose;
  final TextEditingController? searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearchQueryChanged;
  final VoidCallback? onSearchSubmit;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final search = searchController != null &&
        searchFocus != null &&
        onSearchQueryChanged != null &&
        onSearchSubmit != null &&
        onClearSearch != null;

    return Row(
      children: [
        if (search)
          Expanded(
            child: SizedBox(
              height: 32,
              child: HomeSearchField(
                controller: searchController!,
                focusNode: searchFocus!,
                onChanged: onSearchQueryChanged!,
                onSubmit: onSearchSubmit!,
                onClear: onClearSearch!,
              ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Compose (C)',
          onPressed: onCompose,
          icon: const Icon(LucideIcons.squarePen, size: 18),
          color: const Color(0xFF292524),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    super.key,
    required this.thread,
    required this.onTap,
    this.myHandle,
    this.selected = false,
    this.muted = false,
    this.onClose,
    this.onDelete,
    this.onMuteToggle,
  });

  final ThreadSummary thread;
  final VoidCallback onTap;
  final String? myHandle;
  final bool selected;
  final bool muted;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onMuteToggle;

  @override
  Widget build(BuildContext context) {
    final title = _rowTitle(thread, myHandle: myHandle);
    final meta = _rowMeta(thread);
    final status = _rowStatus(thread);
    final time = formatClockHm(thread.updatedAt);

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
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? MutandeColors.stone100 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? MutandeColors.stone200 : Colors.transparent,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: 3,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? MutandeColors.bronze
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(5, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _ThreadMark(thread: thread, label: title),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: MutandeColors.stone800,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        height: 1.2,
                                      ),
                                ),
                                if (meta.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: MutandeColors.stone400,
                                          height: 1.2,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // List pane: Muted · Needs you · else HH:MM (never Waiting).
                          if (muted)
                            Text(
                              'Muted',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: MutandeColors.stone400,
                                    fontWeight: FontWeight.w500,
                                  ),
                            )
                          else if (status == ThreadStatusKind.needsYou)
                            ThreadStatusBadge(kind: status, compact: true)
                          else if (time.isNotEmpty)
                            Text(
                              time,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: MutandeColors.stone400,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadMark extends StatelessWidget {
  const _ThreadMark({required this.thread, required this.label});

  final ThreadSummary thread;
  final String label;

  @override
  Widget build(BuildContext context) {
    final host = _hostSlug(thread.agentBadge);
    final needsYou = _rowStatus(thread) == ThreadStatusKind.needsYou;
    final plate = needsYou
        ? MutandeColors.amberSoft.withValues(alpha: 0.65)
        : MutandeColors.stone100;
    final border = needsYou
        ? MutandeColors.amber.withValues(alpha: 0.28)
        : MutandeColors.stone200;

    Widget mark;
    if (host != null) {
      mark = AiHostIcon(host, size: 28, showPlate: false);
    } else {
      final initials = _initialsFor(label);
      mark = Text(
        initials,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFF78716C),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      );
    }

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: mark,
    );
  }
}

/// List-row status — always show so open/closed read at a glance.
ThreadStatusKind _rowStatus(ThreadSummary t) {
  return ThreadStatusKindX.resolve(status: t.status, yourStatus: t.yourStatus);
}

/// Header/stats: only surface when it changes what you should do.
ThreadStatusKind? _actionStatus({required String status, String? yourStatus}) {
  final resolved = ThreadStatusKindX.resolve(
    status: status,
    yourStatus: yourStatus,
  );
  if (resolved == ThreadStatusKind.open) return null;
  return resolved;
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
        prefs = TransportPrefs.fromJson(await widget.daemon.getTransportDefaults());
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
      return [
        bare,
        ...list.agents.map((a) => '$bare/${a.slug.toLowerCase()}'),
      ];
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
  final ScrollController _messageScroll = ScrollController();
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
      body: proposal.prompt ??
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
    _messageScroll.dispose();
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
            child: ListView(
              controller: _messageScroll,
              padding: const EdgeInsets.only(top: 0, bottom: 16),
              children: [
                _ThreadDetailHeader(
                  detail: _detail!,
                  myHandle: widget.myHandle,
                  muted: widget.muted,
                  onRefresh: widget.embedded && !_loading
                      ? () => _load(silent: _detail != null)
                      : null,
                  onClose: _detail!.status == 'closed' ? null : _closeThread,
                  onDelete: _deleteThread,
                  onMuteToggle: widget.onMuteToggle,
                  onReplyOp: _detail!.status == 'closed'
                      ? null
                      : () {
                          final op = _rootOpMessage(_detail!);
                          if (op != null) _startReplyTo(op);
                        },
                  onUpvoteOp: _detail!.status == 'closed'
                      ? null
                      : () {
                          final op = _rootOpMessage(_detail!);
                          if (op != null) _toggleUpvote(op);
                        },
                  upvotingOp: () {
                    final op = _rootOpMessage(_detail!);
                    return op != null && _upvotingMessageId == op.id;
                  }(),
                ),
                if (_detail!.isEnterpriseThread) ...[
                  const SizedBox(height: 10),
                  const EnterpriseWarnBanner(),
                ],
                if (_detail!.pendingDowngrade?.isPending == true) ...[
                  const SizedBox(height: 10),
                  DowngradeConsentBanner(
                    prompt: _detail!.pendingDowngrade!.prompt ??
                        'Adding @${_detail!.pendingDowngrade!.proposedSlug} (web) ends E2E for this thread',
                    busy: _downgradeBusy,
                    onApprove: () =>
                        _approveDowngrade(_detail!.pendingDowngrade!),
                    onDeny: () => _denyDowngrade(_detail!.pendingDowngrade!),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  PaneInlineError(message: _error!, onRetry: () => _load()),
                ],
                const SizedBox(height: 12),
                for (final node in flattenThreadMessages(_detail!.messages))
                  if (!_isRootOpNode(node, _detail!))
                    _ThreadMessageTile(
                      key: ValueKey(node.message.id),
                      node: node,
                      myHandle: widget.myHandle,
                      opHandle: _detail!.from,
                      onReply: _detail!.status == 'closed'
                          ? null
                          : () => _startReplyTo(node.message),
                      onUpvote: _detail!.status == 'closed'
                          ? null
                          : () => _toggleUpvote(node.message),
                      upvoting: _upvotingMessageId == node.message.id,
                    ),
              ],
            ),
          ),
          _ThreadReplyComposer(
            controller: _reply,
            sending: _sending,
            closed: _detail!.status == 'closed',
            nested: _replyToMessageId != null,
            replyToHandle: _replyToHandle == null
                ? null
                : formatMailAddress(_replyToHandle!, myHandle: widget.myHandle),
            onClearTarget: _clearReplyTarget,
            onSend: _sendReply,
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

    // Reading (left-aligned) · stats — drag the divider like Cursor.
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
          child: _ThreadStatsPanel(detail: _detail!, myHandle: widget.myHandle),
        ),
      ],
    );
  }
}

/// Humanize hub kind; null when empty / unknown.
String? _humanizeThreadKind(String kind) {
  switch (kind.trim().toLowerCase()) {
    case 'broadcast':
      return 'Broadcast';
    case 'direct':
      return 'Direct';
    case '':
      return null;
    default:
      if (kind.isEmpty) return null;
      return kind[0].toUpperCase() + kind.substring(1);
  }
}

/// Direct is obvious from header `to @…`; broadcast less so when audience is `@all@org`.
bool _kindObviousInHeader(ThreadDetailResult detail) {
  final k = detail.kind.trim().toLowerCase();
  if (k == 'direct') return true;
  if (k == 'broadcast') {
    final aud = detail.audience.trim();
    return aud == '@all' || aud.startsWith('@all@');
  }
  return false;
}

class _ThreadStatsPanel extends StatelessWidget {
  const _ThreadStatsPanel({required this.detail, this.myHandle});

  final ThreadDetailResult detail;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final participants = <String>{};
    for (final m in detail.messages) {
      if (m.fromHandle.isNotEmpty) participants.add(m.fromHandle);
    }
    if (detail.from.isNotEmpty) participants.add(detail.from);
    // Bare @all is the group audience, not a participant handle.
    if (detail.audience.isNotEmpty &&
        detail.audience != detail.from &&
        detail.audience.trim() != '@all') {
      participants.add(detail.audience);
    }

    var upvoteTotal = 0;
    for (final m in detail.messages) {
      upvoteTotal += m.upvotes?.count ?? 0;
    }

    // Header already shows compact badge for non-open — don't restate Status.
    // Fold Waiting into the lead metrics (list pane never shows Waiting).
    final status = ThreadStatusKindX.resolve(
      status: detail.status,
      yourStatus: detail.yourStatus,
    );
    final showWaitingInMetrics = status == ThreadStatusKind.waiting;

    final kindLabel = _humanizeThreadKind(detail.kind);
    final showKind = kindLabel != null && !_kindObviousInHeader(detail);

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: MutandeColors.stone500,
      fontWeight: FontWeight.w500,
      fontSize: 11,
      letterSpacing: 0.1,
    );
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: MutandeColors.stone800,
      height: 1.25,
      fontSize: 13,
    );
    final metricStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: MutandeColors.stone800,
      fontWeight: FontWeight.w600,
      height: 1.2,
      fontSize: 13,
    );
    final quietStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: MutandeColors.stone400,
      height: 1.2,
      fontSize: 10.5,
    );

    final msgCount = detail.messages.length;
    final msgLabel = msgCount == 1 ? '1 message' : '$msgCount messages';

    return DecoratedBox(
      decoration: const BoxDecoration(color: MutandeColors.stone50),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          // Lead: coordination + volume (+ Waiting when list can't show it).
          Text.rich(
            TextSpan(
              style: metricStyle,
              children: [
                TextSpan(
                  text: '↑ $upvoteTotal',
                  style: metricStyle?.copyWith(
                    color: upvoteTotal > 0
                        ? MutandeColors.bronze
                        : MutandeColors.stone600,
                  ),
                ),
                TextSpan(text: ' · ', style: quietStyle),
                TextSpan(text: msgLabel),
                if (showWaitingInMetrics) ...[
                  TextSpan(text: ' · ', style: quietStyle),
                  TextSpan(
                    text: ThreadStatusKind.waiting.label,
                    style: metricStyle?.copyWith(
                      color: MutandeColors.bronze,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('coordination weight', style: quietStyle),
          if (showKind && kindLabel != null) ...[
            const SizedBox(height: 16),
            Text('Kind', style: labelStyle),
            const SizedBox(height: 4),
            Text(kindLabel, style: valueStyle),
          ],
          const SizedBox(height: 18),
          Text('Participants', style: labelStyle),
          const SizedBox(height: 8),
          ...participants.map((p) {
            final label = formatMailAddress(p, myHandle: myHandle);
            final host = _hostSlugFromHandle(p, myHandle: myHandle);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _MessageAvatar(label: label, host: host, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle?.copyWith(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Root OP message for the reading-pane header (excluded from the reply list).
ThreadMessageView? _rootOpMessage(ThreadDetailResult detail) {
  final nodes = flattenThreadMessages(detail.messages);
  for (final n in nodes) {
    if (n.depth == 0 && _isOpHandle(n.message.fromHandle, detail.from)) {
      return n.message;
    }
  }
  for (final n in nodes) {
    if (n.depth == 0) return n.message;
  }
  return null;
}

bool _isRootOpNode(ThreadMessageNode node, ThreadDetailResult detail) {
  final op = _rootOpMessage(detail);
  return op != null && node.message.id == op.id;
}

/// OP name + message as header; audience shown as quiet `to @…` meta.
class _ThreadDetailHeader extends StatelessWidget {
  const _ThreadDetailHeader({
    required this.detail,
    this.myHandle,
    this.muted = false,
    this.onRefresh,
    this.onClose,
    this.onDelete,
    this.onMuteToggle,
    this.onReplyOp,
    this.onUpvoteOp,
    this.upvotingOp = false,
  });

  final ThreadDetailResult detail;
  final String? myHandle;
  final bool muted;
  final VoidCallback? onRefresh;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onReplyOp;
  final VoidCallback? onUpvoteOp;
  final bool upvotingOp;

  ThreadStatusKind? get _statusKind =>
      _actionStatus(status: detail.status, yourStatus: detail.yourStatus);

  @override
  Widget build(BuildContext context) {
    final op = _rootOpMessage(detail);
    final opLabel = formatMailAddress(
      op?.fromHandle ?? detail.from,
      myHandle: myHandle,
    );
    final host = _hostSlugFromHandle(
      op?.fromHandle ?? detail.from,
      myHandle: myHandle,
    );
    final audienceLabel = detail.audience.isNotEmpty
        ? formatMailAddress(detail.audience, myHandle: myHandle)
        : null;
    final showTo =
        audienceLabel != null &&
        audienceLabel != opLabel &&
        detail.audience != detail.from;
    final isMyAgentsGroup = detail.audience.trim() == '@all';
    final groupAgents = isMyAgentsGroup
        ? _agentParticipantsFromMessages(detail, myHandle: myHandle)
        : const <String>[];
    final status = _statusKind;
    const iconSize = 44.0;
    final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: MutandeColors.stone400,
      height: 1.15,
      fontSize: 11,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _MessageAvatar(label: opLabel, host: host, size: iconSize),
            const SizedBox(width: 10),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: iconSize),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            opLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: MutandeColors.stone800,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _OpBadge(),
                        if (op != null &&
                            formatClockHm(op.createdAt).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            formatClockHm(op.createdAt),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: MutandeColors.stone400,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ],
                    ),
                    if (showTo || status != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (showTo)
                            Flexible(
                              child: Text(
                                'to $audienceLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                          if (showTo && status != null)
                            const SizedBox(width: 8),
                          if (status != null)
                            ThreadStatusBadge(kind: status, compact: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                color: MutandeColors.stone400,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (onClose != null || onDelete != null || onMuteToggle != null)
              PopupMenuButton<String>(
                tooltip: 'Thread actions',
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'mute') onMuteToggle?.call();
                  if (value == 'close') onClose?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  if (onMuteToggle != null)
                    PopupMenuItem(
                      value: 'mute',
                      child: Text(muted ? 'Unmute' : 'Mute'),
                    ),
                  if (onClose != null)
                    const PopupMenuItem(value: 'close', child: Text('Close')),
                  if (onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: MutandeColors.stone400,
                  ),
                ),
              ),
          ],
        ),
        if (groupAgents.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            groupAgents.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          ),
        ],
        if (op != null) ...[
          const SizedBox(height: 12),
          if (op.displayBody.isNotEmpty) _ReadMoreText(text: op.displayBody),
          if (op.resources.isNotEmpty) ...[
            if (op.displayBody.isNotEmpty) const SizedBox(height: 10),
            MessageAttachments(resources: op.resources),
          ],
          if (onReplyOp != null || onUpvoteOp != null) ...[
            const SizedBox(height: 10),
            _MessageActionGroup(
              count: op.upvotes?.count ?? 0,
              upvoted: op.upvotes?.youUpvoted ?? false,
              upvoting: upvotingOp,
              onUpvote: onUpvoteOp,
              onReply: onReplyOp,
              showUpvote: onUpvoteOp != null || (op.upvotes?.count ?? 0) > 0,
            ),
          ],
        ],
      ],
    );
  }
}

/// Agent slugs that have posted in a my-agents `@all` group (from `from_handle`s).
List<String> _agentParticipantsFromMessages(
  ThreadDetailResult detail, {
  String? myHandle,
}) {
  final seen = <String>{};
  final out = <String>[];
  void addHandle(String handle) {
    if (handle.isEmpty || handle.trim() == '@all') return;
    final label = formatMailAddress(handle, myHandle: myHandle);
    final slash = label.indexOf('/');
    final slug = slash >= 0 && slash < label.length - 1
        ? label.substring(slash + 1)
        : (label.startsWith('@') ? label.substring(1) : label);
    if (slug.isEmpty || !seen.add(slug)) return;
    out.add('@$slug');
  }

  addHandle(detail.from);
  for (final m in detail.messages) {
    addHandle(m.fromHandle);
  }
  return out;
}

class _ReadMoreText extends StatefulWidget {
  const _ReadMoreText({required this.text});

  final String text;
  static const maxLines = 3;

  @override
  State<_ReadMoreText> createState() => _ReadMoreTextState();
}

class _ReadMoreTextState extends State<_ReadMoreText> {
  bool _expanded = false;
  bool _overflows = false;

  @override
  void didUpdateWidget(covariant _ReadMoreText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
      _overflows = false;
    }
  }

  void _measure(double maxWidth, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: _ReadMoreText.maxLines,
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    if (overflows != _overflows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflows = overflows);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.text.trim().isEmpty;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: empty ? MutandeColors.stone400 : MutandeColors.stone800,
      height: 1.5,
      fontStyle: empty ? FontStyle.italic : FontStyle.normal,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!empty) _measure(constraints.maxWidth, style);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              empty ? '(no notes)' : widget.text,
              maxLines: _expanded ? null : _ReadMoreText.maxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: style,
            ),
            if (_overflows) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'Show less' : 'Read more',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: MutandeColors.stone600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: MutandeColors.stone500,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ThreadReplyComposer extends StatefulWidget {
  const _ThreadReplyComposer({
    required this.controller,
    required this.sending,
    required this.closed,
    required this.nested,
    this.replyToHandle,
    required this.onClearTarget,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool closed;
  final bool nested;
  final String? replyToHandle;
  final VoidCallback onClearTarget;
  final VoidCallback onSend;

  @override
  State<_ThreadReplyComposer> createState() => _ThreadReplyComposerState();
}

class _ThreadReplyComposerState extends State<_ThreadReplyComposer> {
  bool _focused = false;
  late bool _hasText = widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant _ThreadReplyComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  void _trySend() {
    if (widget.closed || widget.sending || !_hasText) return;
    widget.onSend();
  }

  String get _hint {
    if (widget.closed) return 'Thread closed';
    if (widget.replyToHandle != null) {
      return 'Reply to ${widget.replyToHandle}…';
    }
    if (widget.nested) return 'Nested reply…';
    return 'Write a reply…';
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.closed && !widget.sending && _hasText;
    final borderColor = _focused
        ? MutandeColors.stone500
        : const Color(0xFFE7E5E4);

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE7E5E4))),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.replyToHandle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.reply,
                    size: 14,
                    color: MutandeColors.stone500,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${widget.replyToHandle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: MutandeColors.stone600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onClearTarget,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: MutandeColors.stone500,
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _trySend,
            },
            child: Focus(
              onFocusChange: (v) => setState(() => _focused = v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 1),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: widget.controller,
                      decoration: InputDecoration(
                        hintText: _hint,
                        hintStyle: TextStyle(
                          color: MutandeColors.stone400,
                          fontSize: 14,
                        ),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: MutandeColors.stone800,
                        height: 1.4,
                      ),
                      minLines: 1,
                      maxLines: 8,
                      maxLength: 12000,
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      enabled: !widget.sending && !widget.closed,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: (_) {},
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (widget.closed)
                          Text(
                            'This thread is closed',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: MutandeColors.stone400),
                          )
                        else if (_focused || _hasText)
                          Text(
                            '⌘↩ to send',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: MutandeColors.stone400),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: canSend ? _trySend : null,
                          style: TextButton.styleFrom(
                            foregroundColor: canSend
                                ? MutandeColors.stone800
                                : MutandeColors.stone400,
                            disabledForegroundColor: MutandeColors.stone400,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(widget.sending ? 'Sending…' : 'Send'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadMessageTile extends StatelessWidget {
  const _ThreadMessageTile({
    super.key,
    required this.node,
    this.myHandle,
    this.opHandle,
    this.onReply,
    this.onUpvote,
    this.upvoting = false,
  });

  final ThreadMessageNode node;
  final String? myHandle;

  /// Thread originator (`detail.from`) — shown as OP when it matches.
  final String? opHandle;
  final VoidCallback? onReply;
  final VoidCallback? onUpvote;
  final bool upvoting;

  @override
  Widget build(BuildContext context) {
    final m = node.message;
    final body = m.displayBody;
    final empty = m.isEmptyBody;
    final hasError = m.openError != null && m.openError!.trim().isNotEmpty;
    // Cap nest indent so deep trees stay readable in the reading pane.
    final depth = node.depth.clamp(0, 5);
    final indent = depth * 18.0;
    final upvotes = m.upvotes;
    final count = upvotes?.count ?? 0;
    final youUpvoted = upvotes?.youUpvoted ?? false;
    final fromLabel = formatMailAddress(m.fromHandle, myHandle: myHandle);
    final host = _hostSlugFromHandle(m.fromHandle, myHandle: myHandle);
    final isOp = _isOpHandle(m.fromHandle, opHandle);
    final time = formatClockHm(m.createdAt);

    // OP gets more air below; nested replies stay denser.
    final bottomGap = depth == 0 ? 20.0 : 14.0;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: bottomGap),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (depth > 0) ...[
              Container(
                width: 2,
                margin: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7E5E4),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _MessageAvatar(label: fromLabel, host: host),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          fromLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: const Color(0xFF292524),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (isOp) ...[const SizedBox(width: 8), const _OpBadge()],
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: MutandeColors.stone400,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (body.isNotEmpty || empty)
                    SelectableText(
                      empty && m.resources.isEmpty ? 'No message body' : body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: hasError
                            ? const Color(0xFF991B1B)
                            : empty
                            ? const Color(0xFFA8A29E)
                            : const Color(0xFF1C1917),
                        height: 1.5,
                        fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  if (m.resources.isNotEmpty) ...[
                    if (body.isNotEmpty || empty) const SizedBox(height: 10),
                    MessageAttachments(resources: m.resources),
                  ],
                  if (onUpvote != null || count > 0 || onReply != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _MessageActionGroup(
                          count: count,
                          upvoted: youUpvoted,
                          upvoting: upvoting,
                          onUpvote: onUpvote,
                          onReply: onReply,
                          showUpvote: onUpvote != null || count > 0,
                        ),
                        if (upvotes != null && upvotes.upvotes.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final vote in upvotes.upvotes.take(8))
                                  _AgentVoteChip(
                                    label: formatMailAddress(
                                      vote.fromHandle,
                                      myHandle: myHandle,
                                    ),
                                  ),
                                if (upvotes.upvotes.length > 8)
                                  _AgentVoteChip(
                                    label: '+${upvotes.upvotes.length - 8}',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// True when [from] is the thread originator (exact or same agent address).
bool _isOpHandle(String from, String? op) {
  if (op == null || op.isEmpty) return false;
  if (from == op) return true;
  // Same handle/agent path after display normalization noise.
  return from.toLowerCase() == op.toLowerCase();
}

class _OpBadge extends StatelessWidget {
  const _OpBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'OP',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF1D4ED8),
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

String? _hostSlugFromHandle(String handle, {String? myHandle}) {
  final formatted = formatMailAddress(handle, myHandle: myHandle);
  if (formatted.startsWith('@') && !formatted.substring(1).contains('@')) {
    final slug = formatted.substring(1).toLowerCase();
    if (AiHostIcon.assetFor(slug) != null) return slug;
  }
  final slash = handle.indexOf('/');
  if (slash >= 0 && slash < handle.length - 1) {
    final slug = handle.substring(slash + 1).toLowerCase();
    if (AiHostIcon.assetFor(slug) != null) return slug;
  }
  return null;
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({required this.label, this.host, this.size = 26});

  final String label;
  final String? host;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (host != null) {
      return AiHostIcon(host!, size: size, showPlate: true);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Text(
        _initialsFor(label),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF78716C),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

class _MessageActionGroup extends StatelessWidget {
  const _MessageActionGroup({
    required this.count,
    required this.upvoted,
    required this.upvoting,
    required this.showUpvote,
    this.onUpvote,
    this.onReply,
  });

  final int count;
  final bool upvoted;
  final bool upvoting;
  final bool showUpvote;
  final VoidCallback? onUpvote;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final showReply = onReply != null;
    if (!showUpvote && !showReply) return const SizedBox.shrink();

    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE7E5E4)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showUpvote) ...[
            _ActionIconCell(
              icon: upvoted ? Icons.arrow_upward : Icons.arrow_upward_outlined,
              label: count > 0 ? '$count' : null,
              active: upvoted,
              tooltip: 'Upvote',
              enabled: !upvoting && onUpvote != null,
              onTap: onUpvote,
              roundedLeft: true,
            ),
            if (showReply)
              Container(width: 1, height: 18, color: const Color(0xFFE7E5E4)),
          ],
          if (showReply)
            _ActionIconCell(
              icon: Icons.reply_outlined,
              tooltip: 'Reply',
              onTap: onReply,
              roundedRight: true,
              roundedLeft: !showUpvote,
            ),
        ],
      ),
    );
  }
}

class _ActionIconCell extends StatelessWidget {
  const _ActionIconCell({
    required this.icon,
    required this.tooltip,
    this.label,
    this.active = false,
    this.enabled = true,
    this.onTap,
    this.roundedLeft = false,
    this.roundedRight = false,
  });

  final IconData icon;
  final String tooltip;
  final String? label;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;
  final bool roundedLeft;
  final bool roundedRight;

  @override
  Widget build(BuildContext context) {
    final fg = active ? const Color(0xFF292524) : const Color(0xFF78716C);
    final bg = active ? const Color(0xFFF5F5F4) : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.horizontal(
          left: roundedLeft ? const Radius.circular(7) : Radius.zero,
          right: roundedRight ? const Radius.circular(7) : Radius.zero,
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.horizontal(
            left: roundedLeft ? const Radius.circular(7) : Radius.zero,
            right: roundedRight ? const Radius.circular(7) : Radius.zero,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 10 : 9,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: enabled ? fg : const Color(0xFFA8A29E),
                ),
                if (label != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    label!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: enabled ? fg : const Color(0xFFA8A29E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentVoteChip extends StatelessWidget {
  const _AgentVoteChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF57534E),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
