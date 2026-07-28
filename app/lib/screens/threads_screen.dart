import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../widgets/thinking_orb.dart';

/// Compact thread list + detail/reply — flows over pixels, no dashboard clutter.
class ThreadsPanel extends StatefulWidget {
  const ThreadsPanel({super.key, required this.daemon});

  final DaemonClient daemon;

  @override
  State<ThreadsPanel> createState() => _ThreadsPanelState();
}

class _ThreadsPanelState extends State<ThreadsPanel> {
  String _filter = 'needs_action';
  bool _loading = true;
  String? _error;
  List<ThreadSummary> _threads = const [];
  String? _openId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final threads = await widget.daemon.listThreads(filter: _filter);
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
        Row(
          children: [
            Text(
              'Threads',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF292524),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            DropdownButton<String>(
              value: _filter,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'needs_action', child: Text('Needs you')),
                DropdownMenuItem(value: 'open', child: Text('Open')),
                DropdownMenuItem(value: 'closed', child: Text('Closed')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _filter = v);
                _reload();
              },
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: MutandeOrb.standard()),
          )
        else if (_error != null)
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF991B1B),
            ),
          )
        else if (_threads.isEmpty)
          Text(
            'No threads.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF78716C),
            ),
          )
        else
          ..._threads.map((t) {
            final statusColor = t.yourStatus == 'pending'
                ? const Color(0xFFB45309)
                : t.status == 'closed'
                ? const Color(0xFF78716C)
                : const Color(0xFF166534);
            final subtitle = [
              t.kind,
              t.status,
              if (t.yourStatus != null) t.yourStatus!,
            ].join(' · ');
            return InkWell(
              onTap: () => setState(() => _openId = t.id),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.from,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF292524),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFFA8A29E)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA8A29E)),
                  ],
                ),
              ),
            );
          }),
      ],
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
        _error = e.toString();
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
      setState(() => _error = e.toString());
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
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
            _detail!.from,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF292524),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${_detail!.kind} · ${_detail!.status}'
            '${_detail!.yourStatus != null ? ' · ${_detail!.yourStatus}' : ''}',
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
          ..._detail!.messages.map((m) {
            final body = m.bundleNotes ??
                m.bundleSubject ??
                m.openError ??
                '(no plaintext)';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.fromHandle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF78716C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: m.openError != null
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF292524),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
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
            onPressed: _sending || _detail!.status == 'closed' ? null : _sendReply,
            child: Text(_sending ? 'Sending…' : 'Send reply'),
          ),
        ],
      ],
    );
  }
}
