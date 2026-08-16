import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../util/clock_format.dart';
import '../widgets/collab/collab_activity_calendar.dart';
import '../widgets/collab/collab_lane_donut.dart';
import '../widgets/collab/collab_metric_row.dart';
import '../widgets/collab/collab_project_dossier.dart';
import '../widgets/collab/collab_projects_table.dart';
import '../widgets/create_card_sheet.dart';
import '../widgets/create_collab_sheet.dart';
import '../widgets/mutande_sheet.dart';
import '../widgets/pane_quiet_state.dart';
import '../widgets/thread_skeletons.dart';
import 'threads_screen.dart';

export '../widgets/create_collab_sheet.dart'
    show collabEncryptionCopy, collabInstructionsVisible;

/// Human copy for collab fetch failures — never `GET /v1/collabs` or hub paths.
String collabFetchErrorCopy(Object error) {
  final mapped = friendlyDaemonError(error, what: 'collab');
  if (mapped.startsWith("Couldn't load collab")) {
    return "Couldn't load collab";
  }
  return mapped;
}

String? _collabQuietBody(String? error) {
  if (error == null || error.trim().isEmpty) return null;
  if (error == "Couldn't load collab" ||
      error.startsWith("Couldn't load collab")) {
    return 'Try again in a moment.';
  }
  return error;
}

/// Collab tab: named boards → Trello-style lanes. Card = thread.
class CollabPanel extends StatefulWidget {
  const CollabPanel({
    super.key,
    required this.daemon,
    this.handle,
    this.onReloadReady,
    this.initialCollabId,
    this.onInitialCollabHandled,
  });

  final DaemonClient daemon;
  final String? handle;
  final void Function(VoidCallback? reload)? onReloadReady;
  final String? initialCollabId;
  final VoidCallback? onInitialCollabHandled;

  @override
  State<CollabPanel> createState() => _CollabPanelState();
}

class _CollabPanelState extends State<CollabPanel> {
  bool _loading = true;
  String? _error;
  List<CollabSummary> _collabs = const [];
  CollabPortfolio _portfolio = const CollabPortfolio();
  String? _openId;

  @override
  void initState() {
    super.initState();
    widget.onReloadReady?.call(_reload);
    final initial = widget.initialCollabId?.trim();
    if (initial != null && initial.isNotEmpty) {
      _openId = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onInitialCollabHandled?.call();
      });
    }
    _reload();
  }

  @override
  void didUpdateWidget(covariant CollabPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialCollabId?.trim();
    final prev = oldWidget.initialCollabId?.trim();
    if (next != null && next.isNotEmpty && next != prev) {
      setState(() => _openId = next);
      widget.onInitialCollabHandled?.call();
    }
  }

  @override
  void dispose() {
    widget.onReloadReady?.call(null);
    super.dispose();
  }

  Future<void> _reload() async {
    final hasList = _collabs.isNotEmpty;
    setState(() {
      if (!hasList) _loading = true;
      _error = null;
    });
    try {
      final listed = await widget.daemon.listCollabs();
      if (!mounted) return;
      setState(() {
        _collabs = listed.collabs;
        _portfolio = listed.portfolio;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = collabFetchErrorCopy(e);
      });
    }
  }

  Future<void> _create({Rect? origin}) async {
    final created = await showCreateCollabSheet(
      context: context,
      daemon: widget.daemon,
      handle: widget.handle,
      origin: origin,
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

    final Widget child;
    if (_loading) {
      child = const CollabHomeSkeleton(key: ValueKey('sk'));
    } else if (_error != null && _collabs.isEmpty) {
      child = PaneQuietState(
        title: "Couldn't load collab",
        body: _collabQuietBody(_error),
        icon: Icons.cloud_off_outlined,
        onRetry: _reload,
      );
    } else if (_collabs.isEmpty) {
      child = PaneQuietState(
        title: 'No collabs yet',
        body: 'A collab is a board of threads — humans steer, agents work.',
        icon: Icons.view_kanban_outlined,
        retryLabel: 'Create',
        onRetryOrigin: (origin) => _create(origin: origin),
      );
    } else {
      child = Padding(
        key: const ValueKey('dash'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PaneInlineError(message: _error!, onRetry: _reload),
              ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: CollabMetricRow(
                      totals: _portfolio.totals,
                      onCreate: (origin) => _create(origin: origin),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(child: _chartsRow()),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: CollabProjectsTable(
                      collabs: _collabs,
                      onOpen: (c) => setState(() => _openId = c.id),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return MutandeFadeSwap(child: child);
  }

  Widget _chartsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final calendar = CollabActivityCalendar(
          key: const Key('collab-activity-calendar'),
          activity: _portfolio.activity,
        );
        final donut = CollabLaneDonut(
          key: const Key('collab-lane-donut'),
          lanes: _portfolio.laneTotals,
        );
        if (constraints.maxWidth < 720) {
          return Column(
            children: [calendar, const SizedBox(height: 12), donut],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: calendar),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: donut),
          ],
        );
      },
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
        _error = collabFetchErrorCopy(e);
      });
    }
  }

  Future<void> _newCard(String laneId, {Rect? origin}) async {
    String? laneName;
    for (final list in _collab?.lists ?? const <CollabListView>[]) {
      if (list.id == laneId) {
        laneName = list.name;
        break;
      }
    }
    final id = await showCreateCardSheet(
      context: context,
      daemon: widget.daemon,
      collabId: widget.collabId,
      laneId: laneId,
      laneName: laneName,
      origin: origin,
    );
    if (id == null || id.isEmpty) return;
    try {
      await _reload();
      if (!mounted) return;
      setState(() => _openCardId = id);
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

    final Widget child;
    if (_loading && _collab == null) {
      child = const CollabBoardSkeleton(key: ValueKey('sk'));
    } else {
      final collab = _collab;
      if (collab == null) {
        child = PaneQuietState(
          title: "Couldn't open collab",
          body: _collabQuietBody(_error) ?? 'Try again in a moment.',
          onRetry: _reload,
        );
      } else {
        child = Padding(
          key: const ValueKey('board'),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProjectHeader(
                name: collab.name,
                e2e: collab.isE2e,
                causeAddress: collab.causeAddress,
                brainOpen: _brainOpen,
                onBack: widget.onBack,
                onToggleBrain: () => setState(() => _brainOpen = !_brainOpen),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: PaneInlineError(
                    message: _error!,
                    onRetry: _reload,
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
                    : _ProjectPage(
                        collab: collab,
                        artifacts: collab.artifacts,
                        artifactsLoading: false,
                        handle: widget.handle,
                        onOpenBrain: () => setState(() => _brainOpen = true),
                        onOpen: (id) => setState(() => _openCardId = id),
                        onNewCard: _newCard,
                        onDrop: _drop,
                      ),
              ),
            ],
          ),
        );
      }
    }
    return MutandeFadeSwap(child: child);
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.name,
    required this.e2e,
    required this.brainOpen,
    required this.onBack,
    required this.onToggleBrain,
    this.causeAddress,
  });

  final String name;
  final bool e2e;
  final String? causeAddress;
  final bool brainOpen;
  final VoidCallback onBack;
  final VoidCallback onToggleBrain;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Boards',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
        ),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: MutandeColors.stone800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: collabEncryptionCopy(
                  e2e: e2e,
                  causeAddress: causeAddress,
                ),
                child: Icon(
                  Icons.lock_outline,
                  key: const Key('collab-seal'),
                  size: 14,
                  color: MutandeColors.stone400,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onToggleBrain,
          child: Text(brainOpen ? 'Board' : 'Brain'),
        ),
      ],
    );
  }
}

