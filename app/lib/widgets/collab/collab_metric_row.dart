import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import 'collab_dash_card.dart';

/// Four portfolio metrics plus a Create tile.
class CollabMetricRow extends StatelessWidget {
  const CollabMetricRow({
    super.key,
    required this.totals,
    required this.onCreate,
  });

  final CollabPortfolioTotals totals;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = <Widget>[
          _MetricTile(
            key: const Key('collab-metric-collabs'),
            label: 'Collabs',
            value: '${totals.collabs}',
            hint: 'you steer',
          ),
          _MetricTile(
            key: const Key('collab-metric-open'),
            label: 'Open cards',
            value: '${totals.open}',
            hint: 'across boards',
          ),
          _MetricTile(
            key: const Key('collab-metric-doing'),
            label: 'In Doing',
            value: '${totals.doing}',
            hint: 'in progress',
          ),
          _MetricTile(
            key: const Key('collab-metric-needs-you'),
            label: 'Needs you',
            value: '${totals.needsYou}',
            hint: 'awaiting a reply',
            accent: totals.needsYou > 0,
          ),
          _CreateTile(onTap: onCreate),
        ];
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        final half = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles) SizedBox(width: half, child: tile),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    this.accent = false,
  });

  final String label;
  final String value;
  final String hint;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final valueColor =
        accent ? MutandeColors.amber : MutandeColors.stone800;
    return CollabDashCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 11,
              color: MutandeColors.stone400,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('collab-create-tile'),
      child: CollabDashCard(
        onTap: onTap,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 22, color: MutandeColors.stone600),
            SizedBox(height: 8),
            Text(
              'New collab',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MutandeColors.stone800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
