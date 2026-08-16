import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import '../../util/clock_format.dart';
import '../mutande_stagger.dart';
import 'collab_dash_card.dart';

/// Compact collab list — all steered boards, active first via sort.
class CollabProjectsTable extends StatelessWidget {
  const CollabProjectsTable({
    super.key,
    required this.collabs,
    required this.onOpen,
  });

  final List<CollabSummary> collabs;
  final ValueChanged<CollabSummary> onOpen;

  List<CollabSummary> get _sorted {
    final copy = [...collabs];
    copy.sort((a, b) {
      final needs = b.needsYouCount.compareTo(a.needsYouCount);
      if (needs != 0) return needs;
      return (b.updatedAt ?? '').compareTo(a.updatedAt ?? '');
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return MutandeStaggerScope(
      child: CollabDashCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Collabs',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MutandeColors.stone800,
              ),
            ),
            const SizedBox(height: 10),
            const _Header(),
            const Divider(height: 1, color: MutandeColors.stone200),
            for (final collab in rows) ...[
              MutandeStaggerIn(
                id: collab.id,
                child: _Row(collab: collab, onTap: () => onOpen(collab)),
              ),
              const Divider(height: 1, color: MutandeColors.stone200),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: _Head('Collab')),
          Expanded(flex: 2, child: _Head('Open')),
          Expanded(flex: 2, child: _Head('Doing')),
          Expanded(flex: 2, child: _Head('Needs you')),
          Expanded(flex: 2, child: _Head('Updated', alignEnd: true)),
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
  const _Row({required this.collab, required this.onTap});

  final CollabSummary collab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('collab-row-${collab.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
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
                    if (collab.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MutandeColors.emeraldSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: MutandeColors.emerald,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(flex: 2, child: _Cell('${collab.openCount}')),
              Expanded(flex: 2, child: _Cell('${collab.doingCount}')),
              Expanded(
                flex: 2,
                child: _Cell(
                  '${collab.needsYouCount}',
                  emphasis: collab.needsYouCount > 0,
                ),
              ),
              Expanded(
                flex: 2,
                child: _Cell(
                  formatRelativeTime(collab.updatedAt),
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.alignEnd = false, this.emphasis = false});

  final String text;
  final bool alignEnd;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 12,
        fontWeight: emphasis ? FontWeight.w600 : FontWeight.w500,
        color: emphasis ? MutandeColors.amber : MutandeColors.stone600,
      ),
    );
  }
}
