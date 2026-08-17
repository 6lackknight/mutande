import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import '../thread_skeletons.dart';
import 'collab_dash_card.dart';

/// Open-card mix across Backlog / Doing / Done.
class CollabLaneDonut extends StatelessWidget {
  const CollabLaneDonut({super.key, required this.lanes});

  final CollabLaneTotals lanes;

  @override
  Widget build(BuildContext context) {
    final total = lanes.open;
    return CollabDashCard(
      height: kCollabChartCardHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lanes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Open cards by lane',
            style: TextStyle(fontSize: 11, color: MutandeColors.stone500),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                MutandeArrive(
                  order: 0,
                  child: SizedBox(
                    width: 108,
                    height: 108,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: MutandeMotion.of(
                        context,
                        const Duration(milliseconds: 520),
                      ),
                      curve: MutandeMotion.easeOut,
                      builder: (context, progress, child) {
                        return CustomPaint(
                          painter: _DonutPainter(
                            backlog: lanes.backlog,
                            doing: lanes.doing,
                            done: lanes.done,
                            progress: progress,
                          ),
                          child: child,
                        );
                      },
                      child: Center(
                        child: Text(
                          total == 0 ? '—' : '$total',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: MutandeColors.stone800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MutandeArrive(
                        order: 1,
                        child: _Legend(
                          color: MutandeColors.stone400,
                          label: 'Backlog',
                          count: lanes.backlog,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MutandeArrive(
                        order: 2,
                        child: _Legend(
                          color: MutandeColors.bronze,
                          label: 'Doing',
                          count: lanes.doing,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MutandeArrive(
                        order: 3,
                        child: _Legend(
                          color: MutandeColors.stone800,
                          label: 'Done',
                          count: lanes.done,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: MutandeColors.stone600,
            ),
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: MutandeColors.stone800,
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.backlog,
    required this.doing,
    required this.done,
    this.progress = 1,
  });

  final int backlog;
  final int doing;
  final int done;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt;
    final total = backlog + doing + done;
    if (total == 0) {
      paint.color = MutandeColors.stone200;
      canvas.drawArc(inset, 0, math.pi * 2 * progress, false, paint);
      return;
    }
    final sweepCap = math.pi * 2 * progress;
    var start = -math.pi / 2;
    var remaining = sweepCap;
    void slice(int n, Color color) {
      if (n <= 0 || remaining <= 0) return;
      final sliceSweep = math.pi * 2 * n / total;
      final sweep = sliceSweep < remaining ? sliceSweep : remaining;
      paint.color = color;
      if (sweep > 0.01) {
        canvas.drawArc(inset, start, sweep - 0.02, false, paint);
      }
      start += sliceSweep;
      remaining -= sliceSweep;
    }

    slice(backlog, MutandeColors.stone400);
    slice(doing, MutandeColors.bronze);
    slice(done, MutandeColors.stone800);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) {
    return old.backlog != backlog ||
        old.doing != doing ||
        old.done != done ||
        old.progress != progress;
  }
}
