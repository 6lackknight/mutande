import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import '../../util/address_display.dart';
import '../../util/clock_format.dart';
import 'collab_dash_card.dart';

/// Git-style heatmap of card `updated_at` counts, with a latest-thread feed.
class CollabActivityCalendar extends StatelessWidget {
  const CollabActivityCalendar({
    super.key,
    required this.activity,
    this.recent = const [],
    this.myHandle,
    this.onOpenThread,
    this.now,
  });

  final List<CollabActivityDay> activity;
  final List<CollabRecentThread> recent;
  final String? myHandle;
  final ValueChanged<CollabRecentThread>? onOpenThread;
  final DateTime? now;

  static const _weeks = 12;
  static const _cell = 11.0;
  static const _cellMax = 14.0;
  static const _cellMin = 6.0;
  static const _gap = 3.0;
  static const _labelW = 22.0;
  static const _labelGap = 6.0;
  static const _feedMax = 5;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      for (final day in activity)
        if (day.date.isNotEmpty) day.date: day.count,
    };
    final cells = _cells(now ?? DateTime.now().toUtc());
    final feed = recent.take(_feedMax).toList();
    return CollabDashCard(
      height: kCollabChartCardHeight,
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
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SizedBox.expand(
                    key: const Key('collab-activity-heatmap-pane'),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Center(
                          child: _Heatmap(
                            counts: counts,
                            cells: cells,
                            cell: _cellFor(constraints),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox.expand(
                    key: const Key('collab-activity-feed-pane'),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: MutandeColors.stone200),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _ThreadFeed(
                          items: feed,
                          myHandle: myHandle,
                          now: now,
                          onOpen: onOpenThread,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _cellFor(BoxConstraints constraints) {
    final cellW =
        (constraints.maxWidth - _labelW - _labelGap - (_weeks - 1) * _gap) /
        _weeks;
    final cellH = (constraints.maxHeight - 6 * _gap) / 7;
    final raw = cellW < cellH ? cellW : cellH;
    if (raw.isInfinite || raw.isNaN) return _cell;
    return raw.clamp(_cellMin, _cellMax);
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

class _Heatmap extends StatelessWidget {
  const _Heatmap({
    required this.counts,
    required this.cells,
    required this.cell,
  });

  final Map<String, int> counts;
  final List<String> cells;
  final double cell;

  @override
  Widget build(BuildContext context) {
    const gap = CollabActivityCalendar._gap;
    const weeks = CollabActivityCalendar._weeks;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: CollabActivityCalendar._labelW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        const SizedBox(width: CollabActivityCalendar._labelGap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var w = 0; w < weeks; w++) ...[
              if (w > 0) const SizedBox(width: gap),
              Column(
                mainAxisSize: MainAxisSize.min,
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
      ],
    );
  }
}

class _ThreadFeed extends StatelessWidget {
  const _ThreadFeed({
    required this.items,
    this.myHandle,
    this.now,
    this.onOpen,
  });

  final List<CollabRecentThread> items;
  final String? myHandle;
  final DateTime? now;
  final ValueChanged<CollabRecentThread>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      primary: false,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return _FeedRow(
          item: item,
          myHandle: myHandle,
          now: now,
          onTap: onOpen == null ? null : () => onOpen!(item),
        );
      },
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.item,
    this.myHandle,
    this.now,
    this.onTap,
  });

  final CollabRecentThread item;
  final String? myHandle;
  final DateTime? now;
  final VoidCallback? onTap;

  String get _title {
    final subject = item.lastSubject?.trim();
    if (subject != null && subject.isNotEmpty) return subject;
    if (item.audience.trim().isNotEmpty) {
      return formatMailAddress(item.audience, myHandle: myHandle);
    }
    return 'Card';
  }

  String get _meta {
    final who = item.from.trim().isEmpty
        ? ''
        : formatMailAddress(item.from, myHandle: myHandle);
    final collab = item.collabName.trim().toLowerCase();
    if (who.isNotEmpty && collab.isNotEmpty) return '$who · $collab';
    if (who.isNotEmpty) return who;
    return collab;
  }

  @override
  Widget build(BuildContext context) {
    final time = formatRelativeTime(item.updatedAt, now: now);
    return Material(
      key: Key('collab-activity-thread-${item.threadId}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: MutandeColors.stone100,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 8,
                child: item.needsYou
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: MutandeColors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: item.needsYou
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: MutandeColors.stone800,
                        height: 1.2,
                      ),
                    ),
                    if (_meta.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        _meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: MutandeColors.stone400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MutandeColors.stone400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
