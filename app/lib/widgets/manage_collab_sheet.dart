import 'package:flutter/material.dart';

import '../models/agent_transport.dart';
import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'ai_host_icon.dart';
import 'contact_avatar.dart';
import 'create_collab_sheet.dart';
import 'mutande_stagger.dart';
import 'thinking_orb.dart';
import 'thread_skeletons.dart';
import 'transport_chip.dart';

class _PersonOpt {
  const _PersonOpt({
    required this.handle,
    this.listHandle,
    this.userId = '',
    this.displayName,
    this.avatarUrl,
    this.isSelf = false,
    this.isExternal = false,
    this.isCreator = false,
    this.onBoard = false,
  });

  final String handle;
  final String? listHandle;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final bool isSelf;
  final bool isExternal;
  final bool isCreator;
  final bool onBoard;

  String get rpcHandle {
    final raw = listHandle?.trim();
    if (raw != null && raw.isNotEmpty) return raw.toLowerCase();
    return handle;
  }
}

class _AgentOpt {
  const _AgentOpt({
    required this.agentId,
    required this.address,
    required this.ownerHandle,
    required this.slug,
    this.transport,
    this.onBoard = false,
  });

  final String agentId;
  final String address;
  final String ownerHandle;
  final String slug;
  final AgentTransport? transport;
  final bool onBoard;
}

class ManageCollabSheet extends StatefulWidget {
  const ManageCollabSheet({
    super.key,
    required this.daemon,
    required this.collab,
    this.handle,
    this.onChanged,
  });

  final DaemonClient daemon;
  final CollabDetail collab;
  final String? handle;
  final VoidCallback? onChanged;

  @override
  State<ManageCollabSheet> createState() => _ManageCollabSheetState();
}

class _ManageCollabSheetState extends State<ManageCollabSheet> {
  static const _wideBreakpoint = 720.0;

  late CollabDetail _collab;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<_PersonOpt> _people = const [];
  List<CollabPickerAgent> _agents = const [];

  String? get _me => bareCollabHandle(widget.handle);

  @override
  void initState() {
    super.initState();
    _collab = widget.collab;
    _load();
  }

