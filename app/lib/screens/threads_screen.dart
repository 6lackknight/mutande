import 'package:flutter/material.dart';
import 'package:flutter_resizable_container/flutter_resizable_container.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thread_message_tree.dart';
import '../widgets/thread_status_badge.dart';

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
  const ThreadsPanel({
    super.key,
    required this.daemon,
    this.onReloadReady,
    this.myHandle,
    this.composeRecipient,
    this.onComposeRecipientHandled,
    this.initialThreadId,
    this.onInitialThreadHandled,
  });

  final DaemonClient daemon;
  final ValueChanged<VoidCallback?>? onReloadReady;
  /// Current user handle (`alice@acme`) for self-shorthand display.
  final String? myHandle;
  /// When set, opens compose addressed to this handle.
  final String? composeRecipient;
  final VoidCallback? onComposeRecipientHandled;
  /// When set, opens this thread (e.g. after first-run ping).
  final String? initialThreadId;
  final VoidCallback? onInitialThreadHandled;

  @override
  State<ThreadsPanel> createState() => _ThreadsPanelState();
}

class _ThreadsPanelState extends State<ThreadsPanel> {
  String _filter = 'all';
  bool _loading = true;
  String? _error;
  List<ThreadSummary> _threads = const [];
  String? _openId;
  bool _composeOpen = false;
  String? _composePrefillRecipient;
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
    _reload();
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
    widget.onReloadReady?.call(null);
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final threads = await widget.daemon.listThreads(
        filter: _filter == 'all' ? null : _filter,
      );
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyDaemonError(e, what: 'Threads');
        _loading = false;
      });
    }
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
      if (_openId == threadId) setState(() => _openId = null);
      await _reload();
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
      if (_openId == threadId) setState(() => _openId = null);
      await _reload();
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
              setState(() => _filter = v);
              _reload();
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
                _reload();
              },
              onCancel: () => setState(() {
                _composeOpen = false;
                _composePrefillRecipient = null;
              }),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(child: _buildListPane(context)),
          const SizedBox(height: 8),
          _ThreadsFooter(
            onNewThread: () => setState(() => _composeOpen = true),
          ),
        ],
      ),
    );

    final reading = _openId == null
        ? const _EmptyReadingPane()
        : ThreadDetailPanel(
            daemon: widget.daemon,
            threadId: _openId!,
            myHandle: widget.myHandle,
            embedded: true,
            onBack: () {
              setState(() => _openId = null);
              _reload();
            },
            onListChanged: _reload,
            onGone: () {
              setState(() => _openId = null);
              _reload();
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
        ResizableChild(
          size: const ResizableSize.expand(),
          child: reading,
        ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF57534E),
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_visible.isEmpty) {
      return Center(
        child: Text(
          'No threads.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: const Color(0xFF78716C)),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _visible.length,
      itemBuilder: (context, i) {
        final t = _visible[i];
        return _ThreadRow(
          thread: t,
          myHandle: widget.myHandle,
          selected: t.id == _openId,
          onTap: () => setState(() => _openId = t.id),
          onClose: t.status == 'closed'
              ? null
              : () => _closeThreadFromList(t.id),
          onDelete: () => _deleteThreadFromList(t.id),
        );
      },
    );
  }
}

class _EmptyReadingPane extends StatelessWidget {
  const _EmptyReadingPane();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select a thread',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF57534E),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Replies stay nested on the right — list never leaves.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA8A29E),
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inbox filter scope (search lives on the home chrome strip).
class _ThreadsToolbar extends StatelessWidget {
  const _ThreadsToolbar({
    required this.filter,
    required this.onFilterChanged,
  });

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
          PopupMenuItem(
            value: 'needs_action',
            child: Text('Needs you'),
          ),
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
              const Icon(
                Icons.expand_more,
                size: 16,
                color: Color(0xFFA8A29E),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadsFooter extends StatelessWidget {
  const _ThreadsFooter({required this.onNewThread});

  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onNewThread,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('New'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF57534E),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.onTap,
    this.myHandle,
    this.selected = false,
    this.onClose,
    this.onDelete,
  });

  final ThreadSummary thread;
  final VoidCallback onTap;
  final String? myHandle;
  final bool selected;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final title = _rowTitle(thread, myHandle: myHandle);
    final meta = _rowMeta(thread);
    final status = _rowStatus(thread);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0xFFF5F5F4) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (details) {
            final items = <PopupMenuEntry<String>>[
              if (onClose != null)
                const PopupMenuItem(value: 'close', child: Text('Close')),
              if (onDelete != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
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
              if (value == 'close') onClose?.call();
              if (value == 'delete') onDelete?.call();
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF292524),
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFA8A29E),
                                    height: 1.2,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ThreadStatusBadge(kind: status, compact: true),
              ],
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
  return ThreadStatusKindX.resolve(
    status: t.status,
    yourStatus: t.yourStatus,
  );
}

/// Header/stats: only surface when it changes what you should do.
ThreadStatusKind? _actionStatus({
  required String status,
  String? yourStatus,
}) {
  final resolved = ThreadStatusKindX.resolve(
    status: status,
    yourStatus: yourStatus,
  );
  if (resolved == ThreadStatusKind.open) return null;
  return resolved;
}

String _rowTitle(ThreadSummary t, {String? myHandle}) {
  final self = _selfCollabTitle(t);
  return formatMailAddress(self ?? t.from, myHandle: myHandle);
}

/// One meta line: `via cursor · 2 replies` — no kind / from /default noise.
String _rowMeta(ThreadSummary t) {
  final parts = <String>[];
  final via = _agentSlug(t.agentBadge);
  if (via != null) parts.add('via $via');
  if (t.replyCount > 0) {
    parts.add(t.replyCount == 1 ? '1 reply' : '${t.replyCount} replies');
  }
  return parts.join(' · ');
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

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<List<String>> _recipientOptions(String input) async {
    final trimmed = input.trim();
    final lower = trimmed.toLowerCase();
    final orgAll = _orgBroadcastFromHandle(widget.myHandle);

    // Self-collaboration shorthand: @cursor, @claude, @all —
    // not @all@org (second @ means org broadcast / handle path below).
    final selfShorthand = trimmed.isEmpty ||
        (trimmed.startsWith('@') && !trimmed.substring(1).contains('@'));
    if (selfShorthand) {
      try {
        final list = await widget.daemon.listAgents();
        final suggestions = <String>[
          '@all',
          if (orgAll != null) orgAll,
          ...list.agents.map((a) => '@${a.slug}'),
        ];
        if (trimmed.isEmpty || lower == '@') return suggestions;
        return suggestions.where((s) => s.startsWith(lower)).toList();
      } catch (_) {
        if (trimmed.isEmpty || lower.startsWith('@')) {
          return [
            '@all',
            if (orgAll != null) orgAll,
          ];
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
      return [bare, ...list.agents.map((a) => '$bare/${a.slug}')];
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
    return '@all@$org';
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
    return base;
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
            onSelected: (value) => _recipientController?.text = value,
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
                onSubmitted: (_) => onSubmit(),
              );
            },
          ),
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
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF991B1B),
                  ),
            ),
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
    this.onGone,
  });

  final DaemonClient daemon;
  final String threadId;
  final VoidCallback onBack;
  final String? myHandle;
  /// Side-panel mode: close control instead of full-page back chrome.
  final bool embedded;
  /// Refresh the thread list (e.g. after close) without clearing selection.
  final VoidCallback? onListChanged;
  /// Clear selection + reload after delete.
  final VoidCallback? onGone;

  @override
  State<ThreadDetailPanel> createState() => _ThreadDetailPanelState();
}

