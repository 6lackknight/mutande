import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../widgets/thinking_orb.dart';
import 'threads_spatial_view.dart';

/// Stitch home threads — filters, list rows, search + new thread footer.
class ThreadsPanel extends StatefulWidget {
  const ThreadsPanel({
    super.key,
    required this.daemon,
    this.onReloadReady,
  });

  final DaemonClient daemon;
  final ValueChanged<VoidCallback?>? onReloadReady;

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
        onBack: () {
          setState(() => _openId = null);
          _reload();
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(
          filter: _filter,
          spatial: _spatial,
          onSpatialChanged: (v) {
            setState(() => _spatial = v);
            _reload();
          },
          onChanged: (v) {
            setState(() => _filter = v);
            _reload();
          },
        ),
        if (_composeOpen) ...[
          const SizedBox(height: 8),
          _ComposePanel(
            daemon: widget.daemon,
            onSent: () {
              setState(() => _composeOpen = false);
              _reload();
            },
            onCancel: () => setState(() => _composeOpen = false),
          ),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: MutandeOrb.standard())
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
                              onOpenThread: (id) =>
                                  setState(() => _openId = id),
                            )
                          : ListView.separated(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
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
                              onTap: () => setState(() => _openId = t.id),
                            );
                          },
                        ),
        ),
        _ThreadsFooter(
          query: _query,
          onQueryChanged: (v) => setState(() => _query = v),
          onNewThread: () => setState(() => _composeOpen = true),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.spatial,
    required this.onSpatialChanged,
    required this.onChanged,
  });

  final String filter;
  final bool spatial;
  final ValueChanged<bool> onSpatialChanged;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String value, String label) {
      final selected = filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? const Color(0xFFE7E5E4) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => onChanged(value),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? const Color(0xFF292524)
                          : const Color(0xFF78716C),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    Widget viewChip(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE7E5E4) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected
                      ? const Color(0xFF292524)
                      : const Color(0xFF78716C),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill('needs_action', 'Needs you'),
        pill('open', 'Open'),
        pill('closed', 'Closed'),
        const Spacer(),
        viewChip('List', !spatial, () => onSpatialChanged(false)),
        const SizedBox(width: 4),
        viewChip('Spatial', spatial, () => onSpatialChanged(true)),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.onTap});

  final ThreadSummary thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = _badgeFor(thread);
    // Self-collab: list by target agent (audience). Otherwise show sender.
    final title = _selfCollabTitle(thread) ?? thread.from;
    final snippet = [
      if (_selfCollabTitle(thread) != null) 'from ${thread.from}',
      if (thread.agentBadge != null) '/${thread.agentBadge}',
      thread.kind,
      if (thread.replyCount > 0) '${thread.replyCount} replies',
    ].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(kind: thread.kind, pending: thread.yourStatus == 'pending'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF292524),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snippet.isEmpty ? 'Thread' : snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF78716C),
                        ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _StatusBadge(badge: badge),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          badge.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: const Color(0xFFA8A29E),
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.kind, required this.pending});

  final String kind;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final broadcast = kind == 'broadcast';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: pending
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        broadcast ? Icons.account_tree_outlined : Icons.person_outline,
        size: 18,
        color: pending
            ? const Color(0xFFB45309)
            : const Color(0xFF57534E),
      ),
    );
  }
}

class _BadgeInfo {
  const _BadgeInfo({
    required this.label,
    required this.detail,
    required this.dot,
    required this.bg,
    required this.fg,
  });

  final String label;
  final String detail;
  final Color dot;
  final Color bg;
  final Color fg;
}

/// Same-user agent handoff: title the row by audience (target agent).
String? _selfCollabTitle(ThreadSummary t) {
  final fromBare = t.from.split('/').first;
  final audBare = t.audience.split('/').first;
  if (fromBare.isEmpty || audBare.isEmpty || fromBare != audBare) return null;
  if (t.audience == t.from) return null;
  return t.audience;
}

_BadgeInfo _badgeFor(ThreadSummary t) {
  if (t.yourStatus == 'pending') {
    return const _BadgeInfo(
      label: 'ACTION REQUIRED',
      detail: 'Awaiting your response',
      dot: Color(0xFFB45309),
      bg: Color(0xFFFEF3C7),
      fg: Color(0xFF92400E),
    );
  }
  if (t.status == 'closed') {
    return const _BadgeInfo(
      label: 'CLOSED',
      detail: 'Resolved',
      dot: Color(0xFF78716C),
      bg: Color(0xFFF5F5F4),
      fg: Color(0xFF57534E),
    );
  }
  if (t.yourStatus == 'replied') {
    return const _BadgeInfo(
      label: 'PENDING',
      detail: 'Waiting on them',
      dot: Color(0xFFD97706),
      bg: Color(0xFFFFFBEB),
      fg: Color(0xFFB45309),
    );
  }
  return const _BadgeInfo(
    label: 'OPEN',
    detail: 'Active thread',
    dot: Color(0xFF166534),
    bg: Color(0xFFECFDF5),
    fg: Color(0xFF166534),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.badge});

  final _BadgeInfo badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badge.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: badge.dot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            badge.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badge.fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _ThreadsFooter extends StatelessWidget {
  const _ThreadsFooter({
    required this.query,
    required this.onQueryChanged,
    required this.onNewThread,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search threads…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: const Color(0xFFFAFAF9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onNewThread,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Thread'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF92400E),
              side: const BorderSide(color: Color(0xFF92400E)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposePanel extends StatefulWidget {
  const _ComposePanel({
    required this.daemon,
    required this.onSent,
    required this.onCancel,
  });

  final DaemonClient daemon;
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
  });

  final DaemonClient daemon;
  final String threadId;
  final VoidCallback onBack;

  @override
  State<ThreadDetailPanel> createState() => _ThreadDetailPanelState();
}

class _ThreadDetailPanelState extends State<ThreadDetailPanel> {
  bool _loading = true;
  String? _error;
  ThreadDetailResult? _detail;
  final _reply = TextEditingController();
  bool _sending = false;

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
      );
      _reply.clear();
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
            child: Center(child: MutandeOrb.standard()),
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
            _detail!.audience.isNotEmpty &&
                    _detail!.audience != _detail!.from
                ? _detail!.audience
                : _detail!.from,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF292524),
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            [
              if (_detail!.audience.isNotEmpty &&
                  _detail!.audience != _detail!.from)
                'from ${_detail!.from}',
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
                ..._detail!.messages.map((m) {
                  final body = m.displayBody;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.fromHandle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF78716C),
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        Text(
                          body,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: m.openError != null
                                        ? const Color(0xFF991B1B)
                                        : const Color(0xFF292524),
                                  ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          TextField(
            controller: _reply,
            decoration: const InputDecoration(
              labelText: 'Reply',
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
