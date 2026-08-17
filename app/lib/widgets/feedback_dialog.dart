import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import 'mutande_sheet.dart';
import 'thinking_orb.dart';

Future<void> showFeedbackDialog({
  required BuildContext context,
  required DaemonClient daemon,
  required String appVersion,
  Rect? origin,
}) {
  return showMutandeSheet<void>(
    context: context,
    barrierLabel: 'Feedback',
    origin: origin,
    width: 480,
    height: 420,
    child: FeedbackDialog(daemon: daemon, appVersion: appVersion),
  );
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    super.key,
    required this.daemon,
    required this.appVersion,
  });

  final DaemonClient daemon;
  final String appVersion;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a short note first.');
      return;
    }
    if (message.length > 4000) {
      setState(() => _error = 'Keep feedback under 4,000 characters.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await widget.daemon.submitFeedback(
        message: message,
        category: 'pilot',
        appVersion: widget.appVersion,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = friendlyDaemonError(e, what: 'Feedback');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: MutandeColors.stone50,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _close,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Feedback',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: MutandeColors.stone800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'esc',
                      style: TextStyle(
                        color: MutandeColors.stone400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us what broke or felt off. Goes to the mutande team — not into threads.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: MutandeColors.stone500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: null,
                    maxLines: null,
                    expands: true,
                    maxLength: 4000,
                    enabled: !_sending,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) {
                      if (_sent || _error != null) {
                        setState(() {
                          _sent = false;
                          _error = null;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'e.g. Connect hosts failed on Claude…',
                      counterText: '',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ],
                if (_sent) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sent — thank you.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF166534),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const MutandeOrb.loading(semanticLabel: 'Sending…')
                        : const Text('Send feedback'),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
