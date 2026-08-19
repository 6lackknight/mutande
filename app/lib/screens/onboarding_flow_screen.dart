import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics_events.dart';
import '../config/app_config.dart';
import '../models/agent_transport.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../services/first_run_gates.dart';
import '../services/first_run_store.dart';
import '../services/host_link_store.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../widgets/ai_host_icon.dart';
import '../widgets/connect_host_flow.dart';
import '../widgets/connect_host_picker.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/home_chrome_strip.dart';
import '../widgets/hosted_mcp_flow.dart';
import '../widgets/morphing_orb_button.dart';
import '../widgets/onboarding_address_rail.dart';
import '../widgets/onboarding_chrome.dart';
import '../widgets/person_identity_row.dart';
import '../widgets/thinking_orb.dart';
import '../widgets/thread_skeletons.dart';
import 'first_run_ping_wizard.dart';

/// Guided 4-step onboarding (sign in → team → connect → first handshake).
/// Connect stays until a second host or a live teammate exists; the last
/// step completes only when that recipient replies on a work thread.
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

/// Org member chip on the team roster: person mark, address, known hosts.
class _RosterChip extends StatelessWidget {
  const _RosterChip({
    required this.handle,
    this.displayName,
    this.avatarUrl,
    this.isSelf = false,
    this.hostSlugs = const [],
  });

  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final bool isSelf;
  final List<String> hostSlugs;

  @override
  Widget build(BuildContext context) {
    final title = personDisplayTitle(displayName: displayName, handle: handle);
    final address = formatMailAddress(handle);
    return Container(
      constraints: const BoxConstraints(maxWidth: 300, minHeight: 56),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PersonAvatar(
            size: 40,
            url: avatarUrl,
            initials: personInitials(title),
            seed: handle,
            isSelf: isSelf,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
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
                    fontWeight: FontWeight.w500,
                    color: MutandeColors.stone500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (hostSlugs.isNotEmpty) ...[
            const SizedBox(width: 12),
            _HostAvatarStack(hostSlugs),
          ],
        ],
      ),
    );
  }
}

/// Overlapping host marks for agents we already know on this handle.
class _HostAvatarStack extends StatelessWidget {
  const _HostAvatarStack(this.slugs);

  final List<String> slugs;

  static const _size = 24.0;
  static const _overlap = 9.0;

