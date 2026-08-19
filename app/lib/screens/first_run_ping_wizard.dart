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
import '../widgets/onboarding_roster_chip.dart';
import '../widgets/thinking_orb.dart';

/// Debug-only: pins the starting frame. Waiting still polls so a real
/// handshake can land on Finish without stepping ⌥→.
enum PingPreview { pick, copy, waiting, delivered, timeout }

/// Opens a host composer with the handshake prompt (copy as fallback), then
/// waits for the other agent to publish a handshake. Skip does not exist —
/// a handshake reply is the only way through.
///
/// After send, the thread fills the letterhead’s right side. A first-job
/// card or Finish unlocks home; the notification ask rides along with the wait.
class FirstRunPingWizard extends StatefulWidget {
  const FirstRunPingWizard({
    super.key,
    required this.daemon,
    required this.firstRunStore,
    required this.onComplete,
    required this.target,
    this.choices = const [],
    this.contacts = const [],
    this.hostsByHandle = const {},
    this.ownAgents = const [],
    this.address = const OnboardingAddress(),
    this.debugBanner,
    this.preview,
    this.openComposer,
    this.sendingTransport,
    this.targetTransport,
    this.onInvite,
  });

  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final ValueChanged<String?> onComplete;
  final OnboardingAddress address;
  final String? debugBanner;

  /// `@claude` or `orinea@tbhco` — used when [choices] is empty or a single
  /// destination. Multiple choices show a picker first.
  final String target;

  /// Other own hosts and live teammates. One `@chatgpt` covers desktop + web.
  final List<String> choices;

  /// Org roster — names and avatars on teammate destination chips.
  final List<ContactView> contacts;

  /// Known host slugs per handle, same map as the team roster.
  final Map<String, List<String>> hostsByHandle;

  /// Own agent slots — used to pick ChatGPT/Claude Web vs desktop after a choice.
  final List<AgentInfo> ownAgents;

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

  /// Opens the web invite page. Null hides the invite card even when solo.
  final VoidCallback? onInvite;

  static String promptFor(String target) => firstRunHandshakePrompt(target);

  @override
  State<FirstRunPingWizard> createState() => _FirstRunPingWizardState();
}

enum _PingStep { pick, copy, waiting, success, timeout }

class _FirstRunPingWizardState extends State<FirstRunPingWizard> {
  late String _target = widget.target;
  late _PingStep _step =
      _previewStep(widget.preview) ??
      (widget.choices.length > 1 ? _PingStep.pick : _PingStep.copy);
  Timer? _poll;
  DateTime? _waitStarted;
  String? _threadId;
  ThreadDetailResult? _detail;
  String? _error;
  bool _busy = false;
  late bool _bannersAsked = widget.firstRunStore.notificationsComplete;
  bool _bannersGranted = false;
  bool _finishing = false;
  bool _awaitingThread = false;
  bool _awaitingReply = false;
  bool _holdOnCopy = false;
  String? _startingKind;

  String get _prompt => FirstRunPingWizard.promptFor(_target);
  String get _replyPrompt => firstRunHandshakeReplyPrompt();
  String? get _hostSlug => widget.address.agent;
  bool get _shouldPick => widget.choices.length > 1;
  AgentTransport? get _targetTransport =>
      firstRunHandoffTransport(ownAgents: widget.ownAgents, target: _target) ??
      widget.targetTransport;
  String? get _sendComposerId {
    final slug = _hostSlug;
    if (slug == null) return null;
    return firstRunComposerId(slug: slug, transport: widget.sendingTransport);
  }

  bool get _teammate => firstRunTargetIsTeammate(_target);
  String? get _replyComposerId {
    if (_teammate) return null;
    final slug = firstRunTargetHostSlug(_target);
    if (slug == null) return null;
    return firstRunComposerId(slug: slug, transport: _targetTransport);
  }

  String? get _hostName => HostComposerLaunch.displayName(_sendComposerId);
  String? get _replyHostName =>
      HostComposerLaunch.displayName(_replyComposerId);
  bool get _canOpenHost => HostComposerLaunch.canOpen(_sendComposerId);
  bool get _canOpenReplyHost => HostComposerLaunch.canOpen(_replyComposerId);

