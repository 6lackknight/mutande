import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Calm empty / error state for Threads · Collab · Network panes.
///
/// Title + short body; optional Retry. Never a place for raw exceptions.
class PaneQuietState extends StatelessWidget {
  const PaneQuietState({
    super.key,
    required this.title,
    this.body,
    this.onRetry,
    this.onRetryOrigin,
    this.retryLabel = 'Retry',
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? body;
  final VoidCallback? onRetry;

  /// When set, Retry captures the button rect (for from-control sheets).
  final void Function(Rect? origin)? onRetryOrigin;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 28,
                color: MutandeColors.stone400.withValues(alpha: 0.9),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.titleSmall?.copyWith(
                  color: MutandeColors.stone600,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              if (body != null && body!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.bodySmall?.copyWith(
                    color: MutandeColors.stone400,
                    height: 1.4,
                  ),
                ),
              ],
              if (onRetry != null || onRetryOrigin != null) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (btnCtx) {
                    return OutlinedButton(
                      onPressed: () {
                        if (onRetryOrigin != null) {
                          final box = btnCtx.findRenderObject() as RenderBox?;
                          final origin = (box != null && box.hasSize)
                              ? box.localToGlobal(Offset.zero) & box.size
                              : null;
                          onRetryOrigin!(origin);
                          return;
                        }
                        onRetry?.call();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MutandeColors.bronze,
                        side: BorderSide(
                          color: MutandeColors.bronze.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size(88, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: Text(retryLabel),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact inline notice — hugs copy, stone capsule, ink Retry pill.
///
/// Never a full-width Material error bar. Last-known content stays visible.
class PaneInlineError extends StatelessWidget {
  const PaneInlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MutandeColors.stone50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MutandeColors.stone200),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 6, onRetry != null ? 6 : 14, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  message,
                  style: text.bodySmall?.copyWith(
                    color: MutandeColors.stone600,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (onRetry != null)
                  FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: MutandeColors.stone800,
                      foregroundColor: MutandeColors.stone50,
                      minimumSize: const Size(44, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(retryLabel),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