  @override
  void didUpdateWidget(ManageCollabSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collab.id != oldWidget.collab.id) {
      _collab = widget.collab;
      _loading = true;
      _load();
      return;
    }
    _collab = widget.collab;
  }

  List<_AgentOpt> get _agentOpts {
    final out = <_AgentOpt>[];
    final seen = <String>{};
    void mark(String raw) {
      final t = raw.trim().toLowerCase();
      if (t.isNotEmpty) seen.add(t);
    }

    for (final r in _collab.roster) {
      final slug = collabRosterSlug(r.address) ?? r.address;
      out.add(
        _AgentOpt(
          agentId: r.agentId,
          address: r.address,
          ownerHandle: bareCollabHandle(r.address) ?? '',
          slug: slug,
          transport: AgentTransport.tryParse(r.transport),
          onBoard: true,
        ),
      );
      mark(r.agentId);
      mark(r.address);
    }
    for (final a in _agents) {
      if (seen.contains(a.agentId.trim().toLowerCase()) ||
          seen.contains(a.address.toLowerCase())) {
        continue;
      }
      out.add(
        _AgentOpt(
          agentId: a.agentId,
          address: a.address,
          ownerHandle: a.ownerHandle,
          slug: a.slug,
          transport: a.transport,
        ),
      );
    }
    out.sort((a, b) {
      if (a.onBoard != b.onBoard) return a.onBoard ? -1 : 1;
      return a.address.compareTo(b.address);
    });
    return out;
  }

  Future<void> _load() async {
    try {
      final me = _me;
      final contacts = await widget.daemon.listContacts();
      var external = const <ContactView>[];
      try {
        external = await widget.daemon.listExternalContacts();
      } catch (_) {}
      final onBoard = {
        for (final s in _collab.steerers) s.handle.trim().toLowerCase(),
      };
      final byHandle = <String, _PersonOpt>{};
      for (final s in _collab.steerers) {
        final h = s.handle.trim().toLowerCase();
        if (h.isEmpty) continue;
        byHandle[h] = _PersonOpt(
          handle: h,
          userId: s.userId,
          isSelf: h == me,
          isCreator: s.userId == _collab.createdBy,
          onBoard: true,
        );
      }
      void addContact(ContactView c, {required bool isExternal}) {
        if (c.isBroadcast) return;
        final h = bareCollabHandle(c.handle);
        if (h == null) return;
        final prev = byHandle[h];
        byHandle[h] = _PersonOpt(
          handle: h,
          listHandle: c.handle.trim(),
          userId: prev?.userId ?? '',
          displayName: c.displayName ?? prev?.displayName,
          avatarUrl: c.avatarUrl ?? prev?.avatarUrl,
          isSelf: h == me,
          isExternal: isExternal || (prev?.isExternal ?? false),
          isCreator: prev?.isCreator ?? false,
          onBoard: onBoard.contains(h),
        );
      }

      for (final c in contacts) {
        addContact(c, isExternal: c.isExternal);
      }
      for (final c in external) {
        addContact(c, isExternal: true);
      }

      final agents = <CollabPickerAgent>[];
      Future<void> addAgents(String owner, {String? rpcHandle}) async {
        try {
          final list = await widget.daemon.listAgents(handle: rpcHandle);
          for (final a in list.agents) {
            final slug = collabRosterSlug(a.slug);
            if (slug == null) continue;
            agents.add(
              CollabPickerAgent(
                agentId: a.id,
                address: owner == me ? '@$slug' : '$owner/$slug',
                ownerHandle: owner,
                slug: slug,
                causeAddress: collabCauseAddress(
                  ownerHandle: owner,
                  slug: slug,
                ),
                transport: a.transport,
              ),
            );
          }
        } catch (_) {}
      }

      if (me != null) await addAgents(me);
      final others = byHandle.values.where((p) => !p.isSelf).toList();
      await Future.wait(
        others.map((p) => addAgents(p.handle, rpcHandle: p.rpcHandle)),
      );

      if (!mounted) return;
      setState(() {
        _people = byHandle.values.toList()
          ..sort((a, b) {
            if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
            if (a.onBoard != b.onBoard) return a.onBoard ? -1 : 1;
            return a.handle.compareTo(b.handle);
          });
        _agents = collapseCollabAgents(agents);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyDaemonError(e, what: 'collab');
      });
    }
  }

  Future<void> _run(Future<CollabDetail> Function() op) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await op();
      if (!mounted) return;
      setState(() {
        _collab = next;
        _busy = false;
      });
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyDaemonError(e, what: 'collab');
      });
    }
  }

  Future<void> _addPerson(_PersonOpt p) async {
    if (_collab.isArchived || p.onBoard) return;
    await _run(
      () => widget.daemon.addCollabSteerer(
        collabId: _collab.id,
        handle: p.rpcHandle,
      ),
    );
  }

  Future<void> _removePerson(_PersonOpt p) async {
    if (_collab.isArchived || p.isCreator || p.userId.isEmpty) return;
    await _run(
      () => widget.daemon.removeCollabSteerer(
        collabId: _collab.id,
        userId: p.userId,
      ),
    );
  }

  Future<void> _addAgent(_AgentOpt a) async {
    if (_collab.isArchived) return;
    await _run(
      () => widget.daemon.addCollabRoster(
        collabId: _collab.id,
        address: a.address,
      ),
    );
  }

  Future<void> _removeAgent(_AgentOpt a) async {
    if (_collab.isArchived || a.agentId.isEmpty) return;
    await _run(
      () => widget.daemon.removeCollabRoster(
        collabId: _collab.id,
        agentId: a.agentId,
      ),
    );
  }

  Future<void> _toggleArchive() async {
    final archived = _collab.isArchived;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archived ? 'Unarchive this board?' : 'Archive this board?'),
        content: Text(
          archived
              ? 'It will show in the default list again.'
              : 'Hidden from the default list and frozen until you unarchive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(archived ? 'Unarchive' : 'Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_collab.isArchived) {
      await _run(() => widget.daemon.unarchiveCollab(_collab.id));
    } else {
      await _run(() => widget.daemon.archiveCollab(_collab.id));
    }
  }

  bool _wouldBreakE2e(_PersonOpt? person, _AgentOpt? agent) {
    if (!_collab.isE2e) return false;
    if (person?.isExternal == true) return true;
    if (agent != null && isHostedWebTransport(agent.transport)) return true;
    if (agent != null) {
      final owner = agent.ownerHandle.toLowerCase();
      final p = _people.where((x) => x.handle == owner).firstOrNull;
      if (p?.isExternal == true) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('collab-manage-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              _pagePad(context),
              0,
              _pagePad(context),
              8,
            ),
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: MutandeColors.stone600,
              ),
            ),
          ),
        Expanded(
          child: MutandeFadeSwap(
            child: _loading
                ? const Center(
                    key: ValueKey('manage-loading'),
                    child: ThinkingOrb(size: ThinkingOrbSize.inline),
                  )
                : KeyedSubtree(
                    key: const ValueKey('manage-body'),
                    child: _body(),
                  ),
          ),
        ),
        if (!_loading) _footer(),
      ],
    );
  }

  double _pagePad(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _wideBreakpoint ? 48 : 24;

  Widget _body() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final padH = wide ? 48.0 : 24.0;
        final people = _peoplePane(scroll: wide);
        final agents = _agentsPane(scroll: wide);
        final child = wide
            ? Row(
                key: const Key('manage-layout-columns'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: people),
                  const SizedBox(width: 48),
                  Expanded(child: agents),
                ],
              )
            : SingleChildScrollView(
                key: const Key('manage-layout-stack'),
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [people, const SizedBox(height: 32), agents],
                ),
              );
        return Padding(
          padding: EdgeInsets.fromLTRB(padH, 12, padH, 0),
          child: child,
        );
      },
    );
  }

  Widget _peoplePane({required bool scroll}) {
    final onBoard = _people.where((p) => p.onBoard).toList();
    final addable = _people.where((p) => !p.onBoard).toList();
    return _pane(
      label: 'People',
      count: onBoard.length,
      scroll: scroll,
      empty: 'No people yet.',
      children: [
        for (final p in onBoard) _personTile(p),
        if (onBoard.isNotEmpty && addable.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: MutandeColors.stone200),
          ),
        for (final p in addable) _personTile(p),
      ],
    );
  }

  Widget _agentsPane({required bool scroll}) {
    final opts = _agentOpts;
    final onBoard = opts.where((a) => a.onBoard).toList();
    final addable = opts.where((a) => !a.onBoard).toList();
    return _pane(
      label: 'Agents',
      count: onBoard.length,
      scroll: scroll,
      empty: 'Connect an AI host in Settings to add agents.',
      children: [
        for (final a in onBoard) _agentTile(a),
        if (onBoard.isNotEmpty && addable.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: MutandeColors.stone200),
          ),
        for (final a in addable) _agentTile(a),
      ],
    );
  }

  Widget _pane({
    required String label,
    required int count,
    required bool scroll,
    required String empty,
    required List<Widget> children,
  }) {
    final list = MutandeStaggerScope(
      delay: MutandeStaggerScope.sectionStagger,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (children.isEmpty)
            Text(
              empty,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: MutandeColors.stone400,
              ),
            )
          else
            ...children,
        ],
      ),
    );
    return Column(
      mainAxisSize: scroll ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ManageSectionLabel(label, count: count),
        const SizedBox(height: 14),
        if (scroll)
          Expanded(child: SingleChildScrollView(child: list))
        else
          list,
      ],
    );
  }

  Widget _personTile(_PersonOpt p) {
    final caption = p.isExternal
        ? 'external'
        : (p.isCreator ? 'creator' : (p.isSelf ? 'you' : null));
    return MutandeStaggerIn(
      id: p.handle,
      child: _ManageMemberTile(
        key: Key('manage-person-${p.handle}'),
        title: collabPersonTitle(displayName: p.displayName, handle: p.handle),
        subtitle: formatMailAddress(p.handle, myHandle: widget.handle),
        caption: caption,
        onBoard: p.onBoard,
        locked: p.isCreator || _collab.isArchived,
        busy: _busy,
        lockHint: p.isCreator ? 'Creator stays on the board' : null,
        onAdd: () => _addPerson(p),
        onRemove: () => _removePerson(p),
        warn: _wouldBreakE2e(p, null),
        warnExternal: p.isExternal,
        leading: PersonAvatar(
          size: 36,
          url: p.avatarUrl,
          initials: collabPersonInitials(
            collabPersonTitle(displayName: p.displayName, handle: p.handle),
          ),
          seed: p.handle,
          isSelf: p.isSelf,
        ),
      ),
    );
  }

  Widget _agentTile(_AgentOpt a) {
    final leading = AiHostIcon.assetFor(a.slug) == null
        ? null
        : AiHostIcon(a.slug, size: 18, showPlate: false);
    return MutandeStaggerIn(
      id: a.address,
      child: _ManageMemberTile(
        key: a.onBoard
            ? Key('manage-roster-${a.agentId}')
            : Key('manage-add-agent-${a.address}'),
        title: formatMailAddress(a.address, myHandle: widget.handle),
        leading: leading,
        trailing: TransportChip.webCaption(transport: a.transport),
        onBoard: a.onBoard,
        locked: _collab.isArchived,
        busy: _busy,
        onAdd: () => _addAgent(a),
        onRemove: () => _removeAgent(a),
        warn: _wouldBreakE2e(null, a),
      ),
    );
  }

  Widget _footer() {
    final padH = _pagePad(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(padH, 8, padH, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: MutandeColors.stone200),
          const SizedBox(height: 12),
          if (_collab.isArchived)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Membership is frozen until you unarchive.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: MutandeColors.stone500,
                ),
              ),
            )
          else if (_collab.isE2e)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                collabEncryptionCopy(e2e: true),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: MutandeColors.stone500,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('manage-archive'),
              onPressed: _busy ? null : _toggleArchive,
              style: TextButton.styleFrom(
                foregroundColor: MutandeColors.stone600,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              child: Text(_collab.isArchived ? 'Unarchive' : 'Archive'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManageSectionLabel extends StatelessWidget {
  const _ManageSectionLabel(this.label, {this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: MutandeColors.stone800,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone400,
            ),
          ),
        ],
      ],
    );
  }
}