  String get _sendWaitLabel {
    final host = _hostName ?? _hostSlug;
    return host == null ? 'Waiting' : 'Waiting for $host';
  }

  String get _replyWaitLabel {
    final host = _replyHostName;
    return host == null ? 'Waiting' : 'Waiting for $host';
  }

  ({String first, String second}) get _nextPair => firstRunNextStepPairLabels(
    ownAgents: widget.ownAgents,
    sendingSlug: _hostSlug ?? '',
    target: _target,
    contacts: widget.contacts,
  );

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
    if (widget.preview == null && !_shouldPick) {
      unawaited(_preferTargetTransport());
    }
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
    PingPreview.pick => _PingStep.pick,
    PingPreview.copy => _PingStep.copy,
    PingPreview.waiting => _PingStep.waiting,
    PingPreview.delivered => _PingStep.success,
    PingPreview.timeout => _PingStep.timeout,
  };

  Future<void> _preferTargetTransport([String? target]) async {
    final chosen = target ?? _target;
    final slug = firstRunTargetHostSlug(chosen);
    final transport =
        firstRunHandoffTransport(ownAgents: widget.ownAgents, target: chosen) ??
        widget.targetTransport;
    if (slug == null || transport == null) return;
    try {
      await widget.daemon.setTransportDefault(slug: slug, transport: transport);
    } catch (_) {}
  }

  void _pickTarget(String target) {
    Analytics.track(AnalyticsEvent.pingPicked);
    setState(() {
      _target = target;
      _step = _PingStep.copy;
    });
    unawaited(_preferTargetTransport(target));
  }

  ThreadDetailResult _previewDetail({required bool handshake}) {
    final me = _myHandle ?? 'alice@acme';
    final sending = _hostSlug ?? 'cursor';
    final peer = firstRunTargetHostSlug(_target) ?? 'claude';
    final other = _teammate ? _target : '$me/$peer';
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
    _beginSendWait();
    await Clipboard.setData(ClipboardData(text: _prompt));
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
    if (_awaitingThread) return;
    _beginSendWait();
    unawaited(_copyTextQuiet(_prompt));
    final slug = _sendComposerId ?? '';
    if (slug.isEmpty) return;
    final result = await _launch(slug: slug, prompt: _prompt);
    if (!mounted) return;
    switch (result) {
      case HostComposerOpenResult.prefilled:
        Analytics.track(AnalyticsEvent.pingOpen);
      case HostComposerOpenResult.appOpened:
        Analytics.track(AnalyticsEvent.pingOpen);
      case HostComposerOpenResult.failed:
        break;
    }
  }

  Future<void> _openReplyHost() async {
    if (_awaitingReply) return;
    final slug = _replyComposerId;
    if (slug == null) return;
    _beginReplyWait();
    unawaited(_copyTextQuiet(_replyPrompt));
    final result = await _launch(slug: slug, prompt: _replyPrompt);
    if (!mounted) return;
    switch (result) {
      case HostComposerOpenResult.prefilled:
      case HostComposerOpenResult.appOpened:
        Analytics.track(AnalyticsEvent.pingOpen);
      case HostComposerOpenResult.failed:
        break;
    }
  }

  Future<void> _copyReplyPrompt() async {
    Analytics.track(AnalyticsEvent.pingCopy);
    _beginReplyWait();
    await Clipboard.setData(ClipboardData(text: _replyPrompt));
  }

  void _beginSendWait() {
    Analytics.track(AnalyticsEvent.pingWaiting);
    setState(() {
      _awaitingThread = true;
      _holdOnCopy = false;
      _waitStarted ??= DateTime.now();
      _error = null;
      _busy = false;
    });
    _ensurePoll();
  }

  void _beginReplyWait() {
    setState(() => _awaitingReply = true);
  }

  void _goBackFromCopy() {
    if (_shouldPick) {
      _startOver();
      return;
    }
    _poll?.cancel();
    setState(() {
      _awaitingThread = false;
      _holdOnCopy = false;
      _waitStarted = null;
    });
  }

  void _goBackFromWaiting() {
    setState(() {
      _step = _PingStep.copy;
      _awaitingReply = false;
      _awaitingThread = false;
      _holdOnCopy = true;
    });
  }

  void _resumeWait() {
    Analytics.track(AnalyticsEvent.pingWaiting);
    setState(() {
      _waitStarted = DateTime.now();
      _error = null;
      _busy = false;
      _holdOnCopy = false;
      if (_threadId != null) {
        _step = _PingStep.waiting;
        _awaitingReply = true;
      } else {
        _step = _PingStep.copy;
        _awaitingThread = true;
      }
    });
    _ensurePoll();
  }

  /// Back to the prompt. Keep waiting must not do this — it would drop the
  /// thread the other host is already answering.
  void _startOver() {
    _poll?.cancel();
    setState(() {
      _step = _shouldPick ? _PingStep.pick : _PingStep.copy;
      _threadId = null;
      _detail = null;
      _waitStarted = null;
      _error = null;
      _awaitingThread = false;
      _awaitingReply = false;
      _holdOnCopy = false;
    });
  }

  void _ensurePoll() {
    final watchCopy =
        _step == _PingStep.copy && (_awaitingThread || _threadId != null);
    if (_step != _PingStep.waiting && !watchCopy) return;
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
              target: _target,
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
          if (_step == _PingStep.copy && !_holdOnCopy) {
            _step = _PingStep.waiting;
            _awaitingThread = false;
          }
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
    Analytics.track(AnalyticsEvent.pingNext, {'kind': 'skip'});
    await widget.firstRunStore.markPingComplete();
    if (!mounted) return;
    widget.onComplete(_threadId);
  }

  Future<void> _startNext(String kind) async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _startingKind = kind;
      _error = null;
    });
    _poll?.cancel();
    Analytics.track(AnalyticsEvent.pingNext, {'kind': kind});
    final pair = _nextPair;
    final notes = kind == 'physics'
        ? firstRunNextStepPhysicsNotes(pair.first, pair.second)
        : firstRunNextStepWorkNotes(pair.first, pair.second);
    try {
      final id = await widget.daemon.forwardDraft(
        recipient: firstRunNextStepRecipient(
          ownAgents: widget.ownAgents,
          target: _target,
        ),
        notes: notes,
      );
      await widget.firstRunStore.markPingComplete();
      if (!mounted) return;
      widget.onComplete(id.isNotEmpty ? id : _threadId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _startingKind = null;
        _error = friendlyDaemonError(e, what: 'Send');
      });
    }
  }

  void _openInvite() {
    Analytics.track(AnalyticsEvent.pingNext, {'kind': 'invite'});
    widget.onInvite?.call();
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
    final showSide = _step != _PingStep.copy && _step != _PingStep.pick;
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
        _PingStep.pick => _PickStep(
          choices: widget.choices.isEmpty ? [_target] : widget.choices,
          contacts: widget.contacts,
          hostsByHandle: widget.hostsByHandle,
          onPick: _pickTarget,
        ),
        _PingStep.copy => _CopyStep(
          theme: theme,
          hostName: _hostName,
          hostSlug: _hostSlug,
          canOpen: _canOpenHost,
          waiting: _awaitingThread,
          waitLabel: _sendWaitLabel,
          prompt: _prompt,
          onCopy: _copyPrompt,
          onOpen: _openHost,
          onGoBack: _goBackFromCopy,
        ),
        _PingStep.waiting => _WaitingStep(
          error: _error,
          teammate: _teammate,
          target: _target,
          replyHostName: _replyHostName,
          canOpenReply: _canOpenReplyHost,
          waiting: _awaitingReply,
          waitLabel: _replyWaitLabel,
          replyPrompt: _replyPrompt,
          onCopyReply: _copyReplyPrompt,
          onOpenReply: _openReplyHost,
          onGoBack: _goBackFromWaiting,
          showBannerAsk: !_bannersAsked,
          bannersGranted: _bannersGranted,
          onAllowBanners: _allowBanners,
          onDeclineBanners: _declineBanners,
        ),
        _PingStep.success => _SuccessStep(
          finishing: _finishing,
          startingKind: _startingKind,
          error: _error,
          first: _nextPair.first,
          second: _nextPair.second,
          showInvite:
              widget.onInvite != null &&
              firstRunShowInvite(
                contacts: widget.contacts,
                myHandle: _myHandle,
              ),
          onWork: () => _startNext('work'),
          onPhysics: () => _startNext('physics'),
          onInvite: widget.onInvite == null ? null : _openInvite,
          onFinish: _finish,
        ),
        _PingStep.timeout => _TimeoutStep(
          onKeepWaiting: _resumeWait,
          onStartOver: _startOver,
        ),
      },
    );
  }
}