  @override
  Widget build(BuildContext context) {
    final shown = slugs.take(3).toList();
    final extra = slugs.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final width = _size + (count - 1) * (_size - _overlap);
    final names = shown.map(AiHostIcon.displayName).join(', ');
    return Tooltip(
      message: extra > 0 ? '$names +$extra' : names,
      child: SizedBox(
        width: width,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * (_size - _overlap),
                child: _HostStackDot(shown[i]),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * (_size - _overlap),
                child: _HostStackMore('+$extra'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HostStackDot extends StatelessWidget {
  const _HostStackDot(this.slug);

  final String slug;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _HostAvatarStack._size,
      height: _HostAvatarStack._size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        shape: BoxShape.circle,
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: AiHostIcon(slug, size: 15, showPlate: false),
    );
  }
}

class _HostStackMore extends StatelessWidget {
  const _HostStackMore(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _HostAvatarStack._size,
      height: _HostAvatarStack._size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: MutandeColors.stone800,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MutandeColors.stone50,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
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
  Map<String, List<String>> _hostsByHandle = const {};
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

  /// Teammate handle that already has at least one registered agent.
  String? _liveTeammateHandle;

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
      unawaited(_ensureHandoffDestination());
    }
    if (_status?.signedIn == true && _status?.configured != true) {
      unawaited(_refreshSignedInStatus());
    }
  }

  bool get _destinationReady => firstRunDestinationReady(
    ownAgents: firstRunOwnAgentCount(_agents),
    liveTeammate: _liveTeammateHandle != null,
  );

  String? get _handoffTarget => firstRunHandoffTarget(
    ownAgents: _agents,
    sendingSlug: _agentSlug,
    liveTeammateHandle: _liveTeammateHandle,
  );

  /// Resuming at the handoff step: bounce back if there is still no recipient.
  Future<void> _ensureHandoffDestination() async {
    await _loadHosts();
    if (!mounted) return;
    if (!_destinationReady) {
      setState(() => _step = OnboardingStep.connect);
      return;
    }
    final slug = _agents
        .map((a) => a.slug.toLowerCase())
        .where((s) => s.isNotEmpty && s != 'default')
        .firstOrNull;
    if (slug != null) setState(() => _agentSlug = slug);
  }

  Future<void> _goToHandoffIfReady() async {
    if (!_destinationReady) return;
    await widget.firstRunStore.markConnectComplete();
    if (!mounted) return;
    setState(() => _step = OnboardingStep.ping);
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
        unawaited(_loadContactHosts());
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

  Future<void> _loadContactHosts() async {
    final humans = _contacts.where((c) => !c.isBroadcast && !c.isExternal);
    final self = (_status?.handle ?? '').toLowerCase();
    final next = <String, List<String>>{};
    final keys = <String>{
      if (self.isNotEmpty) self,
      for (final c in humans) c.handle.toLowerCase(),
    };
    for (final key in keys) {
      try {
        final list = key == self
            ? await widget.daemon.listAgents()
            : await widget.daemon.listAgents(handle: key);
        next[key] = _rankedHostSlugs(list.agents);
      } catch (_) {
        next[key] = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _hostsByHandle = next;
      _liveTeammateHandle = next.entries
          .where((e) => e.key != self && e.value.isNotEmpty)
          .map((e) => e.key)
          .firstOrNull;
    });
  }

  static List<String> _rankedHostSlugs(Iterable<AgentInfo> agents) {
    const order = ['cursor', 'claude', 'chatgpt'];
    final slugs = agents
        .map((a) => a.slug.toLowerCase().trim())
        .where((s) => s.isNotEmpty && s != 'default')
        .toSet();
    return [
      for (final o in order)
        if (slugs.contains(o)) o,
      ...slugs.where((s) => !order.contains(s)),
    ];
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
      final live = await _findLiveTeammate();
      final registered = agents.agents;
      if (!mounted) return;
      setState(() {
        _agents = agents.agents;
        _defaultAgentId = agents.defaultAgentId;
        _liveTeammateHandle = live;
        _hosts = [
          for (final spec in AiHostCatalog.onboarding)
            _presenceFor(spec, detections, links, registered),
        ];
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

  static AiHostPresence _presenceFor(
    AiHostSpec spec,
    List<AiHostDetection> detections,
    Map<String, HostLinkRecord> links,
    List<AgentInfo> agents,
  ) {
    AiHostDetection? detected;
    for (final d in detections) {
      if (d.host.toLowerCase() == spec.agentSlug) {
        detected = d;
        break;
      }
    }
    final slug = spec.agentSlug.toLowerCase();
    final webReg = agents.any(
      (a) =>
          a.slug.toLowerCase() == slug && a.transport == AgentTransport.mcp,
    );
    final desktopReg = agents.any((a) {
      if (a.slug.toLowerCase() != slug) return false;
      return a.transport != AgentTransport.mcp;
    });
    return AiHostPresence(
      id: spec.id,
      slug: spec.agentSlug,
      iconSlug: spec.iconSlug,
      label: spec.label,
      installed: spec.isWeb || (detected?.installed ?? false),
      configPresent: detected?.configPresent ?? false,
      linked: spec.isWeb
          ? webReg
          : (links[spec.agentSlug]?.ok ?? false),
      agentRegistered: spec.isWeb ? webReg : desktopReg,
      isWeb: spec.isWeb,
    );
  }

  Future<String?> _findLiveTeammate() async {
    var contacts = _contacts;
    if (contacts.isEmpty) {
      try {
        contacts = await widget.daemon.listContacts();
        if (mounted) {
          _contacts = contacts.where((c) => !c.isBroadcast).toList();
        }
      } catch (_) {
        return _liveTeammateHandle;
      }
    }
    final self = (_status?.handle ?? '').toLowerCase();
    if (_hostsByHandle.isNotEmpty) {
      for (final e in _hostsByHandle.entries) {
        if (e.key != self && e.value.isNotEmpty) return e.key;
      }
    }
    for (final c in contacts) {
      if (c.isBroadcast) continue;
      if (self.isNotEmpty && c.handle.toLowerCase() == self) continue;
      try {
        final list = await widget.daemon.listAgents(handle: c.handle);
        if (list.agents.isNotEmpty) return c.handle.toLowerCase();
      } catch (_) {}
    }
    return null;
  }

  String _hostNames(List<AiHostPresence> hosts) {
    final names = hosts.map((h) => h.label).toList();
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

  Future<void> _beginConnectHost(String catalogId) async {
    final spec = AiHostCatalog.onboardingById(catalogId);
    if (spec == null) return;
    setState(() {
      _selectedHost = spec.id;
      _error = null;
    });

    if (spec.isWeb) {
      final ok = await showHostedMcpConnectFlow(
        context: context,
        daemon: widget.daemon,
        spec: spec,
      );
      if (!mounted) return;
      if (ok == true) {
        await _loadHosts();
        return;
      }
      if (ok == null) {
        setState(() {
          _error = 'Host link was cancelled. Pick a host to continue.';
        });
      }
      return;
    }

    final installed = _hosts.any((h) => h.id == spec.id && h.installed);
    final result = await showConnectHostFlow(
      context: context,
      daemon: widget.daemon,
      hostLinkStore: widget.hostLinkStore,
      host: spec.agentSlug,
      needsInstall: !installed,
      downloadUrl: spec.downloadUrl,
      celebrateFirstHost: true,
      fullScreen: true,
    );
    if (!mounted) return;
    if (result == null || !result.mcpOk) {
      setState(() {
        _error = 'Host link was cancelled. Pick a host to continue.';
      });
      return;
    }
    setState(() {
      _connectWaiting = true;
      _connectHint = result.mcpNote;
    });
    await _waitForRegistration(spec.agentSlug);
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
          if (!mounted) return;
          setState(() {
            _connectWaiting = false;
            _agentSlug = host.toLowerCase();
            _agents = agents.agents;
          });
          await _loadHosts();
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
    // for a real reply.
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
          contentMaxWidth: 560,
          child: _connectBody(),
        );
      case OnboardingStep.ping:
        final target = _handoffTarget;
        if (target == null && frame == null) {
          return OnboardingShell(
            step: OnboardingStep.ping,
            address: _address,
            debugBanner: debugBanner,
            child: const SizedBox.shrink(),
          );
        }
        return FirstRunPingWizard(
          daemon: widget.daemon,
          firstRunStore: widget.firstRunStore,
          address: _address,
          target: target ?? '@claude',
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

    final handle = _status?.handle ?? '';
    final humans = _contactsLoading
        ? const <ContactView>[]
        : _contacts.where((c) => !c.isBroadcast && !c.isExternal).toList();
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

    final title = _contactsLoading
        ? 'Your team.'
        : peers.isEmpty
        ? 'You’re the only one here yet.'
        : '${_countWord(peers.length, 'teammate')} can already reach you.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: title,
        ),
        const SizedBox(height: OnboardingSpace.lg),
        SizedBox(
          height: kOnboardingRosterPanelHeight,
          child: _contactsLoading
              ? const OnboardingRosterSkeleton()
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (handle.isNotEmpty)
                        _RosterChip(
                          handle: handle,
                          displayName: self?.displayName ?? _status?.displayName,
                          avatarUrl: self?.avatarUrl ?? _status?.avatarUrl,
                          isSelf: true,
                          hostSlugs:
                              _hostsByHandle[handle.toLowerCase()] ?? const [],
                        ),
                      for (final c in peers)
                        _RosterChip(
                          handle: c.handle,
                          displayName: c.displayName,
                          avatarUrl: c.avatarUrl,
                          hostSlugs:
                              _hostsByHandle[c.handle.toLowerCase()] ??
                              const [],
                        ),
                    ],
                  ),
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
            onPressed: _contactsLoading
                ? null
                : () {
                    setState(() {
                      _step = OnboardingStep.connect;
                      _hostsLoading = true;
                    });
                    unawaited(_loadHosts());
                  },
            child: const Text('Continue'),
          ),
          secondary: TextButton(
            onPressed: _contactsLoading ? null : _openInvitesWeb,
            child: const Text('Invite on the web'),
          ),
          tertiary: TextButton(
            onPressed: _contactsLoading ? null : _copyInvitePage,
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

    final connected = _hostsLoading
        ? const <AiHostPresence>[]
        : _hosts.where((h) => h.connected).toList();
    final available = _hostsLoading
        ? const <AiHostPresence>[]
        : _hosts.where((h) => !h.connected).toList();

    final ownCount = firstRunOwnAgentCount(_agents);
    final heading = _hostsLoading || (connected.isEmpty && ownCount == 0)
        ? const OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: 'Pick a host to connect.',
            subtitle:
                'Desktop apps on this Mac, or ChatGPT and Claude in the browser.',
          )
        : !_destinationReady
        ? OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: connected.isEmpty
                ? 'Connect another host.'
                : '${_hostNames(connected)} '
                      '${connected.length == 1 ? 'is' : 'are'} ready to carry mail.',
            subtitle:
                'A handoff needs a second host of yours, or a teammate who '
                'already has mutande.',
          )
        : OnboardingHeading(
            variant: OnboardingHeadingVariant.display,
            title: connected.isEmpty
                ? 'Ready for a first handshake.'
                : '${_hostNames(connected)} '
                      '${connected.length == 1 ? 'is' : 'are'} ready to carry mail.',
            subtitle: _liveTeammateHandle == null
                ? 'Continue to your first handshake.'
                : 'Continue to your first handshake — $_liveTeammateHandle can already receive.',
          );

    final showContinue = !_hostsLoading && _destinationReady;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading,
        const SizedBox(height: OnboardingSpace.lg),
        SizedBox(
          height: kOnboardingHostPanelHeight,
          child: _hostsLoading
              ? const OnboardingHostSkeleton()
              : SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (connected.isNotEmpty) ...[
                        SizedBox(
                          width: 220,
                          child: Column(
                            children: [
                              for (final host in connected)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: OnboardingSpace.xs,
                                  ),
                                  child: _HostTile(
                                    presence: host,
                                    isDefault: _isDefaultHost(host.slug),
                                    settingDefault: _settingDefault,
                                    onTap: () => _beginConnectHost(host.id),
                                    onSetDefault: host.connected
                                        ? () => _setDefaultHost(host.slug)
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: OnboardingSpace.md),
                      ],
                      Expanded(
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 16,
                          children: [
                            for (final host in available)
                              _HostCloudMark(
                                presence: host,
                                onTap: () => _beginConnectHost(host.id),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        SizedBox(
          height: kOnboardingConnectHelperHeight,
          child: Align(
            alignment: Alignment.topLeft,
            child: _hostsLoading || connected.isEmpty
                ? null
                : Text(
                    _defaultAgentId == null
                        ? 'Set Default so mail to your address goes to one host.'
                        : 'Mail to your address goes to Default.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: MutandeColors.stone400,
                    ),
                  ),
          ),
        ),
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
        else if (showContinue)
          OnboardingActions(
            topSpacing: OnboardingSpace.md,
            primary: FilledButton(
              onPressed: () => _continueWithLinkedHost(
                connected.isNotEmpty
                    ? connected.first.slug
                    : (_agents.isNotEmpty ? _agents.first.slug : ''),
              ),
              child: const Text('Continue'),
            ),
          )
        else if (!_hostsLoading && ownCount >= 1)
          OnboardingActions(
            topSpacing: OnboardingSpace.md,
            secondary: TextButton(
              onPressed: _openInvitesWeb,
              child: const Text('Invite on the web'),
            ),
            tertiary: TextButton(
              onPressed: () => unawaited(_loadHosts()),
              child: const Text('Check again'),
            ),
          ),
      ],
    );
  }

  /// Forward path when a destination is already ready (two hosts or a live
  /// teammate) — the connect ceremony isn't re-run.
  Future<void> _continueWithLinkedHost(String slug) async {
    if (slug.isNotEmpty) {
      setState(() => _agentSlug = slug.toLowerCase());
    }
    await _goToHandoffIfReady();
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
    final label = presence.label;
    final badge = isDefault ? 'Default' : 'Connected';

    return Semantics(
      button: true,
      label: '$label, $badge',
      child: Material(
        color: isDefault
            ? MutandeColors.stone50
            : MutandeColors.emeraldSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDefault
                    ? MutandeColors.stone800
                    : const Color(0xFF86EFAC),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
            child: Row(
              children: [
                AiHostIcon(presence.iconSlug, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: -0.15,
                      color: MutandeColors.stone800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.check,
                  size: 16,
                  color: MutandeColors.emerald,
                ),
                if (isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: MutandeColors.stone800,
                      borderRadius: HomeChrome.thumbStadium,
                    ),
                    child: const Text(
                      'Default',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: MutandeColors.stone50,
                      ),
                    ),
                  ),
                ] else if (onSetDefault != null)
                  TextButton(
                    onPressed: settingDefault ? null : onSetDefault,
                    style: TextButton.styleFrom(
                      foregroundColor: MutandeColors.stone800,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      settingDefault ? '…' : 'Default',
                      style: const TextStyle(fontSize: 11),
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

class _HostCloudMark extends StatelessWidget {
  const _HostCloudMark({required this.presence, required this.onTap});

  final AiHostPresence presence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Connect ${presence.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiHostIcon(presence.iconSlug, size: 44),
              const SizedBox(height: 8),
              Text(
                presence.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: MutandeColors.stone800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                presence.isWeb
                    ? 'Browser'
                    : presence.installed
                    ? 'This Mac'
                    : 'Install',
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: MutandeColors.stone400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
