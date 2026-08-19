import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../services/first_run_gates.dart';
import '../services/first_run_store.dart';
import '../services/host_composer_launch.dart';
import '../theme/mutande_macos_theme.dart';
import '../widgets/onboarding_address_rail.dart';
import '../widgets/onboarding_chrome.dart';
import '../widgets/thinking_orb.dart';

/// Debug-only: pins the wizard to one state so the flow can be walked without
/// a real reply.
enum PingPreview { copy, waiting, delivered, timeout }

/// Opens a host composer with the handshake prompt (copy as fallback), then
/// waits for the other agent to publish a handshake. Skip does not exist —
/// a handshake reply is the only way through.
///
/// The notification ask rides along with the wait.
class FirstRunPingWizard extends StatefulWidget {
  const FirstRunPingWizard({
    super.key,
    required this.daemon,
    required this.firstRunStore,
    required this.onComplete,
    required this.target,
    this.address = const OnboardingAddress(),
    this.debugBanner,
    this.preview,
    this.openComposer,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final ValueChanged<String?> onComplete;
  final OnboardingAddress address;
  final String? debugBanner;

  /// `@claude` or `orinea@tbhco` — the recipient that is not the sending agent.
  final String target;

  /// Debug walkthrough: pin a state, skip polling, never auto-complete.
  final PingPreview? preview;

  /// Override host launch (tests). Defaults to [HostComposerLaunch.open].
  final Future<HostComposerOpenResult> Function({
    required String slug,
    required String prompt,
  })?
  openComposer;

  static String promptFor(String target) => firstRunHandshakePrompt(target);

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
  bool _opening = false;

  String get _prompt => FirstRunPingWizard.promptFor(widget.target);
  String? get _hostSlug => widget.address.agent;
  String? get _hostName => HostComposerLaunch.displayName(_hostSlug);
  bool get _canOpenHost => HostComposerLaunch.canPrefill(_hostSlug);

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
    await Clipboard.setData(ClipboardData(text: _prompt));
    if (!mounted) return;
    final host = _hostName ?? 'your AI host';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied — paste into $host')));
  }

  Future<void> _copyPromptQuiet() async {
    await Clipboard.setData(ClipboardData(text: _prompt));
  }

  Future<void> _openHost() async {
    if (_opening) return;
    setState(() => _opening = true);
    unawaited(_copyPromptQuiet());
    final slug = _hostSlug ?? '';
    final result = widget.openComposer != null
        ? await widget.openComposer!(slug: slug, prompt: _prompt)
        : await HostComposerLaunch.open(slug: slug, prompt: _prompt);
    if (!mounted) return;
    setState(() => _opening = false);
    switch (result) {
      case HostComposerOpenResult.prefilled:
        Analytics.track(AnalyticsEvent.pingOpen);
        _startWaiting();
      case HostComposerOpenResult.appOpened:
        Analytics.track(AnalyticsEvent.pingOpen);
        final host = _hostName ?? 'the host';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$host is open — paste the prompt (copied).')),
        );
      case HostComposerOpenResult.failed:
        final host = _hostName ?? 'the host';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn’t open $host — prompt copied. Paste it there.',
            ),
          ),
        );
    }
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
      final open = await widget.daemon.listThreads(
        filter: 'open',
        enrich: false,
      );
      final started = _waitStarted ?? DateTime.now();
      for (final summary in open) {
        if (!isFirstRunHandoffCandidate(
          summary: summary,
          waitStarted: started,
        )) {
          continue;
        }
        final ThreadDetailResult detail;
        try {
          detail = await widget.daemon.getThread(summary.id);
        } catch (e) {
          if (e is TimeoutException ||
              isTimeoutError(e.toString().toLowerCase())) {
            continue;
          }
          rethrow;
        }
        if (isFirstRunHandshakeReply(detail)) {
          _poll?.cancel();
          if (!mounted) return;
          setState(() {
            _step = _PingStep.success;
            _threadId = detail.id;
            _error = null;
          });
          Analytics.track(AnalyticsEvent.pingSuccess);
          await Future<void>.delayed(const Duration(milliseconds: 1600));
          await widget.firstRunStore.markPingComplete();
          if (!mounted) return;
          widget.onComplete(_threadId);
          return;
        }
      }
      if (!mounted) return;
      if (_error != null) setState(() => _error = null);
      if (DateTime.now().difference(started) > const Duration(minutes: 5)) {
        _poll?.cancel();
        Analytics.track(AnalyticsEvent.pingTimeout);
        setState(() => _step = _PingStep.timeout);
      }
    } catch (e) {
      if (!mounted) return;
      if (e is TimeoutException || isTimeoutError(e.toString().toLowerCase())) {
        return;
      }
      setState(() => _error = friendlyDaemonError(e, what: 'Threads'));
    } finally {
      _busy = false;
    }
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
          hostName: _hostName,
          hostSlug: _hostSlug,
          canOpen: _canOpenHost,
          opening: _opening,
          prompt: _prompt,
          onCopy: _copyPrompt,
          onOpen: _openHost,
          onWaiting: _startWaiting,
        ),
        _PingStep.waiting => _WaitingStep(
          error: _error,
          showBannerAsk: !_bannersAsked,
          bannersGranted: _bannersGranted,
          onAllowBanners: _allowBanners,
          onDeclineBanners: _declineBanners,
        ),
        _PingStep.success => const _SuccessStep(),
        _PingStep.timeout => _TimeoutStep(
          onRetry: () => setState(() => _step = _PingStep.copy),
        ),
      },
    );
  }
}