class _ThreadDetailPanelState extends State<ThreadDetailPanel> {
  bool _loading = true;
  String? _error;
  ThreadDetailResult? _detail;
  final _reply = TextEditingController();
  bool _sending = false;
  String? _replyToMessageId;
  String? _replyToHandle;
  String? _upvotingMessageId;
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
          messages: _detail!.messages
              .map((m) =>
                  m.id == message.id ? m.copyWithUpvotes(summary) : m)
              .toList(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyDaemonError(e, what: 'Upvote'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _upvotingMessageId = null);
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.daemon.getThread(widget.threadId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyDaemonError(e, what: 'This thread');
        _loading = false;
      });
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
      await _load();
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
      await _load();
      widget.onListChanged?.call();
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
                    if (value == 'close') _closeThread();
                    if (value == 'delete') _deleteThread();
                  },
                  itemBuilder: (context) => [
                    if (_detail!.status != 'closed')
                      const PopupMenuItem(
                        value: 'close',
                        child: Text('Close'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
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
            child: Center(
              child: Text(
                _error ?? 'Thread unavailable',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF991B1B),
                    ),
              ),
            ),
          )
        else ...[
          _ThreadDetailHeader(
            detail: _detail!,
            myHandle: widget.myHandle,
            onRefresh: widget.embedded && !_loading ? _load : null,
            onClose: _detail!.status == 'closed' ? null : _closeThread,
            onDelete: _deleteThread,
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
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF991B1B),
                  ),
            ),
          ],
          const SizedBox(height: 28),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final node in flattenThreadMessages(_detail!.messages))
                  if (!_isRootOpNode(node, _detail!))
                    _ThreadMessageTile(
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
          size: const ResizableSize.pixels(240, min: 180, max: 360),
          child: _ThreadStatsPanel(
            detail: _detail!,
            myHandle: widget.myHandle,
          ),
        ),
      ],
    );
  }
}

class _ThreadStatsPanel extends StatelessWidget {
  const _ThreadStatsPanel({
    required this.detail,
    this.myHandle,
  });

