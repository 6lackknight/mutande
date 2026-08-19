import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../models/agent_transport.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../services/first_run_gates.dart';
import '../services/first_run_store.dart';
import '../services/host_composer_launch.dart';
import '../theme/mutande_macos_theme.dart';
import '../widgets/handshake_thread_pane.dart';
import '../widgets/onboarding_address_rail.dart';
import '../widgets/onboarding_chrome.dart';

/// Debug-only: pins the starting frame. Waiting still polls so a real
/// handshake can land on Finish without stepping ⌥→.
enum PingPreview { copy, waiting, delivered, timeout }

/// Opens a host composer with the handshake prompt (copy as fallback), then
/// waits for the other agent to publish a handshake. Skip does not exist —
/// a handshake reply is the only way through.
///
/// After send, the thread fills the letterhead’s right side. Finish unlocks
/// home; the notification ask rides along with the wait.
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
    this.sendingTransport,
    this.targetTransport,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final ValueChanged<String?> onComplete;
  final OnboardingAddress address;
  final String? debugBanner;

  /// `@claude` or `orinea@tbhco` — the recipient that is not the sending agent.
  final String target;

  /// Hub slot for the sending host (`mcp` → open ChatGPT/Claude Web).
  final AgentTransport? sendingTransport;

  /// Hub slot for [target]. MCP is preferred when both web and desktop exist.
  final AgentTransport? targetTransport;

  /// Debug walkthrough: pin a starting frame. Waiting still polls; Finish
  /// is never auto-tapped.
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
  ThreadDetailResult? _detail;
  String? _error;
  bool _busy = false;
  late bool _bannersAsked = widget.firstRunStore.notificationsComplete;
  bool _bannersGranted = false;
  bool _opening = false;
  bool _openingReply = false;
  bool _finishing = false;

  String get _prompt => FirstRunPingWizard.promptFor(widget.target);
  String get _replyPrompt => firstRunHandshakeReplyPrompt();
  String? get _hostSlug => widget.address.agent;
  String? get _sendComposerId {
    final slug = _hostSlug;
    if (slug == null) return null;
    return firstRunComposerId(slug: slug, transport: widget.sendingTransport);
  }

  bool get _teammate => firstRunTargetIsTeammate(widget.target);
  String? get _replyComposerId {
    if (_teammate) return null;
    final slug = firstRunTargetHostSlug(widget.target);
    if (slug == null) return null;
    return firstRunComposerId(slug: slug, transport: widget.targetTransport);
  }

  String? get _hostName => HostComposerLaunch.displayName(_sendComposerId);
  String? get _replyHostName =>
      HostComposerLaunch.displayName(_replyComposerId);
  bool get _canOpenHost => HostComposerLaunch.canOpen(_sendComposerId);
  bool get _canOpenReplyHost => HostComposerLaunch.canOpen(_replyComposerId);

  String? get _myHandle {
    final name = widget.address.name?.trim();
    final org = widget.address.org?.trim();
    if (name == null || name.isEmpty || org == null || org.isEmpty) return null;
    return '$name@$org';
  }

  ThreadDetailResult? get _shownDetail {
    if (_detail != null) return _detail;
    if (widget.preview == PingPreview.delivered) {
      return _previewDetail(handshake: true);
    }
    if (widget.preview == PingPreview.waiting) {
      return _previewDetail(handshake: false);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.preview == null) unawaited(_preferTargetTransport());
    if (widget.preview == PingPreview.waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensurePoll();
      });
    }
  }

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
    setState(() {
      _step = pinned;
      _detail = null;
      _threadId = null;
      _waitStarted = pinned == _PingStep.waiting ? DateTime.now() : null;
    });
    if (pinned == _PingStep.waiting) _ensurePoll();
  }

  static _PingStep? _previewStep(PingPreview? preview) => switch (preview) {
    null => null,
    PingPreview.copy => _PingStep.copy,
    PingPreview.waiting => _PingStep.waiting,
    PingPreview.delivered => _PingStep.success,
    PingPreview.timeout => _PingStep.timeout,
  };

  Future<void> _preferTargetTransport() async {
    final slug = firstRunTargetHostSlug(widget.target);
    final transport = widget.targetTransport;
    if (slug == null || transport == null) return;
    try {
      await widget.daemon.setTransportDefault(slug: slug, transport: transport);
    } catch (_) {}
  }

  ThreadDetailResult _previewDetail({required bool handshake}) {
    final me = _myHandle ?? 'alice@acme';
    final sending = _hostSlug ?? 'cursor';
    final peer = firstRunTargetHostSlug(widget.target) ?? 'claude';
    final other = _teammate ? widget.target : '$me/$peer';
    return ThreadDetailResult(
      id: 'preview',
      kind: 'direct',
      status: 'open',
      from: '$me/$sending',
      audience: other,
      messages: [
        ThreadMessageView(
          id: 'm1',
          fromHandle: '$me/$sending',
          createdAt: '2026-08-19T10:00:00Z',
          bundleSubject: 'Handshake',
          bundleNotes: 'Hi — introduce yourself on mutande?',
        ),
        if (handshake)
          ThreadMessageView(
            id: 'm2',
            fromHandle: other,
            createdAt: '2026-08-19T10:00:08Z',
            parentMessageId: 'm1',
            hasHandshake: true,
            bundleNotes: 'I’m the other agent. Ask me about shipping.',
          ),
      ],
    );
  }

  Future<void> _copyPrompt() async {
    Analytics.track(AnalyticsEvent.pingCopy);
    await Clipboard.setData(ClipboardData(text: _prompt));
    if (!mounted) return;
    final host = _hostName ?? 'your AI host';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied — paste into $host')));
  }

  Future<void> _copyTextQuiet(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<HostComposerOpenResult> _launch({
    required String slug,
    required String prompt,
  }) {
    if (widget.openComposer != null) {
      return widget.openComposer!(slug: slug, prompt: prompt);
    }
    return HostComposerLaunch.open(slug: slug, prompt: prompt);
  }

  Future<void> _openHost() async {
    if (_opening) return;
    setState(() => _opening = true);
    unawaited(_copyTextQuiet(_prompt));
    final slug = _sendComposerId ?? '';
    final result = await _launch(slug: slug, prompt: _prompt);
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

  Future<void> _openReplyHost() async {
    if (_openingReply) return;
    final slug = _replyComposerId;
    if (slug == null) return;
    setState(() => _openingReply = true);
    unawaited(_copyTextQuiet(_replyPrompt));
    final result = await _launch(slug: slug, prompt: _replyPrompt);
    if (!mounted) return;
    setState(() => _openingReply = false);
    final host = _replyHostName ?? 'the host';
    switch (result) {
      case HostComposerOpenResult.prefilled:
        Analytics.track(AnalyticsEvent.pingOpen);
      case HostComposerOpenResult.appOpened:
        Analytics.track(AnalyticsEvent.pingOpen);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$host is open — paste the prompt (copied).')),
        );
      case HostComposerOpenResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn’t open $host — prompt copied. Paste it there.',
            ),
          ),
        );
    }
  }

  Future<void> _copyReplyPrompt() async {
    Analytics.track(AnalyticsEvent.pingCopy);
    await Clipboard.setData(ClipboardData(text: _replyPrompt));
    if (!mounted) return;
    final host = _replyHostName ?? 'the other host';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied — paste into $host')));
  }

  void _startWaiting() {
    Analytics.track(AnalyticsEvent.pingWaiting);
    setState(() {
      _step = _PingStep.waiting;
      _waitStarted = DateTime.now();
      _error = null;
      _busy = false;
    });
    _ensurePoll();
  }

  /// Back to the prompt. Keep waiting must not do this — it would drop the
  /// thread the other host is already answering.
  void _startOver() {
    _poll?.cancel();
    setState(() {
      _step = _PingStep.copy;
      _threadId = null;
      _detail = null;
      _waitStarted = null;
      _error = null;
    });
  }

  void _ensurePoll() {
    if (_step != _PingStep.waiting) return;
    if (widget.preview == PingPreview.delivered ||
        widget.preview == PingPreview.timeout) {
      return;
    }
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      if (_threadId != null) {
        await _refreshPinned();
        return;
      }
      final open = await widget.daemon.listThreads(
        filter: 'open',
        enrich: false,
      );
      final started = _waitStarted ?? DateTime.now();
      final candidates = open
          .where(
            (s) => isFirstRunOutboundCandidate(
              summary: s,
              waitStarted: started,
              target: widget.target,
            ),
          )
          .toList();
      candidates.sort((a, b) {
        final at = DateTime.tryParse(a.updatedAt ?? '') ?? DateTime(0);
        final bt = DateTime.tryParse(b.updatedAt ?? '') ?? DateTime(0);
        return bt.compareTo(at);
      });
      for (final summary in candidates) {
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
        if (detail.messages.isEmpty) continue;
        final root = firstRunThreadRoot(detail);
        final ping = root.pingKind?.trim().toLowerCase();
        if (ping != null && ping.isNotEmpty) continue;
        if (!mounted) return;
        setState(() {
          _threadId = detail.id;
          _detail = detail;
          _error = null;
        });
        if (isFirstRunHandshakeReply(detail)) {
          _markSuccess(detail.id);
        }
        return;
      }
      if (!mounted) return;
      if (_error != null) setState(() => _error = null);
      _maybeTimeout(started);
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

  Future<void> _refreshPinned() async {
    final id = _threadId;
    if (id == null) return;
    try {
      final detail = await widget.daemon.getThread(id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _error = null;
      });
      if (isFirstRunHandshakeReply(detail)) {
        _markSuccess(detail.id);
        return;
      }
      _maybeTimeout(_waitStarted ?? DateTime.now());
    } catch (e) {
      if (!mounted) return;
      if (e is TimeoutException || isTimeoutError(e.toString().toLowerCase())) {
        return;
      }
      setState(() => _error = friendlyDaemonError(e, what: 'Threads'));
    }
  }

  void _markSuccess(String threadId) {
    if (_step == _PingStep.success) return;
    _poll?.cancel();
    Analytics.track(AnalyticsEvent.pingSuccess);
    setState(() {
      _step = _PingStep.success;
      _threadId = threadId;
      _error = null;
    });
  }

  void _maybeTimeout(DateTime started) {
    if (_step == _PingStep.success) return;
    // Debug pins stay put; a real handshake can still promote to Finish.
    if (widget.preview != null) return;
    if (DateTime.now().difference(started) > const Duration(minutes: 5)) {
      _poll?.cancel();
      Analytics.track(AnalyticsEvent.pingTimeout);
      setState(() => _step = _PingStep.timeout);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    _poll?.cancel();
    await widget.firstRunStore.markPingComplete();
    if (!mounted) return;
    widget.onComplete(_threadId);
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
    final showSide = _step != _PingStep.copy;
    return OnboardingShell(
      step: OnboardingStep.ping,
      address: widget.address,
      delivered: _step == _PingStep.success,
      debugBanner: widget.debugBanner,
      sideChild: showSide
          ? HandshakeThreadPane(
              detail: _shownDetail,
              myHandle: _myHandle,
              success: _step == _PingStep.success,
            )
          : null,
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
          teammate: _teammate,
          target: widget.target,
          replyHostName: _replyHostName,
          canOpenReply: _canOpenReplyHost,
          openingReply: _openingReply,
          replyPrompt: _replyPrompt,
          onCopyReply: _copyReplyPrompt,
          onOpenReply: _openReplyHost,
          showBannerAsk: !_bannersAsked,
          bannersGranted: _bannersGranted,
          onAllowBanners: _allowBanners,
          onDeclineBanners: _declineBanners,
        ),
        _PingStep.success => _SuccessStep(
          finishing: _finishing,
          onFinish: _finish,
        ),
        _PingStep.timeout => _TimeoutStep(
          onKeepWaiting: _startWaiting,
          onStartOver: _startOver,
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
        _PromptCard(theme: theme, prompt: prompt, onCopy: onCopy),
        OnboardingActions(
          topSpacing: OnboardingSpace.md,
          hugPrimary: true,
          primary: FilledButton(
            onPressed: opening ? null : (canOpen ? onOpen : onWaiting),
            child: Text(
              canOpen
                  ? (hostName == null ? 'Open host' : 'Open $hostName')
                  : 'I’ve pasted it',
            ),
          ),
          secondary: canOpen
              ? TextButton(
                  onPressed: onWaiting,
                  child: const Text('I’ve pasted it'),
                )
              : null,
        ),
      ],
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.theme,
    required this.prompt,
    required this.onCopy,
  });

  final ThemeData theme;
  final String prompt;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _WaitingStep extends StatelessWidget {
  const _WaitingStep({
    required this.error,
    required this.teammate,
    required this.target,
    required this.replyHostName,
    required this.canOpenReply,
    required this.openingReply,
    required this.replyPrompt,
    required this.onCopyReply,
    required this.onOpenReply,
    required this.showBannerAsk,
    required this.bannersGranted,
    required this.onAllowBanners,
    required this.onDeclineBanners,
  });

  final String? error;
  final bool teammate;
  final String target;
  final String? replyHostName;
  final bool canOpenReply;
  final bool openingReply;
  final String replyPrompt;
  final VoidCallback onCopyReply;
  final VoidCallback onOpenReply;
  final bool showBannerAsk;
  final bool bannersGranted;
  final VoidCallback onAllowBanners;
  final VoidCallback onDeclineBanners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = replyHostName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: teammate
              ? 'Ask $target to reply.'
              : (canOpenReply && host != null
                    ? 'Open this in $host.'
                    : 'Paste this in the other host.'),
          subtitle: teammate
              ? 'They introduce themselves with /handshake on this thread.'
              : 'The thread is on the right. They reply with a short intro.',
        ),
        if (!teammate) ...[
          const SizedBox(height: OnboardingSpace.lg),
          _PromptCard(theme: theme, prompt: replyPrompt, onCopy: onCopyReply),
          OnboardingActions(
            topSpacing: OnboardingSpace.md,
            hugPrimary: true,
            primary: canOpenReply
                ? FilledButton(
                    onPressed: openingReply ? null : onOpenReply,
                    child: Text(host == null ? 'Open host' : 'Open $host'),
                  )
                : null,
          ),
        ],
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
  const _SuccessStep({required this.finishing, required this.onFinish});

  final bool finishing;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'they introduced themselves.',
          subtitle: 'That’s the thread. Home is next.',
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.lg,
          hugPrimary: true,
          primary: FilledButton(
            onPressed: finishing ? null : onFinish,
            child: const Text('Finish'),
          ),
        ),
      ],
    );
  }
}

class _TimeoutStep extends StatelessWidget {
  const _TimeoutStep({required this.onKeepWaiting, required this.onStartOver});

  final VoidCallback onKeepWaiting;
  final VoidCallback onStartOver;

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
          hugPrimary: true,
          primary: FilledButton(
            onPressed: onKeepWaiting,
            child: const Text('Keep waiting'),
          ),
          secondary: TextButton(
            onPressed: onStartOver,
            child: const Text('Start over'),
          ),
        ),
      ],
    );
  }
}
