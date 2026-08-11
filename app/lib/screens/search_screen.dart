import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';

/// Threads-first search surface opened from the home chrome strip.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.daemon,
    required this.query,
    required this.recentQueries,
    required this.onPickRecent,
    required this.onOpenThread,
    this.myHandle,
  });

  final DaemonClient daemon;
  final String query;
  final List<String> recentQueries;
  final ValueChanged<String> onPickRecent;
  final ValueChanged<String> onOpenThread;
  final String? myHandle;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _filter = 'open';
  bool _loading = true;
  String? _error;
  List<ThreadSummary> _threads = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Query filter is client-side; only refetch when filter chips change via _reload.
  }

  Future<void> _reload() async {
    if (!mounted) return;
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
        _error = friendlyDaemonError(e, what: 'Search');
        _loading = false;
      });
    }
  }

  List<ThreadSummary> get _hits {
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _threads
        .where(
          (t) =>
              t.from.toLowerCase().contains(q) ||
              t.audience.toLowerCase().contains(q) ||
              t.kind.toLowerCase().contains(q) ||
              t.status.toLowerCase().contains(q) ||
              (t.agentBadge?.toLowerCase().contains(q) ?? false) ||
              (t.lastFrom?.toLowerCase().contains(q) ?? false) ||
              (t.lastSubject?.toLowerCase().contains(q) ?? false) ||
              (t.lastPreview?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Search',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: MutandeColors.stone800,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              _FilterChip(
                label: 'Needs you',
                selected: _filter == 'needs_action',
                onTap: () {
                  setState(() => _filter = 'needs_action');
                  _reload();
                },
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Open',
                selected: _filter == 'open',
                onTap: () {
                  setState(() => _filter = 'open');
                  _reload();
                },
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Closed',
                selected: _filter == 'closed',
                onTap: () {
                  setState(() => _filter = 'closed');
                  _reload();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _body(q)),
        ],
      ),
    );
  }

  Widget _body(String q) {
    if (q.isEmpty) {
      return _EmptySearch(
        recent: widget.recentQueries,
        onPick: widget.onPickRecent,
      );
    }
    if (_loading) {
      return const Center(
        child: MutandeOrb.standard(semanticLabel: 'Searching…'),
      );
    }
    if (_error != null) {
      return PaneQuietState(
        title: "Couldn't search",
        body: _error!,
        onRetry: _reload,
        icon: Icons.cloud_off_outlined,
      );
    }
    final hits = _hits;
    if (hits.isEmpty) {
      return Center(
        child: Text(
          'No threads match “$q”',
          style: const TextStyle(color: MutandeColors.stone500),
        ),
      );
    }
    return ListView.separated(
      itemCount: hits.length + 1,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: MutandeColors.stone200,
      ),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              'Threads · ${hits.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: MutandeColors.stone500,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        }
        final t = hits[i - 1];
        return _SearchHit(
          thread: t,
          myHandle: widget.myHandle,
          onTap: () => widget.onOpenThread(t.id),
        );
      },
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.recent, required this.onPick});

  final List<String> recent;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Search threads by people, agents, or kind',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: MutandeColors.stone600,
                    height: 1.4,
                  ),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'Recent',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: MutandeColors.stone500,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              ...recent.map(
                (q) => InkWell(
                  onTap: () => onPick(q),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          size: 16,
                          color: MutandeColors.stone400,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          q,
                          style: const TextStyle(
                            color: MutandeColors.stone800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? MutandeColors.stone200 : MutandeColors.stone50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? MutandeColors.stone400 : MutandeColors.stone200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? MutandeColors.stone800 : MutandeColors.stone500,
          ),
        ),
      ),
    );
  }
}

class _SearchHit extends StatelessWidget {
  const _SearchHit({
    required this.thread,
    required this.onTap,
    this.myHandle,
  });

  final ThreadSummary thread;
  final VoidCallback onTap;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final title = formatMailAddress(thread.from, myHandle: myHandle);
    final via = thread.agentBadge;
    final meta = [
      if (via != null && via.isNotEmpty && via != 'default') 'via $via',
      if (thread.replyCount > 0)
        thread.replyCount == 1 ? '1 reply' : '${thread.replyCount} replies',
      thread.kind,
    ].join(' · ');

    final host = (via != null &&
            via.isNotEmpty &&
            via != 'default' &&
            AiHostIcon.assetFor(via) != null)
        ? via.toLowerCase()
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MutandeColors.stone100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MutandeColors.stone200),
              ),
              child: host != null
                  ? AiHostIcon(host, size: 28, showPlate: false)
                  : Text(
                      title.isNotEmpty ? title[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: MutandeColors.stone500,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MutandeColors.stone800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MutandeColors.stone500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              formatMailAddress(thread.audience, myHandle: myHandle),
              style: const TextStyle(
                color: MutandeColors.stone400,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