class _PickStep extends StatelessWidget {
  const _PickStep({
    required this.choices,
    required this.contacts,
    required this.hostsByHandle,
    required this.onPick,
  });

  final List<String> choices;
  final List<ContactView> contacts;
  final Map<String, List<String>> hostsByHandle;
  final ValueChanged<String> onPick;

  ContactView? _contact(String handle) {
    final key = handle.trim().toLowerCase();
    for (final c in contacts) {
      if (c.handle.toLowerCase() == key) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Who gets this handshake.',
          subtitle:
              'Another host of yours, or a teammate who already has mutande.',
        ),
        const SizedBox(height: OnboardingSpace.lg),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final target in choices)
              _HandshakeChoiceChip(
                target: target,
                contact: firstRunTargetIsTeammate(target)
                    ? _contact(target)
                    : null,
                hostSlugs: firstRunTargetIsTeammate(target)
                    ? (hostsByHandle[target.trim().toLowerCase()] ?? const [])
                    : const [],
                onTap: () => onPick(target),
              ),
          ],
        ),
      ],
    );
  }
}

class _HandshakeChoiceChip extends StatelessWidget {
  const _HandshakeChoiceChip({
    required this.target,
    required this.onTap,
    this.contact,
    this.hostSlugs = const [],
  });

  final String target;
  final ContactView? contact;
  final List<String> hostSlugs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = firstRunHandoffChoiceLabel(target);
    final icon = firstRunHandoffChoiceIconSlug(target);
    return OnboardingRosterChip(
      handle: target,
      displayName:
          contact?.displayName ??
          (firstRunTargetIsTeammate(target) ? null : label),
      avatarUrl: contact?.avatarUrl,
      hostSlugs: hostSlugs,
      leading: icon == null ? null : OnboardingHostLeading(icon),
      semanticLabel: 'Handshake with $label',
      onTap: onTap,
    );
  }
}

