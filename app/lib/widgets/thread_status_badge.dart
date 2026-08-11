import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Coordination status for a thread inbox row / detail.
enum ThreadStatusKind {
  /// Outstanding human decision (approval / verify / question to you).
  needsYou,
  waiting,
  open,
  closed,
}

extension ThreadStatusKindX on ThreadStatusKind {
  String get label => switch (this) {
        ThreadStatusKind.needsYou => 'Needs you',
        ThreadStatusKind.waiting => 'Waiting',
        ThreadStatusKind.open => 'Open',
        ThreadStatusKind.closed => 'Closed',
      };

  /// Derive from hub `status` + daemon `your_status`.
  ///
  /// On the Mac UI, daemon sets `pending` only for unanswered human decisions
  /// (not agent-to-agent waiting).
  static ThreadStatusKind resolve({
    required String status,
    String? yourStatus,
  }) {
    // Closed wins over pending.
    if (status == 'closed') return ThreadStatusKind.closed;
    if (yourStatus == 'pending') return ThreadStatusKind.needsYou;
    if (yourStatus == 'replied') return ThreadStatusKind.waiting;
    return ThreadStatusKind.open;
  }
}

/// Quiet status badge — soft plate + ink, amber for pending.
class ThreadStatusBadge extends StatelessWidget {
  const ThreadStatusBadge({
    super.key,
    required this.kind,
    this.compact = false,
  });

  final ThreadStatusKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // List pane: plain amber text (Penpot Threads), no plate.
    if (compact && kind == ThreadStatusKind.needsYou) {
      return Text(
        kind.label,
        style: const TextStyle(
          color: MutandeColors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      );
    }

    final (fg, bg, border) = switch (kind) {
      ThreadStatusKind.needsYou => (
          MutandeColors.amber,
          MutandeColors.amberSoft,
          MutandeColors.amber.withValues(alpha: 0.22),
        ),
      ThreadStatusKind.open => (
          MutandeColors.emerald,
          MutandeColors.emeraldSoft,
          MutandeColors.emerald.withValues(alpha: 0.18),
        ),
      // Soft bronze — distinct from Closed (quiet stone) and Needs you (amber).
      ThreadStatusKind.waiting => (
          MutandeColors.bronze,
          MutandeColors.bronzeSoft,
          MutandeColors.bronze.withValues(alpha: 0.18),
        ),
      ThreadStatusKind.closed => (
          MutandeColors.stone500,
          MutandeColors.stone100,
          MutandeColors.stone200,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 5 : 6),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 3,
        ),
        child: Text(
          kind.label,
          style: TextStyle(
            color: fg,
            fontSize: compact ? 10.5 : 11.5,
            fontWeight: FontWeight.w600,
            height: 1.15,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
