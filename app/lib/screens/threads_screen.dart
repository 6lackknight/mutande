import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thread_message_tree.dart';
import 'threads_spatial_view.dart';

/// Stitch home threads — filters, list rows, search + new thread footer.
class ThreadsPanel extends StatefulWidget {
  const ThreadsPanel({
    super.key,
    required this.daemon,
    this.onReloadReady,
    this.myHandle,
    this.composeRecipient,
    this.onComposeRecipientHandled,
  });

  final DaemonClient daemon;
  final ValueChanged<VoidCallback?>? onReloadReady;
  /// Current user handle (`alice@acme`) for self-shorthand display.
  final String? myHandle;
  /// When set, opens compose addressed to this handle.
  final String? composeRecipient;
  final VoidCallback? onComposeRecipientHandled;

  @override
  State<ThreadsPanel> createState() => _ThreadsPanelState();
}

class _ThreadsPanelState extends State<ThreadsPanel> {
  String _filter = 'needs_action';
  bool _spatial = false;
  bool _loading = true;
  String? _error;
  List<ThreadSummary> _threads = const [];
  AgentListResult? _agents;
  String? _openId;
  bool _composeOpen = false;
  String? _composePrefillRecipient;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.onReloadReady?.call(_reload);
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
      final threads = await widget.daemon.listThreads(filter: _filter);
      AgentListResult? agents;
      if (_spatial) {
        try {
          agents = await widget.daemon.listAgents();
        } catch (_) {
          agents = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _agents = agents;
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

  List<ThreadSummary> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _threads;
    return _threads
        .where(
          (t) =>
              t.from.toLowerCase().contains(q) ||
              t.audience.toLowerCase().contains(q) ||
              t.kind.toLowerCase().contains(q) ||
              (t.agentBadge?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_openId != null) {
      return ThreadDetailPanel(
        daemon: widget.daemon,
        threadId: _openId!,
        myHandle: widget.myHandle,
        onBack: () {
          setState(() => _openId = null);
          _reload();
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThreadsToolbar(
          filter: _filter,
          spatial: _spatial,
          query: _query,
          onFilterChanged: (v) {
            setState(() => _filter = v);
            _reload();
          },
          onSpatialChanged: (v) {
            setState(() => _spatial = v);
            _reload();
          },
          onQueryChanged: (v) => setState(() => _query = v),
        ),
        if (_composeOpen) ...[
          const SizedBox(height: 8),
          _ComposePanel(
            daemon: widget.daemon,
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
        Expanded(
          child: _loading
              ? const Center(
                  child: MutandeOrb.standard(
                    semanticLabel: 'Loading threads…',
                  ),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF57534E),
                                    height: 1.35,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton(
                              onPressed: _reload,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _visible.isEmpty && !_spatial
                      ? Center(
                          child: Text(
                            'No threads.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF78716C)),
                          ),
                        )
                      : _spatial
                          ? ThreadsSpatialView(
                              threads: _visible,
                              agents: _agents,
                              myHandle: widget.myHandle,
                              onOpenThread: (id) =>
                                  setState(() => _openId = id),
                            )
                          : Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 720),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: _visible.length,
                                  separatorBuilder: (_, _) => const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Color(0xFFE7E5E4),
                                  ),
                                  itemBuilder: (context, i) {
                                    final t = _visible[i];
                                    return _ThreadRow(
                                      thread: t,
                                      myHandle: widget.myHandle,
                                      onTap: () =>
                                          setState(() => _openId = t.id),
                                    );
                                  },
                                ),
                              ),
                            ),
        ),
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _ThreadsFooter(
              onNewThread: () => setState(() => _composeOpen = true),
            ),
          ),
        ),
      ],
    );
  }
}

/// Search-first toolbar: query field with filter scope + view menu.
class _ThreadsToolbar extends StatefulWidget {
  const _ThreadsToolbar({
    required this.filter,
    required this.spatial,
    required this.query,
    required this.onFilterChanged,
    required this.onSpatialChanged,
    required this.onQueryChanged,
  });