  final ThreadDetailResult detail;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final participants = <String>{};
    for (final m in detail.messages) {
      if (m.fromHandle.isNotEmpty) participants.add(m.fromHandle);
    }
    if (detail.from.isNotEmpty) participants.add(detail.from);
    if (detail.audience.isNotEmpty) participants.add(detail.audience);

    var upvoteTotal = 0;
    for (final m in detail.messages) {
      upvoteTotal += m.upvotes?.count ?? 0;
    }

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: MutandeColors.stone500,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: MutandeColors.stone800,
          height: 1.35,
        );

    Widget row(String label, Widget value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: labelStyle),
            const SizedBox(height: 6),
            value,
          ],
        ),
      );
    }

    Widget textValue(String value) => Text(value, style: valueStyle);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MutandeColors.stone50,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          Text(
            'Thread',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: MutandeColors.stone800,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          row(
            'Status',
            ThreadStatusBadge(
              kind: ThreadStatusKindX.resolve(
                status: detail.status,
                yourStatus: detail.yourStatus,
              ),
            ),
          ),
          row('Kind', textValue(detail.kind.isEmpty ? '—' : detail.kind)),
          row(
            'From',
            textValue(formatMailAddress(detail.from, myHandle: myHandle)),
          ),
          if (detail.audience.isNotEmpty && detail.audience != detail.from)
            row(
              'Audience',
              textValue(
                formatMailAddress(detail.audience, myHandle: myHandle),
              ),
            ),
          row('Messages', textValue('${detail.messages.length}')),
          row('Upvotes', textValue('$upvoteTotal')),
          const SizedBox(height: 4),
          Text('PARTICIPANTS', style: labelStyle),
          const SizedBox(height: 8),
          ...participants.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                formatMailAddress(p, myHandle: myHandle),
                style: valueStyle,
              ),
            ),
          ),
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
    this.onRefresh,
    this.onClose,
    this.onDelete,
    this.onReplyOp,
    this.onUpvoteOp,
    this.upvotingOp = false,
  });

  final ThreadDetailResult detail;
  final String? myHandle;
  final VoidCallback? onRefresh;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onReplyOp;
  final VoidCallback? onUpvoteOp;
  final bool upvotingOp;

  ThreadStatusKind? get _statusKind => _actionStatus(
        status: detail.status,
        yourStatus: detail.yourStatus,
      );

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
    final showTo = audienceLabel != null &&
        audienceLabel != opLabel &&
        detail.audience != detail.from;
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
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: MutandeColors.stone800,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _OpBadge(),
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
            if (onClose != null || onDelete != null)
              PopupMenuButton<String>(
                tooltip: 'Thread actions',
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'close') onClose?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  if (onClose != null)
                    const PopupMenuItem(value: 'close', child: Text('Close')),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
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
        if (op != null) ...[
          const SizedBox(height: 12),
          _ReadMoreText(text: op.displayBody),
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
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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

class _ThreadReplyComposer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE7E5E4))),
      ),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (replyToHandle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: const Color(0xFFF5F5F4),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 14, color: Color(0xFF78716C)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to $replyToHandle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF57534E),
                                  ),
                        ),
                      ),
                      TextButton(
                        onPressed: onClearTarget,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE7E5E4)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: closed
                    ? 'Thread closed'
                    : nested
                        ? 'Nested reply…'
                        : 'Reply to thread…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              minLines: 2,
              maxLines: 8,
              maxLength: 12000,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) =>
                  null,
              enabled: !sending && !closed,
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (closed)
                Text(
                  'This thread is closed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA8A29E),
                      ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: sending || closed ? null : onSend,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF292524),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(sending ? 'Sending…' : 'Send reply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThreadMessageTile extends StatelessWidget {
  const _ThreadMessageTile({
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
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: const Color(0xFF292524),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      if (isOp) ...[
                        const SizedBox(width: 8),
                        const _OpBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: hasError
                              ? const Color(0xFF991B1B)
                              : empty
                                  ? const Color(0xFFA8A29E)
                                  : const Color(0xFF1C1917),
                          height: 1.5,
                          fontStyle:
                              empty ? FontStyle.italic : FontStyle.normal,
                        ),
                  ),
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
                        if (upvotes != null &&
                            upvotes.upvotes.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final vote
                                    in upvotes.upvotes.take(8))
                                  _AgentVoteChip(
                                    label: formatMailAddress(
                                      vote.fromHandle,
                                      myHandle: myHandle,
                                    ),
                                  ),
                                if (upvotes.upvotes.length > 8)
                                  _AgentVoteChip(
                                    label:
                                        '+${upvotes.upvotes.length - 8}',
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
  const _MessageAvatar({
    required this.label,
    this.host,
    this.size = 26,
  });

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
              Container(
                width: 1,
                height: 18,
                color: const Color(0xFFE7E5E4),
              ),
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
                Icon(icon, size: 16, color: enabled ? fg : const Color(0xFFA8A29E)),
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
