import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/first_run_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../widgets/onboarding_address_rail.dart';
import '../widgets/onboarding_chrome.dart';
import '../widgets/thinking_orb.dart';

/// Debug-only: pins the wizard to one state so the flow can be walked without
/// a real pong.
enum PingPreview { copy, waiting, delivered, timeout }

/// Final onboarding step: copy the prompt, wait for the pong, take delivery.
///
/// The notification ask rides along with the wait — it's motivated there
/// ("we'll tell you the moment it lands") and the arriving pong proves it works.
class FirstRunPingWizard extends StatefulWidget {
  const FirstRunPingWizard({
    super.key,
    required this.daemon,
    required this.firstRunStore,
    required this.onComplete,
    this.address = const OnboardingAddress(),
    this.debugBanner,
    this.preview,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final ValueChanged<String?> onComplete;
  final OnboardingAddress address;
  final String? debugBanner;

  /// Debug walkthrough: pin a state, skip polling, never auto-complete.
  final PingPreview? preview;

  static const prompt = 'Use mutande to ping @all (thread)';

  @override
  State<FirstRunPingWizard> createState() => _FirstRunPingWizardState();
}

enum _PingStep { copy, waiting, success, timeout }

class _FirstRunPingWizardState extends State<FirstRunPingWizard> {
  late _PingStep _step = _previewStep(widget.preview) ?? _PingStep.copy;
  Timer? _poll;
  DateTime? _waitStarted;
  String? _threadId;
  String? _error;
  bool _busy = false;
  late bool _bannersAsked = widget.firstRunStore.notificationsComplete;
  bool _bannersGranted = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(FirstRunPingWizard old) {
    super.didUpdateWidget(old);
    if (widget.preview == old.preview) return;
    final pinned = _previewStep(widget.preview);
    if (pinned == null) return;
    _poll?.cancel();
    setState(() => _step = pinned);
  }

  static _PingStep? _previewStep(PingPreview? preview) => switch (preview) {
    null => null,
    PingPreview.copy => _PingStep.copy,
    PingPreview.waiting => _PingStep.waiting,
    PingPreview.delivered => _PingStep.success,
    PingPreview.timeout => _PingStep.timeout,
  };

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
    if (widget.preview != null) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final open = await widget.daemon.listThreads(filter: 'open');
      for (final summary in open) {
        if (_isStale(summary)) continue;
        final detail = await widget.daemon.getThread(summary.id);
        if (_isThreadPingWithPong(detail)) {
          _poll?.cancel();
          if (!mounted) return;
          setState(() {
            _step = _PingStep.success;
            _threadId = detail.id;
          });
          Analytics.track(AnalyticsEvent.pingSuccess);
          // Let the delivery sweep land before handing over to Threads.
          await Future<void>.delayed(const Duration(milliseconds: 1600));
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

  /// Skips the detail fetch for threads that can't be this ping. Slack covers
  /// a ping sent before the user pressed wait.
  bool _isStale(ThreadSummary summary) {
    final started = _waitStarted;
    final updated = DateTime.tryParse(summary.updatedAt ?? '');
    if (started == null || updated == null) return false;
    return updated.isBefore(started.subtract(const Duration(minutes: 5)));
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

  Future<void> _allowBanners() async {
    if (Platform.isMacOS) {
      try {
        await Process.run('open', [
          'x-apple.systempreferences:com.apple.Notifications-Settings.extension',
        ]);
      } catch (_) {}
    }
    await widget.firstRunStore.markNotificationsComplete();
    if (!mounted) return;
    setState(() {
      _bannersAsked = true;
      _bannersGranted = true;
    });
  }

  Future<void> _declineBanners() async {
    await widget.firstRunStore.markNotificationsComplete(skipped: true);
    if (!mounted) return;
    setState(() => _bannersAsked = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingShell(
      step: OnboardingStep.ping,
      address: widget.address,
      delivered: _step == _PingStep.success,
      debugBanner: widget.debugBanner,
      child: switch (_step) {
        _PingStep.copy => _CopyStep(
          theme: theme,
          agent: widget.address.agent,
          onCopy: _copyPrompt,
          onWaiting: _startWaiting,
          onSkip: _skip,
        ),
        _PingStep.waiting => _WaitingStep(
          error: _error,
          showBannerAsk: !_bannersAsked,
          bannersGranted: _bannersGranted,
          onAllowBanners: _allowBanners,
          onDeclineBanners: _declineBanners,
          onSkip: _skip,
        ),
        _PingStep.success => const _SuccessStep(),
        _PingStep.timeout => _TimeoutStep(
          onRetry: () => setState(() => _step = _PingStep.copy),
          onSkip: _skip,
        ),
      },
    );
  }
}

class _CopyStep extends StatelessWidget {
  const _CopyStep({
    required this.theme,
    required this.agent,
    required this.onCopy,
    required this.onWaiting,
    required this.onSkip,
  });

  final ThemeData theme;
  final String? agent;
  final VoidCallback onCopy;
  final VoidCallback onWaiting;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: agent == null
              ? 'Paste this into your connected host.'
              : 'Paste this into $agent.',
          subtitle: 'Your address takes it from there.',
        ),
        const SizedBox(height: OnboardingSpace.lg),
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
          secondary: TextButton(
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
    required this.error,
    required this.showBannerAsk,
    required this.bannersGranted,
    required this.onAllowBanners,
    required this.onDeclineBanners,
    required this.onSkip,
  });

  final String? error;
  final bool showBannerAsk;
  final bool bannersGranted;
  final VoidCallback onAllowBanners;
  final VoidCallback onDeclineBanners;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: MutandeOrb.standard(semanticLabel: 'Waiting for pong'),
        ),
        const SizedBox(height: OnboardingSpace.lg),
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Waiting for pong…',
          subtitle:
              'Your agent should call ping, then reply on the thread. This '
              'screen watches Threads.',
        ),
        if (error != null) ...[
          const SizedBox(height: OnboardingSpace.sm),
          OnboardingErrorBanner(message: error!),
        ],
        if (showBannerAsk) ...[
          const SizedBox(height: OnboardingSpace.xl),
          _BannerAsk(onAllow: onAllowBanners, onDecline: onDeclineBanners),
        ] else if (bannersGranted) ...[
          const SizedBox(height: OnboardingSpace.lg),
          Text(
            'Banners are on — the pong will announce itself.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: MutandeColors.stone500),
          ),
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

/// The old Notify step, asked where the user is already waiting.
class _BannerAsk extends StatelessWidget {
  const _BannerAsk({required this.onAllow, required this.onDecline});

  final VoidCallback onAllow;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: MutandeColors.amberSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Banners on?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: MutandeColors.stone800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'We’ll tell you the moment your agent replies — even if you’re in '
            'another app. Metadata only, never message bodies.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: MutandeColors.stone600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: OnboardingSpace.sm),
          Row(
            children: [
              OutlinedButton(
                onPressed: onAllow,
                child: const Text('Turn on banners'),
              ),
              const SizedBox(width: OnboardingSpace.xs),
              TextButton(onPressed: onDecline, child: const Text('Not now')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Delivery — the rail above is playing the amber sweep as this lands.
class _SuccessStep extends StatelessWidget {
  const _SuccessStep();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'received its first mail.',
          subtitle: 'Threads is where it lands from here.',
        ),
      ],
    );
  }
}

class _TimeoutStep extends StatelessWidget {
  const _TimeoutStep({required this.onRetry, required this.onSkip});

  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Still waiting for a pong',
          subtitle: 'Make sure your host ran ping and replied on the thread.',
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.lg,
          primary: FilledButton(onPressed: onRetry, child: const Text('Retry')),
          tertiary: TextButton(
            onPressed: onSkip,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}