  final String filter;
  final bool spatial;
  final String query;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<bool> onSpatialChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  State<_ThreadsToolbar> createState() => _ThreadsToolbarState();
}

class _ThreadsToolbarState extends State<_ThreadsToolbar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant _ThreadsToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
      _controller.selection =
          TextSelection.collapsed(offset: widget.query.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _filterLabel => switch (widget.filter) {
        'open' => 'Open',
        'closed' => 'Closed',
        _ => 'Needs you',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAF9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE7E5E4)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, size: 18, color: Color(0xFFA8A29E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: widget.onQueryChanged,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF292524),
                          ),
                      decoration: const InputDecoration(
                        hintText: 'Search threads…',
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 22,
                    color: const Color(0xFFE7E5E4),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Filter scope',
                    onSelected: widget.onFilterChanged,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'needs_action',
                        child: Text('Needs you'),
                      ),
                      PopupMenuItem(value: 'open', child: Text('Open')),
                      PopupMenuItem(value: 'closed', child: Text('Closed')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _filterLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: const Color(0xFF57534E),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: Color(0xFF78716C),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<bool>(
            tooltip: 'View',
            onSelected: widget.onSpatialChanged,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: false,
                checked: !widget.spatial,
                child: const Text('List'),
              ),
              CheckedPopupMenuItem(
                value: true,
                checked: widget.spatial,
                child: const Text('Spatial'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.spatial
                        ? Icons.hub_outlined
                        : Icons.view_agenda_outlined,
                    size: 18,
                    color: const Color(0xFF78716C),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.spatial ? 'Spatial' : 'List',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF78716C),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: Color(0xFFA8A29E),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadsFooter extends StatelessWidget {
  const _ThreadsFooter({required this.onNewThread});

  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(
          height: 1,
          thickness: 1,
          color: Color(0xFFE7E5E4),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onNewThread,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Thread'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF57534E),
                side: const BorderSide(color: Color(0xFFD6D3D1)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.onTap,
    this.myHandle,
  });

  final ThreadSummary thread;
  final VoidCallback onTap;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final title = _rowTitle(thread, myHandle: myHandle);
    final meta = _rowMeta(thread);
    final status = _quietStatus(thread);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                        ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF78716C),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: thread.yourStatus == 'pending'
                          ? const Color(0xFFB45309)
                          : const Color(0xFFA8A29E),
                      fontWeight: thread.yourStatus == 'pending'
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
              ),
            ],
          ],
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
    final pending = thread.yourStatus == 'pending';
    final plate = pending
        ? const Color(0xFFFDE68A).withValues(alpha: 0.35)
        : const Color(0xFFF5F5F4);
    final border = pending
        ? const Color(0xFFFDE68A).withValues(alpha: 0.6)
        : const Color(0xFFE7E5E4);

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

