import 'package:flutter/material.dart';

import '../models/agent_transport.dart';
import '../theme/mutande_macos_theme.dart';

/// Persistent calm warning for enterprise-participant threads (§7.2).
class EnterpriseWarnBanner extends StatelessWidget {
  const EnterpriseWarnBanner({
    super.key,
    this.message = kEnterpriseWarnBannerMessage,
  });

  final String message;

  /// Hide when [show] is false.
  static Widget? maybe({required bool show, String? message, Key? key}) {
    if (!show) return null;
    return EnterpriseWarnBanner(
      key: key,
      message: message ?? kEnterpriseWarnBannerMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MutandeColors.bronzeSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: MutandeColors.bronze.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 16,
              color: MutandeColors.bronze,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: MutandeColors.bronze,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
