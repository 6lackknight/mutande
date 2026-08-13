import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/first_run_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../widgets/onboarding_stepper.dart';
import '../widgets/thinking_orb.dart';

/// Copy-paste prompt for first thread ping; polls until a pong reply lands.
class FirstRunPingWizard extends StatefulWidget {
  const FirstRunPingWizard({
    super.key,
    required this.daemon,
    required this.firstRunStore,
    required this.onComplete,
    this.embedded = false,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final ValueChanged<String?> onComplete;
  final bool embedded;

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
    Analytics.track(AnalyticsEvent.pingCopy);
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
    Analytics.track(AnalyticsEvent.pingWaiting);
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
          Analytics.track(AnalyticsEvent.pingSuccess);
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
        Analytics.track(AnalyticsEvent.pingTimeout);
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
    Analytics.track(AnalyticsEvent.pingSkip);
    await widget.firstRunStore.markPingComplete();
    widget.onComplete(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = switch (_step) {
      _PingStep.copy => _CopyStep(
          theme: theme,
          embedded: widget.embedded,
          onCopy: _copyPrompt,
          onWaiting: _startWaiting,
          onSkip: _skip,
        ),
      _PingStep.waiting => _WaitingStep(
          theme: theme,
          embedded: widget.embedded,
          error: _error,
          onSkip: _skip,
        ),
      _PingStep.success => _SuccessStep(theme: theme, embedded: widget.embedded),
      _PingStep.timeout => _TimeoutStep(
          theme: theme,
          embedded: widget.embedded,
          onRetry: () => setState(() => _step = _PingStep.copy),
          onSkip: _skip,
        ),
    };

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: body,
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
    required this.embedded,
    required this.onCopy,
    required this.onWaiting,
    required this.onSkip,
  });

  final ThemeData theme;
  final bool embedded;
  final VoidCallback onCopy;
  final VoidCallback onWaiting;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final align = embedded ? TextAlign.left : TextAlign.center;
    return Column(
      mainAxisAlignment:
          embedded ? MainAxisAlignment.start : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embedded)
          const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Send your first ping',
            subtitle:
                'Paste this into your connected AI host. One host is enough — '
                '@all reaches other agents when you add more.',
          )
        else ...[
          Text(
            'Send your first ping',
            textAlign: align,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: OnboardingSpace.xs),
          Text(
            'Paste this into your connected AI host. One host is enough — @all reaches other agents when you add more.',
            textAlign: align,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: MutandeColors.stone500,
              height: 1.45,
            ),
          ),
        ],
        SizedBox(height: embedded ? OnboardingSpace.lg : 20),
        Container(
          padding: const EdgeInsets.all(OnboardingSpace.md),
          decoration: BoxDecoration(
            color: MutandeColors.stone800,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            FirstRunPingWizard.prompt,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Menlo',
              color: MutandeColors.stone50,
              height: 1.4,
            ),
          ),
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.md,
          primary: FilledButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy prompt'),
          ),
          secondary: OutlinedButton(
            onPressed: onWaiting,
            child: const Text('I’ve pasted it — wait for pong'),
          ),
          tertiary: TextButton(
            onPressed: onSkip,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}

class _WaitingStep extends StatelessWidget {
  const _WaitingStep({
    required this.theme,
    required this.embedded,
    required this.error,
    required this.onSkip,
  });

  final ThemeData theme;
  final bool embedded;
  final String? error;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment:
          embedded ? MainAxisAlignment.start : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: MutandeOrb.standard(semanticLabel: 'Waiting for pong'),
        ),
        SizedBox(height: embedded ? OnboardingSpace.lg : 20),
        if (embedded)
          const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Waiting for pong…',
            subtitle:
                'Your agent should call ping, then reply on the thread. '
                'This screen watches Threads.',
          )
        else ...[
          Text(
            'Waiting for pong…',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: OnboardingSpace.xs),
          Text(
            'Your agent should call ping, then reply on the thread. This screen watches Threads.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: MutandeColors.stone500,
              height: 1.4,
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: OnboardingSpace.sm),
          OnboardingErrorBanner(message: error!),
        ],
        OnboardingActions(
          topSpacing: OnboardingSpace.lg,
          tertiary: TextButton(
            onPressed: onSkip,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.theme, required this.embedded});

  final ThemeData theme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment:
          embedded ? MainAxisAlignment.start : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 48,
          color: MutandeColors.emerald,
        ),
        const SizedBox(height: OnboardingSpace.md),
        Text(
          'Pong received',
          textAlign: embedded ? TextAlign.left : TextAlign.center,
          style: OnboardingHeading.displayTitleStyle(theme).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: OnboardingSpace.xs),
        Text(
          'Your first thread is live.',
          textAlign: embedded ? TextAlign.left : TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: MutandeColors.stone500,
          ),
        ),
      ],
    );
  }
}

class _TimeoutStep extends StatelessWidget {
  const _TimeoutStep({
    required this.theme,
    required this.embedded,
    required this.onRetry,
    required this.onSkip,
  });

  final ThemeData theme;
  final bool embedded;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embedded)
          const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Still waiting for a pong',
            subtitle:
                'Make sure your host ran ping and replied on the thread.',
          )
        else ...[
          Text(
            'Still waiting for a pong',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: OnboardingSpace.sm),
          Text(
            'Make sure your host ran ping and replied on the thread.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: MutandeColors.stone500,
              height: 1.4,
            ),
          ),
        ],
        OnboardingActions(
          topSpacing: embedded ? OnboardingSpace.lg : 20,
          primary: FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
          tertiary: TextButton(
            onPressed: onSkip,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}