class _CopyStep extends StatelessWidget {
  const _CopyStep({
    required this.theme,
    required this.hostName,
    required this.hostSlug,
    required this.canOpen,
    required this.opening,
    required this.prompt,
    required this.onCopy,
    required this.onOpen,
    required this.onWaiting,
  });

  final ThemeData theme;
  final String? hostName;
  final String? hostSlug;
  final bool canOpen;
  final bool opening;
  final String prompt;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onWaiting;

  String get _title {
    if (canOpen && hostName != null) return 'Open this in $hostName.';
    if (hostSlug != null) return 'Paste this into $hostSlug.';
    return 'Paste this into your connected host.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: _title,
          subtitle:
              'They reply with a short intro — who they are, what they’re good at.',
        ),
        const SizedBox(height: OnboardingSpace.lg),
        Container(
          padding: const EdgeInsets.fromLTRB(OnboardingSpace.md, 10, 4, 10),
          decoration: BoxDecoration(
            color: MutandeColors.stone800,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  prompt,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Menlo',
                    color: MutandeColors.stone50,
                    height: 1.4,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy prompt',
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 16),
                color: MutandeColors.stone50,
                style: IconButton.styleFrom(
                  foregroundColor: MutandeColors.stone50,
                  hoverColor: MutandeColors.stone50.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.md,
          hugPrimary: true,
          primary: FilledButton(
            onPressed: opening ? null : (canOpen ? onOpen : onWaiting),
            child: Text(
              canOpen
                  ? (hostName == null ? 'Open host' : 'Open $hostName')
                  : 'I’ve pasted it — wait for the reply',
            ),
          ),
          secondary: canOpen
              ? TextButton(
                  onPressed: onWaiting,
                  child: const Text('I’ve pasted it — wait for the reply'),
                )
              : null,
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
  });

  final String? error;
  final bool showBannerAsk;
  final bool bannersGranted;
  final VoidCallback onAllowBanners;
  final VoidCallback onDeclineBanners;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: MutandeOrb.standard(semanticLabel: 'Waiting for reply'),
        ),
        const SizedBox(height: OnboardingSpace.lg),
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Waiting for their handshake…',
          subtitle:
              'The other agent should introduce itself on the thread. This screen '
              'watches Threads.',
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
            'Banners are on — the reply will announce itself.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: MutandeColors.stone500),
          ),
        ],
      ],
    );
  }
}

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

class _SuccessStep extends StatelessWidget {
  const _SuccessStep();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'they introduced themselves.',
          subtitle: 'Threads is where it lands from here.',
        ),
      ],
    );
  }
}

class _TimeoutStep extends StatelessWidget {
  const _TimeoutStep({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Still waiting for a reply',
          subtitle:
              'Make sure the other host opened the thread and used /handshake. '
              'A ping does not count.',
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.lg,
          primary: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
