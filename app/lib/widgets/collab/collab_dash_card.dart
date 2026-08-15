import 'package:flutter/material.dart';

import '../../theme/mutande_macos_theme.dart';

/// Stone surface used by Collab home tiles, charts, and the projects table.
class CollabDashCard extends StatelessWidget {
  const CollabDashCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: MutandeColors.stone50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MutandeColors.stone200),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(padding: padding, child: child),
            ),
    );
    return card;
  }
}