class _CopyStep extends StatelessWidget {
  const _CopyStep({
    required this.theme,
    required this.hostName,
    required this.hostSlug,
    required this.canOpen,
    required this.waiting,
    required this.waitLabel,
    required this.prompt,
    required this.onCopy,
    required this.onOpen,
    required this.onGoBack,
  });

  final ThemeData theme;
  final String? hostName;
  final String? hostSlug;
  final bool canOpen;
  final bool waiting;
  final String waitLabel;
  final String prompt;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onGoBack;

  String get _title {
    if (canOpen && hostName != null) return 'Open this in $hostName.';
    if (hostSlug != null) return 'Paste this into $hostSlug.';
    return 'Paste this into your connected host.';
  }

  String get _idleLabel {
    if (canOpen) return hostName == null ? 'Open host' : 'Open $hostName';
    return 'Waiting';
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
          primary: (canOpen || waiting)
              ? _HandshakeWaitButton(
                  label: _idleLabel,
                  waitingLabel: waitLabel,
                  waiting: waiting,
                  onPressed: canOpen ? onOpen : null,
                )
              : null,
          secondary: TextButton(
            onPressed: onGoBack,
            child: const Text('Go back'),
          ),
        ),
      ],
    );
  }
}

class _HandshakeWaitButton extends StatelessWidget {
  const _HandshakeWaitButton({
    required this.label,
    required this.waitingLabel,
    required this.waiting,
    required this.onPressed,
  });

