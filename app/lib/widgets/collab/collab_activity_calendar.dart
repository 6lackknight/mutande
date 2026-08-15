import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import 'collab_dash_card.dart';

/// Git-style heatmap of card `updated_at` counts across all collabs.
class CollabActivityCalendar extends StatelessWidget {
  const CollabActivityCalendar({
    super.key,
    required this.activity,
    this.now,
  });

  final List<CollabActivityDay> activity;
  final DateTime? now;

  static const _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      for (final day in activity)
        if (day.date.isNotEmpty) day.date: day.count,
    };
    final cells = _cells(now ?? DateTime.now().toUtc());
    return CollabDashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Card updates across all collabs',
            style: TextStyle(fontSize: 11, color: MutandeColors.stone500),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 3.0;
              const labelWidth = 28.0;
              final gridWidth = (constraints.maxWidth - labelWidth).clamp(
                80.0,
                double.infinity,
              );
              final cell =
                  ((gridWidth - gap * (_weeks - 1)) / _weeks).clamp(7.0, 14.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        for (var i = 0; i < 7; i++) ...[
                          if (i > 0) const SizedBox(height: gap),
                          SizedBox(
                            height: cell,
                            child: Text(
                              const ['', 'M', '', 'W', '', 'F', ''][i],
                              style: const TextStyle(
                                fontSize: 9,
                                color: MutandeColors.stone400,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Row(
                      children: [
                        for (var w = 0; w < _weeks; w++) ...[
                          if (w > 0) const SizedBox(width: gap),
                          Column(
                            children: [
                              for (var d = 0; d < 7; d++) ...[
                                if (d > 0) const SizedBox(height: gap),
                                _Cell(
                                  date: cells[w * 7 + d],
                                  count: counts[cells[w * 7 + d]] ?? 0,
                                  size: cell,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 12 Sunday-aligned weeks ending this week (UTC).
  static List<String> _cells(DateTime utcNow) {
    final today = DateTime.utc(utcNow.year, utcNow.month, utcNow.day);
    final sundayOffset = today.weekday % 7; // Sun=0 … Sat=6
    final thisSunday = today.subtract(Duration(days: sundayOffset));
    final start = thisSunday.subtract(const Duration(days: 7 * (_weeks - 1)));
    return [
      for (var i = 0; i < _weeks * 7; i++)
        _key(start.add(Duration(days: i))),
    ];
  }

  static String _key(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.date,
    required this.count,
    required this.size,
  });

  final String date;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = count == 0
        ? '$date · no updates'
        : '$date · $count ${count == 1 ? 'update' : 'updates'}';
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 250),
      child: SizedBox(
        key: Key('collab-cal-$date'),
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _heat(count),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  static Color _heat(int count) {
    if (count <= 0) return MutandeColors.stone200;
    if (count == 1) return const Color(0xFFE8D5C4);
    if (count <= 3) return MutandeColors.amberSoft;
    return MutandeColors.bronze;
  }
}
