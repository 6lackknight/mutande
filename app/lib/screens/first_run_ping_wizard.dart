import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../services/first_run_store.dart';
import '../widgets/thinking_orb.dart';

/// Copy-paste prompt for first thread ping; polls until a pong reply lands.
class FirstRunPingWizard extends StatefulWidget {
  const FirstRunPingWizard({
    super.key,
    required this.daemon,
    required this.firstRunStore,
    required this.onComplete,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final ValueChanged<String?> onComplete;

  static const prompt = 'Use mutande to ping @all (thread)';

  @override
  State<FirstRunPingWizard> createState() => _FirstRunPingWizardState();
}

enum _PingStep { copy, waiting, success, timeout }

class _FirstRunPingWizardState extends State<FirstRunPingWizard> {
  _PingStep _step = _PingStep.copy;
  Timer? _poll;
  DateTime? _waitStarted;
  String? _threadId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(
      const ClipboardData(text: FirstRunPingWizard.prompt),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied — paste into your AI host')),
    );
  }

  void _startWaiting() {
    _poll?.cancel();
    setState(() {
      _step = _PingStep.waiting;
      _waitStarted = DateTime.now();
      _error = null;
      _busy = false;
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final open = await widget.daemon.listThreads(filter: 'open');
      for (final summary in open) {
        final detail = await widget.daemon.getThread(summary.id);
        if (_isThreadPingWithPong(detail)) {
          _poll?.cancel();
          if (!mounted) return;
          setState(() {
            _step = _PingStep.success;
            _threadId = detail.id;
          });
          await Future<void>.delayed(const Duration(milliseconds: 900));
          await widget.firstRunStore.markPingComplete();
          if (!mounted) return;
          widget.onComplete(_threadId);
          return;
        }
      }
      final started = _waitStarted;
      if (started != null &&
          DateTime.now().difference(started) > const Duration(minutes: 5)) {
        _poll?.cancel();
        if (!mounted) return;
        setState(() => _step = _PingStep.timeout);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _busy = false;
    }
  }

  bool _isThreadPingWithPong(ThreadDetailResult detail) {
    if (detail.messages.isEmpty) return false;
    final roots = detail.messages
        .where((m) => m.parentMessageId == null && m.inReplyTo == null)
        .toList();
    final root = roots.isNotEmpty ? roots.first : detail.messages.first;
    if (root.pingKind != 'thread') return false;
    // Any later message counts as pong (agent reply or auto).
    return detail.messages.any((m) => m.id != root.id);
  }

  Future<void> _skip() async {
    _poll?.cancel();
    await widget.firstRunStore.markPingComplete();
    widget.onComplete(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: switch (_step) {
                _PingStep.copy => _CopyStep(
                    theme: theme,
                    onCopy: _copyPrompt,
                    onWaiting: _startWaiting,
                    onSkip: _skip,
                  ),
                _PingStep.waiting => _WaitingStep(
                    theme: theme,
                    error: _error,
                    onSkip: _skip,
                  ),
                _PingStep.success => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Pong received',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your first thread is live.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF78716C),
                        ),
                      ),
                    ],
                  ),
                _PingStep.timeout => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Still waiting for a pong',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Paste the prompt in your host again, or skip and try from Threads later.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF78716C),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _startWaiting,
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        onPressed: _skip,
                        child: const Text('Skip for now'),
                      ),
                    ],
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyStep extends StatelessWidget {
  const _CopyStep({
    required this.theme,
    required this.onCopy,
    required this.onWaiting,
    required this.onSkip,
  });

  final ThemeData theme;
  final VoidCallback onCopy;
  final VoidCallback onWaiting;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Send your first ping',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF292524),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Paste this into your connected AI host. One host is enough — @all reaches other agents when you add more.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF78716C),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1917),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            FirstRunPingWizard.prompt,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Menlo',
              color: const Color(0xFFFAFAF9),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy prompt'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onWaiting,
          child: const Text('I’ve pasted it — wait for pong'),
        ),
        TextButton(
          onPressed: onSkip,
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}

class _WaitingStep extends StatelessWidget {
  const _WaitingStep({
    required this.theme,
    required this.error,
    required this.onSkip,
  });

  final ThemeData theme;
  final String? error;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MutandeOrb.standard(semanticLabel: 'Waiting for pong'),
        const SizedBox(height: 20),
        Text(
          'Waiting for pong…',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your agent should call ping, then reply on the thread. This screen watches Threads.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF78716C),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF991B1B),
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: onSkip,
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}