class _ManageMemberTile extends StatefulWidget {
  const _ManageMemberTile({
    super.key,
    required this.title,
    this.subtitle,
    this.caption,
    this.leading,
    this.trailing,
    required this.onBoard,
    this.locked = false,
    this.busy = false,
    this.warn = false,
    this.warnExternal = false,
    this.lockHint,
    this.onAdd,
    this.onRemove,
  });

  final String title;
  final String? subtitle;
  final String? caption;
  final Widget? leading;
  final Widget? trailing;
  final bool onBoard;
  final bool locked;
  final bool busy;
  final bool warn;
  final bool warnExternal;
  final String? lockHint;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  State<_ManageMemberTile> createState() => _ManageMemberTileState();
}

class _ManageMemberTileState extends State<_ManageMemberTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final onBoard = widget.onBoard;
    final bg = _hover
        ? (onBoard ? MutandeColors.stone200 : MutandeColors.stone100)
        : (onBoard ? MutandeColors.stone100 : Colors.transparent);
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: MutandeMotion.of(context, MutandeMotion.hover),
        curve: MutandeMotion.easeOut,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.leading != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: widget.leading!,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: MutandeColors.stone800,
                    ),
                  ),
                  if (widget.subtitle != null ||
                      widget.caption != null ||
                      widget.trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              [
                                if (widget.caption != null) widget.caption,
                                if (widget.subtitle != null) widget.subtitle,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                color: MutandeColors.stone500,
                              ),
                            ),
                          ),
                          if (widget.trailing != null) ...[
                            const SizedBox(width: 6),
                            widget.trailing!,
                          ],
                        ],
                      ),
                    ),
                  if (widget.warn && !onBoard)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        collabEncryptionCopy(
                          e2e: false,
                          causeAddress: widget.title,
                          external: widget.warnExternal,
                        ),
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: MutandeColors.stone500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (onBoard)
              IconButton(
                tooltip: widget.lockHint ?? 'Remove',
                onPressed: widget.locked || widget.busy
                    ? null
                    : widget.onRemove,
                icon: const Icon(Icons.close, size: 16),
              )
            else
              TextButton(
                onPressed: widget.locked || widget.busy ? null : widget.onAdd,
                child: const Text('Add'),
              ),
          ],
        ),
      ),
    );

    return tile;
  }
}
