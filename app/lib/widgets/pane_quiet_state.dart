import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Calm empty / error state for Threads · Agents · Contacts panes.
///
/// Title + short body; optional Retry. Never a place for raw exceptions.
class PaneQuietState extends StatelessWidget {
  const PaneQuietState({
    super.key,
    required this.title,
    this.body,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? body;
  final VoidCallback? onRetry;
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
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onRetry,
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
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact inline error under a header / compose form.
class PaneInlineError extends StatelessWidget {
  const PaneInlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF991B1B),
                    height: 1.35,
                  ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF991B1B),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
