import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Calm Approve/Deny strip for L5 E2E → app_envelope downgrade consent (§6.5).
class DowngradeConsentBanner extends StatelessWidget {
  const DowngradeConsentBanner({
    super.key,
    required this.prompt,
    this.detail,
    this.busy = false,
    this.onApprove,
    this.onDeny,
  });

  final String prompt;
  /// Extra line under the prompt. Null hides it (task gates).
  final String? detail;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prompt,
              style: const TextStyle(
                color: Color(0xFF44403C),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            if (detail != null) ...[
              Text(
                detail!,
                style: TextStyle(
                  color: MutandeColors.stone500,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
            ] else
              const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: busy ? null : onDeny,
                  child: const Text('Deny'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