class _ProjectPage extends StatelessWidget {
  const _ProjectPage({
    required this.collab,
    List<CollabArtifactView>? artifacts,
    required this.artifactsLoading,
    required this.onOpenBrain,
    required this.onOpen,
    required this.onNewCard,
    required this.onDrop,
    this.handle,
  }) : _artifacts = artifacts;

  final CollabDetail collab;
  final List<CollabArtifactView>? _artifacts;
  List<CollabArtifactView> get artifacts => _artifacts ?? const [];
  final bool artifactsLoading;
  final VoidCallback onOpenBrain;
  final String? handle;
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
    return CollabProjectDossier(
      collab: collab,
      artifacts: artifacts,
      artifactsLoading: artifactsLoading,
      myHandle: handle,
      onOpenBrain: onOpenBrain,
      onOpenCard: onOpen,
      board: _Kanban(
        collab: collab,
        onOpen: onOpen,
        onNewCard: onNewCard,
        onDrop: onDrop,
      ),
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
      separatorBuilder: (_, _) => const SizedBox(width: 10),
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
          onNewCard: ({Rect? origin}) => onNewCard(lane.id, origin: origin),
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
  final void Function({Rect? origin}) onNewCard;
  final Future<void> Function(CollabCardView card, {String? beforeId}) onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<CollabCardView>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: MutandeMotion.of(
            context,
            const Duration(milliseconds: 120),
          ),
          curve: MutandeMotion.ease,
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
                      return Builder(
                        builder: (btnCtx) {
                          return TextButton.icon(
                            key: Key('collab-new-card-${lane.id}'),
                            onPressed: () => onNewCard(
                              origin: mutandeSheetOrigin(btnCtx),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('New card'),
                          );
                        },
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

  String get _meta {
    final owner = card.assignedTo?.trim();
    final who = (owner != null && owner.isNotEmpty)
        ? formatMailAddress(owner)
        : '';
    final when = formatRelativeTime(card.updatedAt);
    if (who.isNotEmpty && when.isNotEmpty) return '$who · $when';
    if (who.isNotEmpty) return who;
    return when;
  }

  @override
  Widget build(BuildContext context) {
    final title = (card.title?.trim().isNotEmpty == true)
        ? card.title!
        : (card.audience.isNotEmpty ? card.audience : 'Card');
    return DragTarget<CollabCardView>(
      onAcceptWithDetails: (d) {
        if (d.data.id != card.id) onDropBefore(d.data);
      },
      builder: (context, _, _) {
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
          if (_meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: MutandeColors.stone400,
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
    final showInstructions = collabInstructionsVisible(
      steerers: collab.steererHandles.isNotEmpty
          ? collab.steererHandles
          : [if (widget.handle != null) widget.handle!],
      roster: collab.roster.map((r) => r.address),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (showInstructions) ...[
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
        ],
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
