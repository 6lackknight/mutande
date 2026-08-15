import 'package:flutter/material.dart';

import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../theme/mutande_macos_theme.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thinking_orb.dart';
import 'threads_screen.dart';

/// Honest encryption copy — never says "insecure"; names the cause address.
String collabEncryptionCopy({required bool e2e, String? causeAddress}) {
  if (e2e) {
    return 'Mail in this collab is sealed to steerer devices.';
  }
  final who = (causeAddress ?? 'a hosted agent').toLowerCase();
  return "E2E isn't available for this collab — $who reads mail through the hub.";
}

/// Collab tab: named boards → Trello-style lanes. Card = thread.
class CollabPanel extends StatefulWidget {
  const CollabPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.onReloadReady,
  });

  final DaemonClient daemon;
  final String? handle;
  final void Function(VoidCallback? reload)? onReloadReady;

  @override
  State<CollabPanel> createState() => _CollabPanelState();
}

class _CollabPanelState extends State<CollabPanel> {
  bool _loading = true;
  String? _error;
  List<CollabSummary> _collabs = const [];
  String? _openId;

  @override
  void initState() {
    super.initState();
    widget.onReloadReady?.call(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.onReloadReady?.call(null);
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.daemon.listCollabs();
      if (!mounted) return;
      setState(() {
        _collabs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyDaemonError(e, what: 'Collab');
        _collabs = const [];
      });
    }
  }