/// Quiet status for the right column — no shouty chips.
String _quietStatus(ThreadSummary t) {
  if (t.yourStatus == 'pending') return 'needs you';
  if (t.status == 'closed') return 'closed';
  if (t.yourStatus == 'replied') return 'waiting';
  return 'open';
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
    this.initialRecipient,
    required this.onSent,
    required this.onCancel,
  });

  final DaemonClient daemon;
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

    // Self-collaboration shorthand: @cursor, @claude, @all, …
    if (trimmed.isEmpty || trimmed.startsWith('@')) {
      try {
        final list = await widget.daemon.listAgents();
        final suggestions = <String>[
          '@all',
          ...list.agents.map((a) => '@${a.slug}'),
        ];
        if (trimmed.isEmpty || lower == '@') return suggestions;
        return suggestions.where((s) => s.startsWith(lower)).toList();
      } catch (_) {
        if (trimmed.isEmpty || lower.startsWith('@')) {
          return const ['@all'];
        }
      }
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
  });

  final DaemonClient daemon;
  final String threadId;
  final VoidCallback onBack;
  final String? myHandle;

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
        SnackBar(content: Text('Could not update upvote: $e')),
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
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.daemon.replyToThread(
        threadId: widget.threadId,
        notes: text,
        inReplyTo: _replyToMessageId,
      );
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: const Text('← Threads'),
            ),
            const Spacer(),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
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
          Text(
            _error ?? 'Thread unavailable',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF991B1B),
                ),
          )
        else ...[
          Text(
            formatMailAddress(
              _detail!.audience.isNotEmpty &&
                      _detail!.audience != _detail!.from
                  ? _detail!.audience
                  : _detail!.from,
              myHandle: widget.myHandle,
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF292524),
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            [
              if (_detail!.audience.isNotEmpty &&
                  _detail!.audience != _detail!.from)
                'from ${formatMailAddress(_detail!.from, myHandle: widget.myHandle)}',
              _detail!.kind,
              _detail!.status,
              if (_detail!.yourStatus != null) _detail!.yourStatus!,
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF78716C),
                ),
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
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final node in flattenThreadMessages(_detail!.messages))
                  _ThreadMessageTile(
                    node: node,
                    myHandle: widget.myHandle,
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
          if (_replyToHandle != null) ...[
            const SizedBox(height: 8),
            Material(
              color: const Color(0xFFF5F5F4),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to ${formatMailAddress(_replyToHandle!, myHandle: widget.myHandle)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF57534E),
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: _clearReplyTarget,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          TextField(
            controller: _reply,
            decoration: InputDecoration(
              labelText: _replyToMessageId == null ? 'Reply' : 'Nested reply',
              hintText: 'Short note for their agent',
            ),
            minLines: 2,
            maxLines: 4,
            enabled: !_sending && _detail!.status != 'closed',
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed:
                _sending || _detail!.status == 'closed' ? null : _sendReply,
            child: Text(_sending ? 'Sending…' : 'Send reply'),
          ),
        ],
      ],
    );
  }
}

class _ThreadMessageTile extends StatelessWidget {
  const _ThreadMessageTile({
    required this.node,
    this.myHandle,
    this.onReply,
    this.onUpvote,
    this.upvoting = false,
  });

  final ThreadMessageNode node;
  final String? myHandle;
  final VoidCallback? onReply;
  final VoidCallback? onUpvote;
  final bool upvoting;

  @override
  Widget build(BuildContext context) {
    final m = node.message;
    final body = m.displayBody;
    final indent = 12.0 + (node.depth * 20.0);
    final upvotes = m.upvotes;
    final count = upvotes?.count ?? 0;
    final youUpvoted = upvotes?.youUpvoted ?? false;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 12, right: 4),
      child: DecoratedBox(
        decoration: node.depth > 0
            ? const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFE7E5E4), width: 2),
                ),
              )
            : const BoxDecoration(),
        child: Padding(
          padding: EdgeInsets.only(left: node.depth > 0 ? 10 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatMailAddress(m.fromHandle, myHandle: myHandle),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF78716C),
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: m.openError != null
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF292524),
                    ),
              ),
              if (onUpvote != null || count > 0) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (onUpvote != null)
                      TextButton.icon(
                        onPressed: upvoting ? null : onUpvote,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          minimumSize: const Size(44, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: youUpvoted
                              ? const Color(0xFF44403C)
                              : const Color(0xFF78716C),
                        ),
                        icon: Icon(
                          youUpvoted
                              ? Icons.arrow_upward
                              : Icons.arrow_upward_outlined,
                          size: 16,
                        ),
                        label: Text(count > 0 ? '$count' : 'Upvote'),
                      )
                    else if (count > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$count',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF78716C),
                                  ),
                        ),
                      ),
                    if (upvotes != null && upvotes.upvotes.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final vote in upvotes.upvotes)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F4),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  formatMailAddress(
                                    vote.fromHandle,
                                    myHandle: myHandle,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: const Color(0xFF57534E),
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (onReply != null) ...[
                const SizedBox(height: 2),
                TextButton(
                  onPressed: onReply,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reply'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
