import 'package:flutter/material.dart';

import '../models/handshake_card.dart';
import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'ai_host_icon.dart';
import 'handshake_intro_card.dart';
import 'onboarding_chrome.dart';
import 'thread_message_tree.dart';
import 'thread_skeletons.dart';

/// Read-only thread for the first-handshake letterhead — no composer.
class HandshakeThreadPane extends StatelessWidget {
  const HandshakeThreadPane({
    super.key,
    this.detail,
    this.myHandle,
    this.success = false,
  });

  final ThreadDetailResult? detail;
  final String? myHandle;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final d = detail;
    if (d == null || d.messages.isEmpty) {
      return const ThreadReadingSkeleton();
    }
    final nodes = flattenThreadMessages(d.messages);
    final subject = d.messages
        .map((m) => m.bundleSubject?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .firstOrNull;

    return ColoredBox(
      color: MutandeColors.stone50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OnboardingSpace.lg,
              OnboardingSpace.lg,
              OnboardingSpace.lg,
              OnboardingSpace.sm,
            ),
            child: Text(
              subject == null || subject.isEmpty
                  ? (success ? 'Handshake landed' : 'Thread')
                  : subject,
              style: theme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: MutandeColors.stone800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                OnboardingSpace.lg,
                0,
                OnboardingSpace.lg,
                OnboardingSpace.xl,
              ),
              itemCount: nodes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                return _HandshakeMessage(
                  message: nodes[i].message,
                  myHandle: myHandle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HandshakeMessage extends StatelessWidget {
  const _HandshakeMessage({required this.message, this.myHandle});

  final ThreadMessageView message;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final from = formatMailAddress(message.fromHandle, myHandle: myHandle);
    final slash = message.fromHandle.lastIndexOf('/');
    final host = slash >= 0 && slash < message.fromHandle.length - 1
        ? message.fromHandle.substring(slash + 1).toLowerCase()
        : '';
    final card = HandshakeCardView.resolve(
      handshake: message.handshake,
      notes: message.bundleNotes,
    );
    final notes = message.bundleNotes?.trim();
    final prose =
        notes != null &&
            notes.isNotEmpty &&
            !HandshakeCardView.notesAreDump(notes)
        ? notes
        : null;
    final body =
        prose ??
        (card != null && card.leadSentence.isNotEmpty
            ? card.leadSentence
            : message.displayBody.trim());
    final showBody = body.isNotEmpty && body != 'No message body';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (host.isNotEmpty)
          AiHostIcon(host, size: 22)
        else
          CircleAvatar(
            radius: 11,
            backgroundColor: MutandeColors.stone200,
            foregroundColor: MutandeColors.stone800,
            child: Text(
              personInitials(personDisplayTitle(handle: message.fromHandle)),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      from,
                      style: theme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: MutandeColors.stone800,
                      ),
                    ),
                  ),
                  if (message.hasHandshake || card != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      'handshake',
                      style: theme.labelSmall?.copyWith(
                        color: MutandeColors.amber,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ],
              ),
              if (showBody) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.bodySmall?.copyWith(
                    color: MutandeColors.stone600,
                    height: 1.45,
                  ),
                ),
              ],
              if (card != null) HandshakeExtrasLine(card),
            ],
          ),
        ),
      ],
    );
  }
}
