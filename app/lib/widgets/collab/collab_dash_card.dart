import 'package:flutter/material.dart';

import '../../theme/mutande_macos_theme.dart';

/// Shared height for Collab home Activity and Lanes plates.
const kCollabChartCardHeight = 188.0;

/// Stone surface used by Collab home tiles, charts, and the projects table.
class CollabDashCard extends StatelessWidget {
  const CollabDashCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.height,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inner = onTap == null
        ? Padding(padding: padding, child: child)
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(padding: padding, child: child),
          );
    final card = Material(
      color: MutandeColors.stone50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MutandeColors.stone200),
      ),
      child: inner,
    );
    if (height == null) return card;
    return SizedBox(height: height, width: double.infinity, child: card);
  }
}
