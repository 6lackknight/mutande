import 'package:flutter/material.dart';

import '../models/agent_transport.dart';
import '../theme/mutande_macos_theme.dart';

/// Quiet "via web" / "via sidecar" chip — social attribution style.
class TransportChip extends StatelessWidget {
  const TransportChip({
    super.key,
    required this.transport,
    this.compact = false,
    this.active = false,
    this.lastSeen,
  });

  final AgentTransport transport;
  final bool compact;

  /// Capability freshness (§5.1) — soft "active now" cue when true.
  final bool active;
  final DateTime? lastSeen;

  /// Hide when transport unknown (pre-L1 API).
  static Widget? maybe({
    AgentTransport? transport,
    bool compact = false,
    DateTime? lastSeen,
    DateTime? now,
    Key? key,
  }) {
    if (transport == null) return null;
    return TransportChip(
      key: key,
      transport: transport,
      compact: compact,
      active: isCapabilityFresh(lastSeen, now: now),
      lastSeen: lastSeen,
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = transport.chipLabel;
    final fg = transport == AgentTransport.mcp
        ? MutandeColors.amber
        : MutandeColors.stone600;
    final bg = transport == AgentTransport.mcp
        ? MutandeColors.amberSoft
        : MutandeColors.stone100;
    final border = transport == AgentTransport.mcp
        ? MutandeColors.amber.withValues(alpha: 0.22)
        : MutandeColors.stone200;

    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 5 : 999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Container(
                width: compact ? 5 : 6,
                height: compact ? 5 : 6,
                decoration: const BoxDecoration(
                  color: MutandeColors.emerald,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: compact ? 4 : 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                height: 1.15,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );

    final tip = StringBuffer(label);
    if (active) {
      tip.write(' · active now');
    } else if (lastSeen != null) {
      tip.write(' · last seen ${_formatLastSeen(lastSeen!)}');
    }
    return Tooltip(
      message: tip.toString(),
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }

  static String _formatLastSeen(DateTime at) {
    final local = at.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Compose persistent badge for non-E2E routes (§6.5.1).
class ComposeNonE2eChip extends StatelessWidget {
  const ComposeNonE2eChip({super.key, required this.warning});

  final ComposeTransportWarning warning;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MutandeColors.amberSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: MutandeColors.amber.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          warning.label,
          style: const TextStyle(
            color: MutandeColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
