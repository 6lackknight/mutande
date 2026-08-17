import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../util/clock_format.dart';
import '../util/thread_peer.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/collab/collab_activity_calendar.dart';
import '../widgets/collab/collab_brain_pane.dart';
import '../widgets/collab/collab_lane_donut.dart';
import '../widgets/collab/collab_metric_row.dart';
import '../widgets/collab/collab_project_dossier.dart';
import '../widgets/collab/collab_projects_table.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/create_card_sheet.dart';
import '../widgets/create_collab_sheet.dart';
import '../widgets/downgrade_consent_banner.dart';
import '../widgets/home_chrome_pills.dart';
import '../widgets/home_chrome_strip.dart';
import '../widgets/manage_collab_sheet.dart';
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
    this.userId,
    this.onReloadReady,
    this.initialCollabId,
    this.onInitialCollabHandled,
  });

  final DaemonClient daemon;
  final String? handle;
  final String? userId;
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
  Map<String, String> _avatarsByHandle = const {};
  String? _openId;
  String? _pendingCardId;
  bool _showArchived = false;
  MutandeListSort _sort = MutandeListSort.recent;

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
      final listed = await widget.daemon.listCollabs(archived: _showArchived);
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
    final needRecent = _portfolio.recent.isEmpty && _error == null;
    final recentFuture = needRecent
        ? _recentFromInbox()
        : Future<List<CollabRecentThread>>.value(const []);
    final avatarsFuture = _loadAvatarMap();
    final recent = await recentFuture;
    final avatars = await avatarsFuture;
    if (!mounted) return;
    if (recent.isEmpty && avatars.isEmpty) return;
    setState(() {
      if (recent.isNotEmpty && _portfolio.recent.isEmpty) {
        _portfolio = _portfolio.copyWith(recent: recent);
      }
      if (avatars.isNotEmpty) {
        _avatarsByHandle = avatars;
      }
    });
  }

  Future<List<CollabRecentThread>> _recentFromInbox() async {
    try {
      return recentFromThreads(await widget.daemon.listThreads());
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, String>> _loadAvatarMap() async {
    try {
      final org = await widget.daemon.listContacts();
      return avatarUrlsByHandle([
        for (final c in org) (handle: c.handle, avatarUrl: c.avatarUrl),
      ]);
    } catch (_) {
      return const {};
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
        userId: widget.userId,
        avatarUrls: _avatarsByHandle,
        initialCardId: _pendingCardId,
        onBack: () {
          setState(() {
            _openId = null;
            _pendingCardId = null;
          });
          _reload();
        },
      );
    }

    final Widget child;
    final empty = !_loading && _error == null && _collabs.isEmpty;
    final failed = !_loading && _error != null && _collabs.isEmpty;
    child = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (empty || failed) ...[
            _CollabHomeChrome(archiveFilter: _archiveFilter()),
            const SizedBox(height: 12),
          ],
          if (_error != null && _collabs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PaneInlineError(message: _error!, onRetry: _reload),
            ),
          Expanded(
            child: failed
                ? PaneQuietState(
                    title: "Couldn't load collab",
                    body: _collabQuietBody(_error),
                    icon: Icons.cloud_off_outlined,
                    onRetry: _reload,
                  )
                : empty
                ? PaneQuietState(
                    title: _showArchived
                        ? 'No archived collabs'
                        : 'No collabs yet',
                    body: _showArchived
                        ? 'Archived boards stay here until you unarchive them.'
                        : 'A collab is a board of threads — humans steer, agents work.',
                    icon: Icons.view_kanban_outlined,
                    retryLabel: _showArchived ? 'Boards' : 'Create',
                    onRetry: _showArchived
                        ? () {
                            setState(() => _showArchived = false);
                            _reload();
                          }
                        : null,
                    onRetryOrigin: _showArchived
                        ? null
                        : (origin) => _create(origin: origin),
                  )
                : CustomScrollView(
                    slivers: [
                      if (!_showArchived) ...[
                        SliverToBoxAdapter(
                          child: CollabMetricRow(
                            totals: _portfolio.totals,
                            loading: _loading,
                            onCreate: (origin) => _create(origin: origin),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(child: _chartsRow(loading: _loading)),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      ],
                      SliverToBoxAdapter(
                        child: CollabProjectsTable(
                          collabs: _collabs,
                          avatarUrls: _avatarsByHandle,
                          myHandle: widget.handle,
                          sort: _sort,
                          onSort: (next) => setState(() => _sort = next),
                          loading: _loading,
                          headerTrailing: _archiveFilter(),
                          onOpen: (c) => setState(() {
                            _openId = c.id;
                            _pendingCardId = null;
                          }),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
    return MutandeFadeSwap(child: child);
  }

  Widget _archiveFilter() {
    return HomeChromeLabelPill(
      key: const Key('collab-archived-filter'),
      label: 'Archived',
      selected: _showArchived,
      onTap: () {
        setState(() => _showArchived = !_showArchived);
        _reload();
      },
    );
  }

  Widget _chartsRow({required bool loading}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final calendar = loading
            ? const CollabActivitySkeleton(
                key: Key('collab-activity-calendar'),
              )
            : MutandeArrive(
                order: 5,
                child: CollabActivityCalendar(
                  key: const Key('collab-activity-calendar'),
                  activity: _portfolio.activity,
                  recent: _portfolio.recent,
                  myHandle: widget.handle,
                  onOpenThread: (item) {
                    if (item.collabId.isEmpty) return;
                    setState(() {
                      _openId = item.collabId;
                      _pendingCardId = item.threadId;
                    });
                  },
                ),
              );
        final donut = loading
            ? const CollabLanesSkeleton(key: Key('collab-lane-donut'))
            : MutandeArrive(
                order: 6,
                child: CollabLaneDonut(
                  key: const Key('collab-lane-donut'),
                  lanes: _portfolio.laneTotals,
                ),
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

class _CollabHomeChrome extends StatelessWidget {
  const _CollabHomeChrome({required this.archiveFilter});

  final Widget archiveFilter;

  @override
  Widget build(BuildContext context) {
    return Row(children: [archiveFilter, const Spacer()]);
  }
}

enum _CollabBoardPane { board, brain, manage }

class _CollabBoard extends StatefulWidget {
  const _CollabBoard({
    required this.daemon,
    required this.collabId,
    required this.onBack,
    this.handle,
    this.userId,
    this.avatarUrls = const {},
    this.initialCardId,
  });

  final DaemonClient daemon;
  final String collabId;
  final VoidCallback onBack;
  final String? handle;
  final String? userId;
  final Map<String, String> avatarUrls;
  final String? initialCardId;

  @override
  State<_CollabBoard> createState() => _CollabBoardState();
}

class _CollabBoardState extends State<_CollabBoard> {
  bool _loading = true;
  String? _error;
  CollabDetail? _collab;
  _CollabBoardPane _pane = _CollabBoardPane.board;
  String? _pendingCardId;

  @override
  void initState() {
    super.initState();
    _pendingCardId = widget.initialCardId?.trim();
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
      final pending = _pendingCardId;
      if (pending != null && pending.isNotEmpty) {
        _pendingCardId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openCard(pending);
        });
      }
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
      people: _collab?.steererHandles ?? const [],
      agents: _collab?.roster ?? const [],
      handle: widget.handle,
    );
    if (id == null || id.isEmpty) return;
    await _reload();
    if (!mounted) return;
    await _openCard(id);
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

  Future<void> _openCard(String threadId) async {
    await showMutandeFullscreen<void>(
      context: context,
      barrierLabel: 'Card',
      builder: (ctx) => _CollabCardModal(
        daemon: widget.daemon,
        threadId: threadId,
        handle: widget.handle,
        onChanged: _reload,
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final loadingBoard = _loading && _collab == null;
    final collab =
        _collab ??
        const CollabDetail(id: '', name: '', encryptionMode: 'e2e', lists: []);
    final Widget child;
    if (!loadingBoard && _collab == null) {
      child = PaneQuietState(
        title: "Couldn't open collab",
        body: _collabQuietBody(_error) ?? 'Try again in a moment.',
        onRetry: _reload,
      );
    } else {
      child = Padding(
        key: ValueKey(loadingBoard ? 'board-sk' : 'board'),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectHeader(
              name: loadingBoard ? 'Collab' : collab.name,
              e2e: collab.isE2e,
              causeAddress: collab.causeAddress,
              archived: collab.isArchived,
              pane: _pane,
              loading: loadingBoard,
              onBack: widget.onBack,
              onBoard: loadingBoard
                  ? null
                  : () => setState(() => _pane = _CollabBoardPane.board),
              onBrain: loadingBoard
                  ? null
                  : () => setState(() => _pane = _CollabBoardPane.brain),
              onManage: loadingBoard
                  ? null
                  : () => setState(() => _pane = _CollabBoardPane.manage),
              onUnarchive: collab.isArchived
                  ? () async {
                      await widget.daemon.unarchiveCollab(widget.collabId);
                      await _reload();
                    }
                  : null,
            ),
            if (collab.pendingMembership != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: DowngradeConsentBanner(
                  prompt:
                      'Adding ${collab.pendingMembership!.who} ends device-sealed mail from this point.',
                  detail:
                      'All steerers must agree. Pre-downgrade history stays sealed.',
                  busy: false,
                  onApprove: () async {
                    await widget.daemon.approveCollabPendingMembership(
                      widget.collabId,
                    );
                    await _reload();
                  },
                  onDeny: () async {
                    await widget.daemon.denyCollabPendingMembership(
                      widget.collabId,
                    );
                    await _reload();
                  },
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: PaneInlineError(message: _error!, onRetry: _reload),
              ),
            Expanded(
              child: !loadingBoard && _pane == _CollabBoardPane.brain
                  ? CollabBrainPane(
                      daemon: widget.daemon,
                      collab: collab,
                      handle: widget.handle,
                      userId: widget.userId,
                      avatarUrls: widget.avatarUrls,
                      onChanged: _reload,
                    )
                  : !loadingBoard && _pane == _CollabBoardPane.manage
                  ? ManageCollabSheet(
                      daemon: widget.daemon,
                      collab: collab,
                      handle: widget.handle,
                      onChanged: _reload,
                    )
                  : _ProjectPage(
                      collab: collab,
                      artifacts: collab.artifacts,
                      artifactsLoading: loadingBoard,
                      loading: loadingBoard,
                      handle: widget.handle,
                      avatarUrls: widget.avatarUrls,
                      readOnly: collab.isArchived,
                      onOpenBrain: () =>
                          setState(() => _pane = _CollabBoardPane.brain),
                      onOpen: _openCard,
                      onNewCard: _newCard,
                      onDrop: _drop,
                      onManage: () =>
                          setState(() => _pane = _CollabBoardPane.manage),
                    ),
            ),
          ],
        ),
      );
    }
    return MutandeFadeSwap(child: child);
  }
}

class _CollabCardModal extends StatelessWidget {
  const _CollabCardModal({
    required this.daemon,
    required this.threadId,
    required this.onChanged,
    this.handle,
  });

  final DaemonClient daemon;
  final String threadId;
  final VoidCallback onChanged;
  final String? handle;

  void _close(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Material(
        color: MutandeColors.stone50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, HomeChrome.height, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('collab-card-close'),
                    tooltip: 'Close',
                    onPressed: () => _close(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ThreadDetailPanel(
                daemon: daemon,
                threadId: threadId,
                myHandle: handle,
                embedded: true,
                onBack: () => _close(context),
                onListChanged: onChanged,
                onGone: () => _close(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.name,
    required this.e2e,
    required this.pane,
    required this.onBack,
    this.archived = false,
    this.onBoard,
    this.onBrain,
    this.onManage,
    this.onUnarchive,
    this.causeAddress,
    this.loading = false,
  });

  final String name;
  final bool e2e;
  final String? causeAddress;
  final _CollabBoardPane pane;
  final bool archived;
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback? onBoard;
  final VoidCallback? onBrain;
  final VoidCallback? onManage;
  final VoidCallback? onUnarchive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
                  child: loading
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 120,
                            height: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: MutandeColors.stone200,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Text(
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
                    LucideIcons.shield,
                    key: const Key('collab-seal'),
                    size: 14,
                    color: MutandeColors.stone400,
                  ),
                ),
                if (archived) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Archived',
                    key: Key('collab-archived-chip'),
                    style: TextStyle(
                      fontSize: 11,
                      color: MutandeColors.stone500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          HomeChromeLabelPill(
            key: const Key('collab-mode-board'),
            label: 'Board',
            icon: LucideIcons.squareKanban,
            selected: pane == _CollabBoardPane.board,
            onTap: onBoard,
          ),
          const SizedBox(width: 4),
          HomeChromeLabelPill(
            key: const Key('collab-mode-brain'),
            label: 'Brain',
            icon: LucideIcons.brain,
            selected: pane == _CollabBoardPane.brain,
            onTap: onBrain,
          ),
          const SizedBox(width: 4),
          HomeChromeLabelPill(
            key: const Key('collab-mode-manage'),
            label: 'Manage',
            icon: LucideIcons.settings2,
            selected: pane == _CollabBoardPane.manage,
            onTap: onManage,
          ),
          if (onUnarchive != null)
            PopupMenuButton<String>(
              key: const Key('collab-manage-menu'),
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'unarchive') onUnarchive?.call();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'unarchive',
                  child: Text('Unarchive'),
                ),
              ],
              icon: const Icon(Icons.more_horiz, size: 18),
            ),
        ],
      ),
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
    this.avatarUrls = const {},
    this.readOnly = false,
    this.onManage,
    this.loading = false,
  }) : _artifacts = artifacts;

  final CollabDetail collab;
  final List<CollabArtifactView>? _artifacts;
  List<CollabArtifactView> get artifacts => _artifacts ?? const [];
  final bool artifactsLoading;
  final VoidCallback onOpenBrain;
  final String? handle;
  final Map<String, String> avatarUrls;
  final bool readOnly;
  final VoidCallback? onManage;
  final bool loading;
  final ValueChanged<String> onOpen;
  final void Function(String laneId, {Rect? origin}) onNewCard;
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
      loading: loading,
      myHandle: handle,
      onOpenBrain: onOpenBrain,
      onOpenCard: onOpen,
      onManageGroup: onManage,
      board: loading
          ? const CollabBoardSkeleton()
          : _Kanban(
              collab: collab,
              readOnly: readOnly,
              handle: handle,
              avatarUrls: avatarUrls,
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
    this.handle,
    this.avatarUrls = const {},
    this.readOnly = false,
  });

  final CollabDetail collab;
  final bool readOnly;
  final String? handle;
  final Map<String, String> avatarUrls;
  final ValueChanged<String> onOpen;
  final void Function(String laneId, {Rect? origin}) onNewCard;
  final Future<void> Function(
    CollabCardView card,
    String laneId, {
    String? beforeId,
  })
  onDrop;

  static const _padH = 16.0;
  static const _gap = 10.0;
  static const _minLaneWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final n = collab.lists.length;
    if (n == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = n > 1 ? (n - 1) * _gap : 0.0;
        final share = (constraints.maxWidth - _padH - gaps) / n;
        final fill = share >= _minLaneWidth;

        Widget column(int i, {double? width}) {
          final lane = collab.lists[i];
          final cards = collab.cards.where((c) => c.laneId == lane.id).toList()
            ..sort(
              (a, b) => (a.lanePosition ?? 0).compareTo(b.lanePosition ?? 0),
            );
          return _LaneColumn(
            key: Key('collab-lane-${lane.id}'),
            lane: lane,
            cards: cards,
            width: width,
            readOnly: readOnly,
            handle: handle,
            avatarUrls: avatarUrls,
            onOpen: onOpen,
            onNewCard: ({Rect? origin}) => onNewCard(lane.id, origin: origin),
            onDrop: (card, {String? beforeId}) =>
                onDrop(card, lane.id, beforeId: beforeId),
          );
        }

        if (fill) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Expanded(child: column(i)),
                ],
              ],
            ),
          );
        }

        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          itemCount: n,
          separatorBuilder: (_, _) => const SizedBox(width: _gap),
          itemBuilder: (context, i) => column(i, width: _minLaneWidth),
        );
      },
    );
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    super.key,
    required this.lane,
    required this.cards,
    required this.onOpen,
    required this.onNewCard,
    required this.onDrop,
    this.width,
    this.handle,
    this.avatarUrls = const {},
    this.readOnly = false,
  });

  final CollabListView lane;
  final List<CollabCardView> cards;
  final double? width;
  final bool readOnly;
  final String? handle;
  final Map<String, String> avatarUrls;
  final ValueChanged<String> onOpen;
  final void Function({Rect? origin}) onNewCard;
  final Future<void> Function(CollabCardView card, {String? beforeId}) onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<CollabCardView>(
      onAcceptWithDetails: readOnly ? null : (d) => onDrop(d.data),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: MutandeMotion.of(
            context,
            const Duration(milliseconds: 120),
          ),
          curve: MutandeMotion.ease,
          width: width ?? double.infinity,
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
                      if (readOnly) return const SizedBox.shrink();
                      return Builder(
                        builder: (btnCtx) {
                          return TextButton.icon(
                            key: Key('collab-new-card-${lane.id}'),
                            onPressed: () =>
                                onNewCard(origin: mutandeSheetOrigin(btnCtx)),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('New card'),
                          );
                        },
                      );
                    }
                    final card = cards[i];
                    return _CardTile(
                      card: card,
                      myHandle: handle,
                      avatarUrls: avatarUrls,
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
    this.myHandle,
    this.avatarUrls = const {},
  });

  final CollabCardView card;
  final VoidCallback onOpen;
  final ValueChanged<CollabCardView> onDropBefore;
  final String? myHandle;
  final Map<String, String> avatarUrls;

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
        return LayoutBuilder(
          builder: (context, constraints) {
            final feedbackWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 236.0;
            return LongPressDraggable<CollabCardView>(
              data: card,
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: feedbackWidth,
                  child: _cardBody(title, dragging: true),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _cardBody(title),
              ),
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
      },
    );
  }

  /// Ticket rail (locked from prototype variant C) — thin bronze/stone
  /// left rail, title, compact footer (faces · due · time).
  Widget _cardBody(String title, {bool dragging = false}) {
    final due = formatDueOn(card.dueOn);
    final time = formatRelativeTime(card.updatedAt);
    final faces = _facesForCard(
      card,
      myHandle: myHandle,
      avatarUrls: avatarUrls,
    );
    final rail = card.needsYou ? MutandeColors.bronze : MutandeColors.stone200;
    final footer = faces.isNotEmpty || due.isNotEmpty || time.isNotEmpty;
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: rail),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                        height: 1.25,
                        color: MutandeColors.stone800,
                      ),
                    ),
                    if (footer) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (faces.isNotEmpty) ...[
                            _CardFaceStack(faces: faces, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              [
                                if (due.isNotEmpty) due,
                                if (time.isNotEmpty) time,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: MutandeColors.stone400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFace {
  const _CardFace({required this.mark, required this.tooltip});

  final Widget mark;
  final String tooltip;
}

class _CardFaceStack extends StatelessWidget {
  const _CardFaceStack({required this.faces, this.size = 18});

  final List<_CardFace> faces;
  final double size;

  static const _overlap = 8.0;
  static const _maxFaces = 3;

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) return const SizedBox.shrink();
    final shown = faces.take(_maxFaces).toList();
    final extra = faces.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final width = size + (count - 1) * (size - _overlap);
    final names = faces.map((f) => f.tooltip).join(', ');

    return Tooltip(
      message: names,
      child: SizedBox(
        width: width,
        height: size,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * (size - _overlap),
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MutandeColors.stone50,
                    border: Border.all(
                      color: MutandeColors.stone50,
                      width: 1.5,
                    ),
                  ),
                  child: shown[i].mark,
                ),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * (size - _overlap),
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: MutandeColors.stone800,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w700,
                      color: MutandeColors.stone50,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<_CardFace> _facesForCard(
  CollabCardView card, {
  String? myHandle,
  Map<String, String> avatarUrls = const {},
}) {
  final faces = <_CardFace>[];
  final seenPeople = <String>{};
  final seenSlugs = <String>{};
  final me = myHandle == null || myHandle.trim().isEmpty
      ? null
      : bareMailHandle(myHandle);

  void addPerson(String raw) {
    final handle = bareMailHandle(raw);
    if (handle.isEmpty || handle.startsWith('@all')) return;
    if (!seenPeople.add(handle)) return;
    faces.add(
      _CardFace(
        tooltip: formatMailAddress(raw, myHandle: myHandle),
        mark: PersonAvatar(
          size: 16,
          initials: personInitials(titleCaseLocalPart(handle)),
          url: avatarUrls[handle],
          seed: handle,
          isSelf: me != null && handle == me,
        ),
      ),
    );
  }

  void addHost(String raw) {
    final slug = _cardAgentSlug(raw);
    if (slug == null || !seenSlugs.add(slug)) return;
    faces.add(
      _CardFace(
        tooltip: '@$slug',
        mark: Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: MutandeColors.stone100,
            shape: BoxShape.circle,
          ),
          child: AiHostIcon(slug, size: 11, showPlate: false),
        ),
      ),
    );
  }

  final assigned = card.assignedTo?.trim();
  if (assigned != null && assigned.isNotEmpty) {
    addPerson(assigned);
    addHost(assigned);
  }
  final from = card.from.trim();
  if (from.isNotEmpty) {
    addPerson(from);
    addHost(from);
  }
  return faces;
}

String? _cardAgentSlug(String address) {
  final a = address.trim().toLowerCase();
  final slash = a.lastIndexOf('/');
  if (slash <= 0 || slash >= a.length - 1) return null;
  final slug = a.substring(slash + 1);
  if (slug.isEmpty || slug == 'default') return null;
  return slug;
}
