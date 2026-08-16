import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import '../../util/address_display.dart';
import '../../util/clock_format.dart';
import '../../util/thread_peer.dart';
import '../ai_host_icon.dart';
import '../contact_avatar.dart';
import '../home_chrome_pills.dart';
import '../mutande_stagger.dart';
import '../thread_skeletons.dart';
import 'collab_dash_card.dart';

/// Compact collab list — people first, counts as chips, recent via sort.
class CollabProjectsTable extends StatelessWidget {
  const CollabProjectsTable({
    super.key,
    required this.collabs,
    required this.onOpen,
    this.avatarUrls = const {},
    this.myHandle,
    this.sort = MutandeListSort.recent,
    this.onSort,
    this.loading = false,
    this.headerTrailing,
  });

  final List<CollabSummary> collabs;
  final ValueChanged<CollabSummary> onOpen;
  final Map<String, String> avatarUrls;
  final String? myHandle;
  final MutandeListSort sort;
  final ValueChanged<MutandeListSort>? onSort;
  final bool loading;
  final Widget? headerTrailing;

  List<CollabSummary> get _sorted {
    final copy = [...collabs];
    copy.sort((a, b) {
      if (sort == MutandeListSort.name) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return a.id.compareTo(b.id);
      }
      final byTime = (b.updatedAt ?? '').compareTo(a.updatedAt ?? '');
      if (byTime != 0) return byTime;
      return b.needsYouCount.compareTo(a.needsYouCount);
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return MutandeStaggerScope(
      child: CollabDashCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'Collabs',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MutandeColors.stone800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  MutandeSortToggles(
                    value: sort,
                    onChanged: onSort ?? (_) {},
                    recentKey: const Key('collab-sort-recent'),
                    nameKey: const Key('collab-sort-name'),
                  ),
                  const Spacer(),
                  if (headerTrailing != null) headerTrailing!,
                ],
              ),
            ),
            const SizedBox(height: 8),
            const _Header(),
            if (loading)
              const CollabTableRowsSkeleton()
            else
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: 8,
                    endIndent: 8,
                    color: MutandeColors.stone200,
                  ),
                MutandeStaggerIn(
                  id: rows[i].id,
                  child: _Row(
                    collab: rows[i],
                    avatarUrls: avatarUrls,
                    myHandle: myHandle,
                    onTap: () => onOpen(rows[i]),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

const _statusColWidth = 72.0;
const _updatedColWidth = 56.0;
const _rowPadding = EdgeInsets.fromLTRB(8, 13, 8, 13);

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          Expanded(flex: 5, child: _Head('Title')),
          SizedBox(
            width: _statusColWidth,
            child: Center(child: _Head('Status')),
          ),
          Expanded(flex: 4, child: _Head('Lanes')),
          SizedBox(
            width: _updatedColWidth,
            child: _Head('Updated', alignEnd: true),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.label, {this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: MutandeColors.stone400,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.collab,
    required this.avatarUrls,
    required this.onTap,
    this.myHandle,
  });

  final CollabSummary collab;
  final Map<String, String> avatarUrls;
  final String? myHandle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('collab-row-${collab.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: MutandeColors.stone100,
        child: Padding(
          padding: _rowPadding,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    _CollabFaceStack(
                      collab: collab,
                      avatarUrls: avatarUrls,
                      myHandle: myHandle,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        collab.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MutandeColors.stone800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _statusColWidth,
                child: collab.isActive
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _CountChip(
                            label: 'active',
                            foreground: MutandeColors.stone600,
                            background: MutandeColors.stone100,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LaneBar(collab: collab),
                    if (collab.openCount > 0 ||
                        collab.doingCount > 0 ||
                        collab.needsYouCount > 0) ...[
                      const SizedBox(height: 6),
                      _CardChips(collab: collab),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: _updatedColWidth,
                child: Text(
                  formatRelativeTime(collab.updatedAt),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MutandeColors.stone500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaneBar extends StatelessWidget {
  const _LaneBar({required this.collab});

  final CollabSummary collab;

  static const _height = 8.0;

  @override
  Widget build(BuildContext context) {
    final backlog = collab.backlogCount;
    final doing = collab.doingCount;
    final done = collab.doneCount;
    final total = backlog + doing + done;
    final label = total == 0
        ? 'No open cards'
        : 'Backlog $backlog · Doing $doing · Done $done';

    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          key: Key('collab-lane-bar-${collab.id}'),
          height: _height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: total == 0
                ? const ColoredBox(color: MutandeColors.stone200)
                : Row(
                    children: [
                      if (backlog > 0)
                        Expanded(
                          flex: backlog,
                          child: const ColoredBox(color: MutandeColors.stone400),
                        ),
                      if (backlog > 0 && (doing > 0 || done > 0))
                        const SizedBox(width: 1.5),
                      if (doing > 0)
                        Expanded(
                          flex: doing,
                          child: const ColoredBox(color: MutandeColors.bronze),
                        ),
                      if (doing > 0 && done > 0) const SizedBox(width: 1.5),
                      if (done > 0)
                        Expanded(
                          flex: done,
                          child: const ColoredBox(color: MutandeColors.stone800),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CardChips extends StatelessWidget {
  const _CardChips({required this.collab});

  final CollabSummary collab;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (collab.openCount > 0)
        _CountChip(
          label: '${collab.openCount} open',
          foreground: MutandeColors.stone600,
          background: MutandeColors.stone100,
        ),
      if (collab.doingCount > 0)
        _CountChip(
          label: '${collab.doingCount} doing',
          foreground: MutandeColors.bronze,
          background: MutandeColors.bronzeSoft,
        ),
      if (collab.needsYouCount > 0)
        _CountChip(
          label: '${collab.needsYouCount} needs you',
          foreground: MutandeColors.amber,
          background: MutandeColors.amberSoft,
        ),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          chips[i],
        ],
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: foreground,
        ),
      ),
    );
  }
}

class _CollabFaceStack extends StatelessWidget {
  const _CollabFaceStack({
    required this.collab,
    required this.avatarUrls,
    this.myHandle,
  });

  final CollabSummary collab;
  final Map<String, String> avatarUrls;
  final String? myHandle;

  static const _size = 26.0;
  static const _overlap = 10.0;
  static const _maxFaces = 3;

  @override
  Widget build(BuildContext context) {
    final faces = _facesFor(collab, avatarUrls, myHandle);
    if (faces.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = faces.take(_maxFaces).toList();
    final extra = faces.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final width = _size + (count - 1) * (_size - _overlap);
    final names = faces.map((f) => f.tooltip).join(', ');

    return Tooltip(
      message: names,
      child: SizedBox(
        width: width,
        height: _size,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * (_size - _overlap),
                child: _FaceRing(child: shown[i].mark),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * (_size - _overlap),
                child: _FaceRing(
                  child: _OverflowMark(label: '+$extra'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Face {
  const _Face({required this.mark, required this.tooltip});

  final Widget mark;
  final String tooltip;
}

List<_Face> _facesFor(
  CollabSummary collab,
  Map<String, String> avatarUrls,
  String? myHandle,
) {
  final me = myHandle == null || myHandle.trim().isEmpty
      ? null
      : bareMailHandle(myHandle);
  final people = <String>[];
  void addPerson(String raw) {
    final handle = bareMailHandle(raw);
    if (handle.isEmpty || handle.startsWith('@all')) return;
    if (people.contains(handle)) return;
    people.add(handle);
  }

  for (final h in collab.steererHandles) {
    addPerson(h);
  }
  if (people.isEmpty) {
    for (final r in collab.roster) {
      addPerson(r.address);
    }
  }

  final faces = <_Face>[
    for (final handle in people)
      _Face(
        tooltip: formatMailAddress(handle, myHandle: myHandle),
        mark: PersonAvatar(
          size: _CollabFaceStack._size - 2,
          initials: personInitials(titleCaseLocalPart(handle)),
          url: avatarUrls[handle],
          seed: handle,
          isSelf: me != null && handle == me,
        ),
      ),
  ];

  final slugs = <String>{};
  for (final r in collab.roster) {
    final slug = _agentSlug(r.address);
    if (slug == null || !slugs.add(slug)) continue;
    faces.add(
      _Face(
        tooltip: '@$slug',
        mark: _AgentMark(slug: slug),
      ),
    );
  }
  return faces;
}

String? _agentSlug(String address) {
  final a = address.trim().toLowerCase();
  final slash = a.lastIndexOf('/');
  if (slash <= 0 || slash >= a.length - 1) return null;
  final slug = a.substring(slash + 1);
  if (slug.isEmpty || slug == 'default') return null;
  return slug;
}

class _FaceRing extends StatelessWidget {
  const _FaceRing({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _CollabFaceStack._size,
      height: _CollabFaceStack._size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MutandeColors.stone50,
        border: Border.all(color: MutandeColors.stone50, width: 1.5),
      ),
      child: child,
    );
  }
}

class _AgentMark extends StatelessWidget {
  const _AgentMark({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _CollabFaceStack._size - 2,
      height: _CollabFaceStack._size - 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: MutandeColors.stone100,
        shape: BoxShape.circle,
      ),
      child: AiHostIcon(slug, size: 14, showPlate: false),
    );
  }
}

class _OverflowMark extends StatelessWidget {
  const _OverflowMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _CollabFaceStack._size - 2,
      height: _CollabFaceStack._size - 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: MutandeColors.stone800,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
          color: MutandeColors.stone50,
        ),
      ),
    );
  }
}
