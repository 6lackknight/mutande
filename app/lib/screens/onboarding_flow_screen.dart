import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../config/app_config.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/first_run_store.dart';
import '../services/host_link_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_flow.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/home_chrome_strip.dart';
import '../widgets/morphing_orb_button.dart';
import '../widgets/onboarding_address_rail.dart';
import '../widgets/onboarding_chrome.dart';
import '../widgets/person_identity_row.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thread_skeletons.dart';
import 'first_run_ping_wizard.dart';

/// Guided 4-step onboarding (sign in → team → connect → ping), told as the
/// address assembling itself. Notifications are asked during the ping wait.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({
    super.key,
    required this.config,
    required this.daemon,
    required this.firstRunStore,
    required this.hostLinkStore,
    required this.onComplete,
    this.initialStatus,
    this.forceDebug = false,
    this.initialStep,
  });

  final AppConfig config;
  final DaemonClient daemon;
  final FirstRunStore firstRunStore;
  final HostLinkStore hostLinkStore;
  final void Function(DaemonStatusResult status, String? openThreadId)
  onComplete;
  final DaemonStatusResult? initialStatus;
  final bool forceDebug;
  final OnboardingStep? initialStep;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

enum _TeamMode { setupChoose, setupCreate, setupJoin, roster }

/// Org member on the team roster: avatar, name, lowercase handle.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.handle,
    this.displayName,
    this.avatarUrl,
    this.isSelf = false,
  });

  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final title = personDisplayTitle(displayName: displayName, handle: handle);
    final address = formatMailAddress(handle);
    return Padding(
      padding: const EdgeInsets.only(bottom: OnboardingSpace.sm),
      child: Row(
        children: [
          PersonAvatar(
            size: 32,
            url: avatarUrl,
            initials: personInitials(title),
            seed: handle,
            isSelf: isSelf,
          ),
          const SizedBox(width: OnboardingSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MutandeColors.stone800,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: OnboardingSpace.xs),
                      PersonIdentityRow.statusPill(label: 'you'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 12,
                    color: MutandeColors.stone500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One stop on the debug walkthrough.
class _DebugFrame {
  const _DebugFrame(
    this.step, {
    this.securing = false,
    this.welcomeBack = false,
    this.ping,
  });

  final OnboardingStep step;
  final bool securing;
  final bool welcomeBack;
  final PingPreview? ping;
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  late OnboardingStep _step;
  DaemonStatusResult? _status;
  bool _submitting = false;
  String? _error;

  // Sign-in / securing
  bool _securing = false;

  // Welcome back
  bool _welcomeBack = false;

  // Team setup
  _TeamMode _teamMode = _TeamMode.roster;
  final _slug = TextEditingController();
  final _orgName = TextEditingController();
  final _handle = TextEditingController();
  final _invite = TextEditingController();
  List<ContactView> _contacts = const [];
  bool _contactsLoading = false;

  // Connect
  List<AiHostPresence> _hosts = const [];
  List<AgentInfo> _agents = const [];
  String? _defaultAgentId;
  bool _hostsLoading = false;
  bool _settingDefault = false;
  String? _selectedHost;
  bool _connectWaiting = false;
  String? _connectHint;
  Timer? _connectPoll;

  /// Last address segment — the agent slug, once one has registered.
  String? _agentSlug;

  /// Non-null once the debug walkthrough has been driven off the live flow.
  int? _debugFrameIndex;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _step = widget.initialStep ?? _initialStepFromStatus();
    if (_status?.configured == true) {
      _teamMode = _TeamMode.roster;
    } else if (_status?.signedIn == true) {
      _teamMode = _TeamMode.setupChoose;
    }
    if (_step == OnboardingStep.team) {
      _contactsLoading = _teamMode == _TeamMode.roster;
      unawaited(_loadTeam());
    }
    if (_step == OnboardingStep.connect) {
      _hostsLoading = true;
      unawaited(_loadHosts());
    }
    if (_step == OnboardingStep.ping) {
      unawaited(_loadAgentSlug());
    }
    if (_status?.signedIn == true && _status?.configured != true) {
      unawaited(_refreshSignedInStatus());
    }
  }

  /// Resuming at the ping step: recover the agent segment already earned.
  Future<void> _loadAgentSlug() async {
    try {
      final agents = await widget.daemon.listAgents();
      final slug = agents.agents
          .map((a) => a.slug.toLowerCase())
          .where((s) => s.isNotEmpty && s != 'default')
          .firstOrNull;
      if (!mounted || slug == null) return;
      setState(() => _agentSlug = slug);
    } catch (_) {
      // Address just shows the agent slot empty.
    }
  }

  OnboardingStep _initialStepFromStatus() {
    final s = _status;
    if (s?.configured == true || s?.signedIn == true) {
      return OnboardingStep.team;
    }
    return OnboardingStep.signIn;
  }

  Future<void> _refreshSignedInStatus() async {
    try {
      final status = await widget.daemon.getStatus();
      if (!mounted) return;
      if (!status.configured) return;
      setState(() {
        _status = status;
        _step = OnboardingStep.team;
        _teamMode = _TeamMode.roster;
      });
      await _loadTeam();
    } catch (_) {
      // Stale status — user can still create/join manually.
    }
  }

  @override
  void dispose() {
    _slug.dispose();
    _orgName.dispose();
    _handle.dispose();
    _invite.dispose();
    _connectPoll?.cancel();
    super.dispose();
  }

  /// The address as far as it has been assembled.
  OnboardingAddress get _address {
    final handle = _status?.handle;
    if (handle != null && handle.contains('@')) {
      return OnboardingAddress.fromHandle(handle, agent: _agentSlug);
    }
    // Signed in but no org yet — the name lands from the account email.
    final email = _status?.email;
    final local = (email != null && email.contains('@'))
        ? email.split('@').first.toLowerCase()
        : null;
    return OnboardingAddress(name: local, agent: _agentSlug);
  }

  Future<void> _signIn() async {
    Analytics.track(AnalyticsEvent.signInClick);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final status = await widget.daemon.authLogin(
        hubUrl: widget.config.hubUrl,
        auth0Domain: widget.config.auth0Domain,
        auth0ClientId: widget.config.auth0NativeClientId,
        auth0Audience: widget.config.auth0Audience,
      );
      if (!mounted) return;
      if (status.configured) {
        Analytics.track(AnalyticsEvent.signInSuccess);
        setState(() {
          _status = status;
          _submitting = false;
          _securing = true;
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        setState(() {
          _securing = false;
          _welcomeBack = true;
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        setState(() {
          _welcomeBack = false;
          _step = OnboardingStep.team;
          _teamMode = _TeamMode.roster;
        });
        await _loadTeam();
        return;
      }
      Analytics.track(AnalyticsEvent.signInSuccess, {'needs_org': true});
      setState(() {
        _status = status;
        _submitting = false;
        _step = OnboardingStep.team;
        _teamMode = _TeamMode.setupChoose;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyDaemonError(e, what: 'Sign-in');
      });
    }
  }

  Future<void> _loadTeam() async {
    setState(() => _contactsLoading = true);
    try {
      final status = await widget.daemon.getStatus();
      if (!mounted) return;
      _status = status;
      if (status.configured) {
        final contacts = await widget.daemon.listContacts();
        if (!mounted) return;
        setState(() {
          _contacts = contacts.where((c) => !c.isBroadcast).toList();
          _teamMode = _TeamMode.roster;
          _contactsLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _contactsLoading = false);
  }

  Future<void> _createTeam() async {
    final slug = _slug.text.trim().toLowerCase();
    if (slug.isEmpty) {
      setState(() => _error = 'Team slug is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.daemon.createOrg(
        slug: slug,
        name: _orgName.text.trim().isEmpty ? null : _orgName.text.trim(),
        handle: _handle.text.trim().isEmpty ? null : _handle.text.trim(),
      );
      await _afterTeamSetup();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyDaemonError(e, what: 'Create team');
      });
    }
  }

  Future<void> _joinInvite() async {
    final invite = _invite.text.trim();
    if (invite.isEmpty) {
      setState(() => _error = 'Invite code is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.daemon.joinOrg(
        inviteCode: invite,
        handle: _handle.text.trim().isEmpty ? null : _handle.text.trim(),
      );
      await _afterTeamSetup();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyDaemonError(e, what: 'Join');
      });
    }
  }

  Future<void> _afterTeamSetup() async {
    final status = await widget.daemon.getStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _submitting = false;
      _teamMode = _TeamMode.roster;
    });
    await _loadTeam();
  }

  Future<void> _loadHosts() async {
    setState(() => _hostsLoading = true);
    try {
      final detections = await widget.daemon.detectAiHosts();
      final links = await widget.hostLinkStore.load();
      final agents = await widget.daemon.listAgents();
      final registered = agents.agents.map((a) => a.slug.toLowerCase()).toSet();
      if (!mounted) return;
      setState(() {
        _agents = agents.agents;
        _defaultAgentId = agents.defaultAgentId;
        _hosts =
            detections
                .map(
                  (d) => AiHostPresence(
                    slug: d.host,
                    installed: d.installed,
                    configPresent: d.configPresent,
                    linked: links[d.host]?.ok ?? false,
                    agentRegistered: registered.contains(d.host),
                  ),
                )
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _hostsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hostsLoading = false;
        _error = friendlyDaemonError(e, what: 'Detect hosts');
      });
    }
  }

  String _hostNames(List<AiHostPresence> hosts) {
    final names = hosts.map((h) => AiHostIcon.displayName(h.slug)).toList();
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  AgentInfo? _agentForHost(String slug) {
    final key = slug.toLowerCase();
    for (final a in _agents) {
      if (a.slug.toLowerCase() == key) return a;
    }
    return null;
  }

  bool _isDefaultHost(String slug) {
    final id = _defaultAgentId;
    if (id == null || id.isEmpty) return false;
    return _agentForHost(slug)?.id == id;
  }

  Future<void> _setDefaultHost(String slug) async {
    final agent = _agentForHost(slug);
    if (agent == null) {
      setState(() {
        _error =
            'Connect ${AiHostIcon.displayName(slug)} before setting Default.';
      });
      return;
    }
    setState(() {
      _settingDefault = true;
      _error = null;
    });
    try {
      await widget.daemon.setDefaultAgent(agent.id);
      if (!mounted) return;
      await _loadHosts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyDaemonError(e, what: 'Default');
      });
    } finally {
      if (mounted) setState(() => _settingDefault = false);
    }
  }

  Future<void> _beginConnectHost(String host) async {
    if (!_hosts.any((h) => h.slug == host && h.installed)) {
      setState(() {
        _error = '${AiHostIcon.displayName(host)} isn’t installed on this Mac.';
      });
      return;
    }
    setState(() {
      _selectedHost = host;
      _error = null;
    });
    final result = await showConnectHostFlow(
      context: context,
      daemon: widget.daemon,
      hostLinkStore: widget.hostLinkStore,
      host: host,
      celebrateFirstHost: true,
      fullScreen: true,
    );
    if (!mounted) return;
    if (result == null || !result.mcpOk) {
      setState(() {
        _error = 'Host link was cancelled. Pick an installed host to continue.';
      });
      return;
    }
    setState(() {
      _connectWaiting = true;
      _connectHint = result.mcpNote;
    });
    await _waitForRegistration(host);
  }

  Future<void> _waitForRegistration(String host) async {
    _connectPoll?.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final agents = await widget.daemon.listAgents();
        if (agents.agents.any(
          (a) => a.slug.toLowerCase() == host.toLowerCase(),
        )) {
          await widget.firstRunStore.markConnectComplete();
          if (!mounted) return;
          setState(() {
            _connectWaiting = false;
            _agentSlug = host.toLowerCase();
            _step = OnboardingStep.ping;
          });
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _connectWaiting = false;
      _error =
          'Config written, but mutande hasn’t seen the agent yet. Restart the host, then Retry.';
    });
  }

  /// Copies the invite page URL. It's a page, not a minted invite — the label
  /// says so.
  Future<void> _copyInvitePage() async {
    final base = widget.config.webAppUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/admin/invites';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied: $url')));
  }

  Future<void> _openInvitesWeb() async {
    final base = widget.config.webAppUrl.replaceAll(RegExp(r'/+$'), '');
    await Process.run('open', ['$base/admin/invites']);
  }

  @override
  Widget build(BuildContext context) {
    final screen = _buildStep(context);
    if (!widget.forceDebug) return screen;
    // Debug walkthrough: every frame reachable without signing out or waiting
    // for a real pong.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _stepDebugFrame(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _stepDebugFrame(1),
      },
      child: Focus(autofocus: true, child: screen),
    );
  }

  static const _debugFrames = <_DebugFrame>[
    _DebugFrame(OnboardingStep.signIn),
    _DebugFrame(OnboardingStep.signIn, securing: true),
    _DebugFrame(OnboardingStep.signIn, welcomeBack: true),
    _DebugFrame(OnboardingStep.team),
    _DebugFrame(OnboardingStep.connect),
    _DebugFrame(OnboardingStep.ping, ping: PingPreview.copy),
    _DebugFrame(OnboardingStep.ping, ping: PingPreview.waiting),
    _DebugFrame(OnboardingStep.ping, ping: PingPreview.delivered),
    _DebugFrame(OnboardingStep.ping, ping: PingPreview.timeout),
  ];

  /// Where the live flow currently sits, so the first keypress moves relative
  /// to what's on screen.
  int get _debugFrameCursor {
    final known = _debugFrameIndex;
    if (known != null) return known;
    final at = _debugFrames.indexWhere(
      (f) =>
          f.step == _step &&
          f.securing == _securing &&
          f.welcomeBack == _welcomeBack,
    );
    return at < 0 ? 0 : at;
  }

  void _stepDebugFrame(int delta) {
    var next = _debugFrameCursor + delta;
    next %= _debugFrames.length;
    if (next < 0) next += _debugFrames.length;
    final frame = _debugFrames[next];
    setState(() {
      _debugFrameIndex = next;
      _step = frame.step;
      _securing = frame.securing;
      _welcomeBack = frame.welcomeBack;
      _error = null;
    });
    if (frame.step == OnboardingStep.team) unawaited(_loadTeam());
    if (frame.step == OnboardingStep.connect) unawaited(_loadHosts());
  }

  Widget _buildStep(BuildContext context) {
    final frame = _debugFrameIndex;
    final debugBanner = widget.forceDebug
        ? 'Debug — onboarding preview · ⌥← ⌥→ to step'
              '${frame == null ? '' : ' (${frame + 1}/${_debugFrames.length})'}'
        : null;

    if (_securing) {
      return OnboardingShell(
        step: OnboardingStep.signIn,
        address: _address,
        debugBanner: debugBanner,
        child: _securingBody(),
      );
    }
    if (_welcomeBack) {
      return _welcomeBackScreen(debugBanner);
    }

    switch (_step) {
      case OnboardingStep.signIn:
        return OnboardingShell(
          step: _step,
          address: _address,
          debugBanner: debugBanner,
          child: _signInBody(),
        );
      case OnboardingStep.team:
        return OnboardingShell(
          step: _step,
          address: _address,
          debugBanner: debugBanner,
          child: _teamBody(),
        );
      case OnboardingStep.connect:
        return OnboardingShell(
          step: _step,
          address: _address,
          debugBanner: debugBanner,
          contentMaxWidth: 480,
          child: _connectBody(),
        );
      case OnboardingStep.ping:
        return FirstRunPingWizard(
          daemon: widget.daemon,
          firstRunStore: widget.firstRunStore,
          address: _address,
          debugBanner: debugBanner,
          preview: frame == null ? null : _debugFrames[frame].ping,
          onComplete: (threadId) {
            final status = _status;
            if (status != null) {
              widget.onComplete(status, threadId);
            }
          },
        );
    }
  }

  /// The one screen where the address is already whole — light, like the rest
  /// of the flow. Only the splash is dark.
  Widget _welcomeBackScreen(String? debugBanner) {
    return OnboardingShell(
      step: OnboardingStep.team,
      address: _address,
      debugBanner: debugBanner,
      child: const OnboardingHeading(
        variant: OnboardingHeadingVariant.display,
        title: 'Welcome back.',
      ),
    );
  }

  Widget _securingBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: MutandeOrb.standard(semanticLabel: 'Securing…')),
        const SizedBox(height: OnboardingSpace.lg),
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Securing this Mac',
          subtitle:
              'Creating a device key in Keychain so only you can read your mail. '
              'Choose Allow if macOS asks.',
        ),
      ],
    );
  }

  Widget _signInBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Address Intelligence.',
          subtitle: 'Sign in with the same account as mutande.online.',
          detail:
              'Agent mail for your AI tools — no more copy-pasting between tabs.',
        ),
        if (_error != null) ...[
          const SizedBox(height: OnboardingSpace.md),
          OnboardingErrorBanner(message: _error!),
        ],
        OnboardingActions(
          primary: MorphingOrbButton(
            onPressed: _submitting ? null : _signIn,
            loading: _submitting,
            label: 'Sign in with Auth0',
          ),
        ),
      ],
    );
  }

  Widget _teamBody() {
    if (_teamMode != _TeamMode.roster) {
      return _teamSetupBody();
    }
    if (_contactsLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Your team.',
          ),
          const SizedBox(height: OnboardingSpace.lg),
          const OnboardingRosterSkeleton(),
          const SizedBox(height: OnboardingSpace.lg),
          Text(
            'Teammates need mutande on Mac to receive agent mail.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: MutandeColors.stone500,
              height: 1.4,
            ),
          ),
        ],
      );
    }
    final handle = _status?.handle ?? '';
    final humans = _contacts
        .where((c) => !c.isBroadcast && !c.isExternal)
        .toList();
    final handleLower = handle.toLowerCase();
    ContactView? self;
    for (final c in humans) {
      if (c.handle.toLowerCase() == handleLower) {
        self = c;
        break;
      }
    }
    final peers = humans
        .where((c) => c.handle.toLowerCase() != handleLower)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The marquee above already says who and where — the headline says
        // what that's worth.
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: peers.isEmpty
              ? 'You’re the only one here yet.'
              : '${_countWord(peers.length, 'teammate')} can already reach you.',
        ),
        const SizedBox(height: OnboardingSpace.lg),
        // Plain rows on the stone ground — no card nesting a card.
        if (handle.isNotEmpty)
          _RosterRow(
            handle: handle,
            displayName: self?.displayName,
            avatarUrl: self?.avatarUrl,
            isSelf: true,
          ),
        ...peers.map(
          (c) => _RosterRow(
            handle: c.handle,
            displayName: c.displayName,
            avatarUrl: c.avatarUrl,
          ),
        ),
        const SizedBox(height: OnboardingSpace.lg),
        Text(
          'Teammates need mutande on Mac to receive agent mail.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: MutandeColors.stone500,
            height: 1.4,
          ),
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.md,
          primary: FilledButton(
            onPressed: () {
              setState(() {
                _step = OnboardingStep.connect;
                _hostsLoading = true;
              });
              unawaited(_loadHosts());
            },
            child: const Text('Continue'),
          ),
          secondary: TextButton(
            onPressed: _openInvitesWeb,
            child: const Text('Invite on the web'),
          ),
          tertiary: TextButton(
            onPressed: _copyInvitePage,
            child: const Text('Copy link'),
          ),
        ),
      ],
    );
  }

  /// `One teammate` / `Two teammates` — reads better than a bare digit at the
  /// start of a sentence.
  static String _countWord(int n, String noun) {
    const words = [
      'Zero',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
    ];
    final count = n < words.length ? words[n] : '$n';
    return '$count $noun${n == 1 ? '' : 's'}';
  }

  Widget _teamSetupBody() {
    final title = switch (_teamMode) {
      _TeamMode.setupChoose => 'Pick the org half of your address.',
      _TeamMode.setupCreate => 'Create a team',
      _ => 'Join with invite',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: title,
        ),
        const SizedBox(height: OnboardingSpace.lg),
        if (_teamMode == _TeamMode.setupChoose) ...[
          OnboardingActions(
            topSpacing: 0,
            primary: FilledButton(
              onPressed: () =>
                  setState(() => _teamMode = _TeamMode.setupCreate),
              child: const Text('Create a team'),
            ),
            secondary: TextButton(
              onPressed: () => setState(() => _teamMode = _TeamMode.setupJoin),
              child: const Text('I have an invite'),
            ),
          ),
        ] else if (_teamMode == _TeamMode.setupCreate) ...[
          TextField(
            controller: _slug,
            decoration: const InputDecoration(labelText: 'Team slug'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnboardingSpace.sm),
          TextField(
            controller: _orgName,
            decoration: const InputDecoration(
              labelText: 'Team name (optional)',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnboardingSpace.sm),
          TextField(
            controller: _handle,
            decoration: const InputDecoration(
              labelText: 'Your handle (optional)',
              hintText: 'alice or alice@team',
            ),
            textInputAction: TextInputAction.done,
          ),
          OnboardingActions(
            primary: FilledButton(
              onPressed: _submitting ? null : _createTeam,
              child: Text(_submitting ? 'Creating…' : 'Create team'),
            ),
            tertiary: TextButton(
              onPressed: () =>
                  setState(() => _teamMode = _TeamMode.setupChoose),
              child: const Text('Back'),
            ),
          ),
        ] else ...[
          TextField(
            controller: _invite,
            decoration: const InputDecoration(hintText: 'Paste invite code'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: OnboardingSpace.sm),
          TextField(
            controller: _handle,
            decoration: const InputDecoration(
              labelText: 'Your handle (optional)',
            ),
            textInputAction: TextInputAction.done,
          ),
          OnboardingActions(
            primary: FilledButton(
              onPressed: _submitting ? null : _joinInvite,
              child: Text(_submitting ? 'Joining…' : 'Join team'),
            ),
            tertiary: TextButton(
              onPressed: () =>
                  setState(() => _teamMode = _TeamMode.setupChoose),
              child: const Text('Back'),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: OnboardingSpace.sm),
          OnboardingErrorBanner(message: _error!),
        ],
      ],
    );
  }

  Widget _connectBody() {
    if (_connectWaiting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: MutandeOrb.standard(semanticLabel: 'Connecting…'),
          ),
          const SizedBox(height: OnboardingSpace.lg),
          OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Restart ${_selectedHost ?? 'host'} and open a new chat',
            subtitle: _connectHint,
          ),
        ],
      );
    }

    if (_hostsLoading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Pick a host to connect.',
            subtitle:
                'One is enough — mutande wires the relay, '
                'then hands it the collaboration skill.',
          ),
          SizedBox(height: OnboardingSpace.lg),
          OnboardingHostSkeleton(),
        ],
      );
    }

    // Hierarchy by detection state: what you can actually connect gets the
    // weight, the rest is one quiet line.
    final installed = _hosts.where((h) => h.installed).toList();
    final missing = _hosts.where((h) => !h.installed).toList();
    final linked = installed
        .where((h) => h.linked && h.agentRegistered)
        .toList();

    // The goal, stated as the thing to do — and once it's done, said so.
    final heading = linked.isEmpty
        ? const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Pick a host to connect.',
            subtitle:
                'One is enough — mutande wires the relay, '
                'then hands it the collaboration skill.',
          )
        : OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title:
                '${_hostNames(linked)} '
                '${linked.length == 1 ? 'is' : 'are'} ready to carry mail.',
            subtitle: 'Continue to your first ping, or connect another host.',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        const SizedBox(height: OnboardingSpace.lg),
        for (final host in installed)
          Padding(
            padding: const EdgeInsets.only(bottom: OnboardingSpace.xs),
            child: _HostTile(
              presence: host,
              isDefault: _isDefaultHost(host.slug),
              settingDefault: _settingDefault,
              onTap: () => _beginConnectHost(host.slug),
              onSetDefault: host.linked && host.agentRegistered
                  ? () => _setDefaultHost(host.slug)
                  : null,
            ),
          ),
        if (linked.isNotEmpty) ...[
          const SizedBox(height: OnboardingSpace.sm),
          Text(
            _defaultAgentId == null
                ? 'Set Default so mail to your address goes to one host.'
                : 'Mail to your address goes to Default.',
            style: const TextStyle(fontSize: 12, color: MutandeColors.stone400),
          ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: OnboardingSpace.sm),
          Text(
            '${_hostNames(missing)} '
            '${missing.length == 1 ? 'isn\'t' : 'aren\'t'} installed on this Mac.',
            style: const TextStyle(fontSize: 12, color: MutandeColors.stone400),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: OnboardingSpace.md),
          OnboardingErrorBanner(message: _error!),
        ],
        if (_selectedHost != null && _error != null)
          OnboardingActions(
            topSpacing: OnboardingSpace.sm,
            primary: OutlinedButton(
              onPressed: () => _beginConnectHost(_selectedHost!),
              child: const Text('Retry'),
            ),
          )
        else if (linked.isNotEmpty)
          OnboardingActions(
            topSpacing: OnboardingSpace.md,
            primary: FilledButton(
              onPressed: () => _continueWithLinkedHost(linked.first.slug),
              child: const Text('Continue'),
            ),
          ),
      ],
    );
  }

  /// Forward path when a host is already wired in (returning users, replays,
  /// or a second visit to this step) — the connect ceremony isn't re-run.
  Future<void> _continueWithLinkedHost(String slug) async {
    await widget.firstRunStore.markConnectComplete();
    if (!mounted) return;
    setState(() {
      _agentSlug = slug.toLowerCase();
      _step = OnboardingStep.ping;
    });
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({
    required this.presence,
    required this.onTap,
    this.isDefault = false,
    this.settingDefault = false,
    this.onSetDefault,
  });

  final AiHostPresence presence;
  final VoidCallback onTap;
  final bool isDefault;
  final bool settingDefault;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    final linked = presence.linked && presence.agentRegistered;
    final label = AiHostIcon.displayName(presence.slug);
    final badge = isDefault ? 'Default' : presence.primaryBadge;

    return Semantics(
      button: true,
      label: '$label, $badge',
      child: Material(
        color: isDefault
            ? MutandeColors.stone50
            : linked
            ? MutandeColors.emeraldSoft
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDefault
                    ? MutandeColors.stone800
                    : linked
                    ? const Color(0xFF86EFAC)
                    : MutandeColors.stone200,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Row(
              children: [
                AiHostIcon(presence.slug, size: 44),
                const SizedBox(width: OnboardingSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          letterSpacing: -0.2,
                          color: MutandeColors.stone800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        badge,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDefault
                              ? MutandeColors.stone800
                              : linked
                              ? MutandeColors.emerald
                              : MutandeColors.stone500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (linked) ...[
                  const Icon(
                    Icons.check,
                    size: 20,
                    color: MutandeColors.emerald,
                  ),
                  const SizedBox(width: 10),
                  if (isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: MutandeColors.stone800,
                        borderRadius: HomeChrome.thumbStadium,
                      ),
                      child: const Text(
                        'Default',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MutandeColors.stone50,
                        ),
                      ),
                    )
                  else if (onSetDefault != null)
                    TextButton(
                      onPressed: settingDefault ? null : onSetDefault,
                      style: TextButton.styleFrom(
                        foregroundColor: MutandeColors.stone800,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        settingDefault ? 'Setting…' : 'Set as default',
                      ),
                    ),
                ] else
                  const Text(
                    'Connect',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MutandeColors.amber,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