  final String label;
  final String waitingLabel;
  final bool waiting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: waiting ? null : onPressed,
      style: FilledButton.styleFrom(
        disabledBackgroundColor: MutandeColors.stone800,
        disabledForegroundColor: MutandeColors.stone50,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (waiting) ...[
            MutandeOrb.loading(semanticLabel: waitingLabel, dark: true),
            const SizedBox(width: 8),
          ],
          Text(waiting ? waitingLabel : label),
        ],
      ),
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
    required this.waiting,
    required this.waitLabel,
    required this.replyPrompt,
    required this.onCopyReply,
    required this.onOpenReply,
    required this.onGoBack,
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
  final bool waiting;
  final String waitLabel;
  final String replyPrompt;
  final VoidCallback onCopyReply;
  final VoidCallback onOpenReply;
  final VoidCallback onGoBack;
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
            primary: _HandshakeWaitButton(
              label: host == null ? 'Open host' : 'Open $host',
              waitingLabel: waitLabel,
              waiting: waiting,
              onPressed: canOpenReply ? onOpenReply : null,
            ),
            secondary: TextButton(
              onPressed: onGoBack,
              child: const Text('Go back'),
            ),
          ),
        ] else
          OnboardingActions(
            topSpacing: OnboardingSpace.md,
            secondary: TextButton(
              onPressed: onGoBack,
              child: const Text('Go back'),
            ),
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
  const _SuccessStep({
    required this.finishing,
    required this.startingKind,
    required this.first,
    required this.second,
    required this.showInvite,
    required this.onWork,
    required this.onPhysics,
    required this.onFinish,
    this.error,
    this.onInvite,
  });

  final bool finishing;
  final String? startingKind;
  final String? error;
  final String first;
  final String second;
  final bool showInvite;
  final VoidCallback onWork;
  final VoidCallback onPhysics;
  final VoidCallback? onInvite;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'they introduced themselves.',
          subtitle: 'That’s the thread. Send a first job, or look around.',
        ),
        const SizedBox(height: OnboardingSpace.lg),
        _NextJobCard(
          title: 'Find work worth a handoff.',
          body:
              'Ask $first and $second what they’re each holding that the other '
              'could take.',
          starting: startingKind == 'work',
          enabled: !finishing,
          onTap: onWork,
        ),
        const SizedBox(height: OnboardingSpace.sm),
        _NextJobCard(
          title: 'Check this with me.',
          body:
              'Give $first the setup and $second the check: why a Foucault '
              'pendulum appears to rotate, and what would change at the equator.',
          starting: startingKind == 'physics',
          enabled: !finishing,
          onTap: onPhysics,
        ),
        if (showInvite && onInvite != null) ...[
          const SizedBox(height: OnboardingSpace.sm),
          _NextJobCard(
            title: 'Invite someone.',
            body: 'Teammates need mutande on Mac to receive agent mail.',
            starting: false,
            enabled: !finishing,
            onTap: onInvite!,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: OnboardingSpace.sm),
          OnboardingErrorBanner(message: error!),
        ],
        OnboardingActions(
          topSpacing: OnboardingSpace.md,
          secondary: TextButton(
            onPressed: finishing ? null : onFinish,
            child: const Text('Finish'),
          ),
        ),
      ],
    );
  }
}

class _NextJobCard extends StatelessWidget {
  const _NextJobCard({
    required this.title,
    required this.body,
    required this.starting,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String body;
  final bool starting;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Material(
      color: MutandeColors.stone50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: MutandeColors.stone200),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: MutandeColors.stone800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: theme.bodyMedium?.copyWith(
                  color: MutandeColors.stone600,
                  height: 1.45,
                ),
              ),
              if (starting) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    MutandeOrb.loading(semanticLabel: 'Starting'),
                    const SizedBox(width: 8),
                    Text(
                      'Starting',
                      style: theme.labelMedium?.copyWith(
                        color: MutandeColors.stone500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