  Future<void> _create() async {
    final created = await showDialog<CollabDetail>(
      context: context,
      builder: (ctx) =>
          _CreateCollabDialog(daemon: widget.daemon, handle: widget.handle),
    );
    if (created == null || !mounted) return;
    await _reload();
    if (!mounted) return;
    setState(() => _openId = created.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_openId != null) {
      return _CollabBoard(
        daemon: widget.daemon,
        collabId: _openId!,
        handle: widget.handle,
        onBack: () {
          setState(() => _openId = null);
          _reload();
        },
      );
    }

    if (_loading) {
      return Center(child: MutandeOrb.standard(size: ThinkingOrbSize.panel));
    }

    if (_collabs.isEmpty) {
      return PaneQuietState(
        title: 'No collabs yet',
        body: 'A collab is a board of threads — humans steer, agents work.',
        icon: Icons.view_kanban_outlined,
        retryLabel: 'Create',
        onRetry: _create,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: MutandeColors.bronze, fontSize: 12),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create'),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _collabs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final c = _collabs[i];
              return Material(
                color: MutandeColors.stone50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: MutandeColors.stone200),
                ),
                child: ListTile(
                  title: Text(
                    c.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: MutandeColors.stone800,
                    ),
                  ),
                  subtitle: Text(
                    '${c.cardCount} ${c.cardCount == 1 ? 'card' : 'cards'} · ${c.isE2e ? 'e2e' : 'app envelope'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MutandeColors.stone500,
                    ),
                  ),
                  onTap: () => setState(() => _openId = c.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CreateCollabDialog extends StatefulWidget {
  const _CreateCollabDialog({required this.daemon, this.handle});

  final DaemonClient daemon;
  final String? handle;

  @override
  State<_CreateCollabDialog> createState() => _CreateCollabDialogState();
}

class _CreateCollabDialogState extends State<_CreateCollabDialog> {
  final _name = TextEditingController();
  final _instructions = TextEditingController();
  final _roster = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _cause;
  bool _e2e = true;

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _roster.dispose();
    super.dispose();
  }

  Future<void> _refreshMode() async {
    final addrs = _roster.text
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    var e2e = true;
    String? cause;
    try {
      final own = await widget.daemon.listAgents();
      for (final addr in addrs) {
        final slug = addr.contains('/')
            ? addr.split('/').last
            : (addr.startsWith('@') ? addr.substring(1) : null);
        if (slug == null) continue;
        for (final a in own.agents) {
          if (a.slug == slug && a.transport == AgentTransport.mcp) {
            e2e = false;
            cause = addr.startsWith('@')
                ? '${(widget.handle ?? '').toLowerCase()}/$slug'.replaceFirst(
                    RegExp(r'^/'),
                    '',
                  )
                : addr;
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _e2e = e2e;
      _cause = cause;
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final roster = _roster.text
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.daemon.createCollab(
        name: name,
        rosterAddresses: roster,
        instructions: _e2e ? null : _instructions.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyDaemonError(e, what: 'Create collab');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create collab'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _roster,
              onChanged: (_) => _refreshMode(),
              decoration: const InputDecoration(
                labelText: 'Roster (agent addresses)',
                hintText: '@cursor, bob@acme/claude',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              collabEncryptionCopy(e2e: _e2e, causeAddress: _cause),
              style: const TextStyle(
                fontSize: 12,
                color: MutandeColors.stone600,
              ),
            ),
            if (!_e2e) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _instructions,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Instructions',
                  hintText: 'Standing context for this board',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: MutandeColors.bronze,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: MutandeOrb.standard(size: ThinkingOrbSize.inline),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _CollabBoard extends StatefulWidget {
  const _CollabBoard({
    required this.daemon,
    required this.collabId,
    required this.onBack,
    this.handle,
  });

  final DaemonClient daemon;
  final String collabId;
  final VoidCallback onBack;
  final String? handle;

  @override
  State<_CollabBoard> createState() => _CollabBoardState();
}

class _CollabBoardState extends State<_CollabBoard> {
  bool _loading = true;
  String? _error;
  CollabDetail? _collab;
  String? _openCardId;
  bool _brainOpen = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final c = await widget.daemon.getCollab(widget.collabId);
      if (!mounted) return;
      setState(() {
        _collab = c;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyDaemonError(e, what: 'Collab');
      });
    }
  }

  Future<void> _newCard(String laneId) async {
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctl = TextEditingController();
        return AlertDialog(
          title: const Text('New card'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (title == null || title.isEmpty) return;
    try {
      final id = await widget.daemon.createCollabCard(
        collabId: widget.collabId,
        title: title,
        laneId: laneId,
      );
      await _reload();
      if (!mounted) return;
      if (id.isNotEmpty) setState(() => _openCardId = id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyDaemonError(e, what: 'New card'));
    }
  }

  Future<void> _drop(
    CollabCardView card,
    String laneId, {
    String? beforeId,
  }) async {
    try {
      await widget.daemon.setLane(
        collabId: widget.collabId,
        threadId: card.id,
        laneId: laneId,
        beforeThreadId: beforeId,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyDaemonError(e, what: 'Move card'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_openCardId != null) {
      return ThreadDetailPanel(
        daemon: widget.daemon,
        threadId: _openCardId!,
        myHandle: widget.handle,
        embedded: true,
        onBack: () {
          setState(() => _openCardId = null);
          _reload();
        },
        onListChanged: _reload,
        onGone: () {
          setState(() => _openCardId = null);
          _reload();
        },
      );
    }

    if (_loading && _collab == null) {
      return Center(child: MutandeOrb.standard(size: ThinkingOrbSize.panel));
    }
    final collab = _collab;
    if (collab == null) {
      return PaneQuietState(
        title: 'Couldn’t open collab',
        body: _error,
        onRetry: _reload,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Boards',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
            ),
            Expanded(
              child: Text(
                collab.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: MutandeColors.stone800,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _brainOpen = !_brainOpen),
              child: Text(_brainOpen ? 'Board' : 'Brain'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            collabEncryptionCopy(
              e2e: collab.isE2e,
              causeAddress: collab.causeAddress,
            ),
            style: const TextStyle(fontSize: 12, color: MutandeColors.stone500),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: MutandeColors.bronze, fontSize: 12),
            ),
          ),
        Expanded(
          child: _brainOpen
              ? _BrainPanel(
                  daemon: widget.daemon,
                  collab: collab,
                  handle: widget.handle,
                  onChanged: _reload,
                )
              : _Kanban(
                  collab: collab,
                  onOpen: (id) => setState(() => _openCardId = id),
                  onNewCard: _newCard,
                  onDrop: _drop,
                ),
        ),
      ],
    );
  }
}

class _Kanban extends StatelessWidget {
  const _Kanban({
    required this.collab,
    required this.onOpen,
    required this.onNewCard,
    required this.onDrop,
  });

  final CollabDetail collab;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onNewCard;
  final Future<void> Function(
    CollabCardView card,
    String laneId, {
    String? beforeId,
  })
  onDrop;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: collab.lists.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final lane = collab.lists[i];
        final cards = collab.cards.where((c) => c.laneId == lane.id).toList()
          ..sort(
            (a, b) => (a.lanePosition ?? 0).compareTo(b.lanePosition ?? 0),
          );
        return _LaneColumn(
          lane: lane,
          cards: cards,
          onOpen: onOpen,
          onNewCard: () => onNewCard(lane.id),
          onDrop: (card, {String? beforeId}) =>
              onDrop(card, lane.id, beforeId: beforeId),
        );
      },
    );
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.lane,
    required this.cards,
    required this.onOpen,
    required this.onNewCard,
    required this.onDrop,
  });

  final CollabListView lane;
  final List<CollabCardView> cards;
  final ValueChanged<String> onOpen;
  final VoidCallback onNewCard;
  final Future<void> Function(CollabCardView card, {String? beforeId}) onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<CollabCardView>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 260,
          decoration: BoxDecoration(
            color: hot ? MutandeColors.bronzeSoft : MutandeColors.stone100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MutandeColors.stone200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lane.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: MutandeColors.stone800,
                        ),
                      ),
                    ),
                    Text(
                      '${cards.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: MutandeColors.stone400,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: cards.length + 1,
                  itemBuilder: (context, i) {
                    if (i == cards.length) {
                      return TextButton.icon(
                        onPressed: onNewCard,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('New card'),
                      );
                    }
                    final card = cards[i];
                    return _CardTile(
                      card: card,
                      onOpen: () => onOpen(card.id),
                      onDropBefore: (incoming) =>
                          onDrop(incoming, beforeId: card.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.onOpen,
    required this.onDropBefore,
  });

  final CollabCardView card;
  final VoidCallback onOpen;
  final ValueChanged<CollabCardView> onDropBefore;

  @override
  Widget build(BuildContext context) {
    final title = (card.title?.trim().isNotEmpty == true)
        ? card.title!
        : (card.audience.isNotEmpty ? card.audience : 'Card');
    return DragTarget<CollabCardView>(
      onAcceptWithDetails: (d) {
        if (d.data.id != card.id) onDropBefore(d.data);
      },
      builder: (context, _, __) {
        return LongPressDraggable<CollabCardView>(
          data: card,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 236,
              child: _cardBody(title, dragging: true),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: _cardBody(title)),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(8),
                child: _cardBody(title),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cardBody(String title, {bool dragging = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MutandeColors.stone200),
        boxShadow: dragging
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: MutandeColors.stone800,
            ),
          ),
          if (card.needsYou) ...[
            const SizedBox(height: 4),
            const Text(
              'Needs you',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: MutandeColors.amber,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrainPanel extends StatefulWidget {
  const _BrainPanel({
    required this.daemon,
    required this.collab,
    required this.onChanged,
    this.handle,
  });

  final DaemonClient daemon;
  final CollabDetail collab;
  final VoidCallback onChanged;
  final String? handle;

  @override
  State<_BrainPanel> createState() => _BrainPanelState();
}

class _BrainPanelState extends State<_BrainPanel> {
  late final TextEditingController _instructions;
  final _learning = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _instructions = TextEditingController(
      text: widget.collab.instructions ?? '',
    );
  }

  @override
  void dispose() {
    _instructions.dispose();
    _learning.dispose();
    super.dispose();
  }

  Future<void> _saveInstructions() async {
    setState(() => _saving = true);
    try {
      await widget.daemon.updateCollabInstructions(
        collabId: widget.collab.id,
        instructions: _instructions.text,
      );
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLearning() async {
    final notes = _learning.text.trim();
    if (notes.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.daemon.addLearning(collabId: widget.collab.id, notes: notes);
      _learning.clear();
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collab = widget.collab;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        const Text(
          'Instructions',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: MutandeColors.stone800,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _instructions,
          maxLines: 5,
          enabled: !collab.isE2e,
          decoration: InputDecoration(
            hintText: collab.isE2e
                ? 'E2E instructions stay sealed on this device.'
                : 'Standing context for this board',
          ),
        ),
        if (!collab.isE2e)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _saving ? null : _saveInstructions,
              child: const Text('Save'),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Learnings',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: MutandeColors.stone800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'One-liners, not diaries. Context — not directives.',
          style: TextStyle(fontSize: 12, color: MutandeColors.stone500),
        ),
        const SizedBox(height: 8),
        if (collab.learnings.isEmpty)
          const Text(
            'No learnings yet.',
            style: TextStyle(fontSize: 13, color: MutandeColors.stone400),
          ),
        for (final l in collab.learnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.notes?.trim().isNotEmpty == true
                  ? '${l.fromHandle}: ${l.notes}'
                  : '${l.fromHandle}: sealed learning',
              style: const TextStyle(
                fontSize: 13,
                color: MutandeColors.stone600,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _learning,
                decoration: const InputDecoration(
                  hintText: 'Add a one-line learning',
                ),
                onSubmitted: (_) => _addLearning(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _addLearning,
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}
