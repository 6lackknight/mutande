import 'package:flutter/material.dart';

import '../services/daemon_errors.dart';

/// Distilled full-screen state when bootstrap cannot load session status.
class DaemonErrorScreen extends StatefulWidget {
  const DaemonErrorScreen({
    super.key,
    required this.error,
    required this.endpoint,
    this.daemonReachable = false,
    required this.onRetry,
    this.onRestartCourier,
  });

  final String error;
  final String endpoint;
  final bool daemonReachable;
  final VoidCallback onRetry;

  /// When set, shows a secondary action to stop and respawn mutande-core.
  final Future<void> Function()? onRestartCourier;

  @override
  State<DaemonErrorScreen> createState() => _DaemonErrorScreenState();
}

class _DaemonErrorScreenState extends State<DaemonErrorScreen> {
  bool _detailsOpen = false;
  bool _restarting = false;

  Future<void> _restart() async {
    final restart = widget.onRestartCourier;
    if (restart == null || _restarting) return;
    setState(() => _restarting = true);
    try {
      await restart();
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = classifyDaemonError(
      error: widget.error,
      daemonReachable: widget.daemonReachable,
    );
    final copy = daemonErrorCopy(kind, daemonReachable: widget.daemonReachable);
    final isWait = kind == DaemonErrorKind.keychainOrStarting;
    final accent = isWait ? const Color(0xFFB45309) : const Color(0xFF991B1B);
    final busy = _restarting;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  isWait ? Icons.lock_outline : Icons.cloud_off_outlined,
                  size: 44,
                  color: accent.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 28),
                Text(
                  'mutande',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 20),
                Text(
                  copy.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  copy.body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF57534E),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : widget.onRetry,
                    child: Text(busy ? 'Restarting…' : 'Retry'),
                  ),
                ),
                if (widget.onRestartCourier != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: busy ? null : _restart,
                      child: Text(
                        busy ? 'Restarting courier…' : 'Restart courier',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => _detailsOpen = !_detailsOpen),
                  child: Text(_detailsOpen ? 'Hide details' : 'Details'),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: _detailsOpen
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      'HTTP: ${widget.endpoint}\n\n${_scrubError(widget.error)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFA8A29E),
                            height: 1.4,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _scrubError(String raw) {
    var msg = raw;
    for (final prefix in ['DaemonException: ', 'Exception: ', 'ClientException: ']) {
      if (msg.startsWith(prefix)) {
        msg = msg.substring(prefix.length);
      }
    }
    return msg;
  }
}
