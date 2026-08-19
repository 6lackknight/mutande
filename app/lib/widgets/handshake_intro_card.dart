import 'package:flutter/material.dart';

import '../models/handshake_card.dart';
import '../theme/mutande_macos_theme.dart';

/// Skills / model / tools under a handshake body — one quiet line, no labels.
class HandshakeExtrasLine extends StatelessWidget {
  const HandshakeExtrasLine(this.card, {super.key});

  final HandshakeCardView card;

  @override
  Widget build(BuildContext context) {
    final line = card.extrasLine;
    if (line.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        line,
        style: const TextStyle(
          fontSize: 11,
          height: 1.35,
          color: MutandeColors.stone400,
        ),
      ),
    );
  }
}
