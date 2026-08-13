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
import '../widgets/morphing_orb_button.dart';
import '../widgets/onboarding_stepper.dart';
import '../widgets/thinking_orb.dart';
import 'first_run_ping_wizard.dart';

/// Guided 5-step onboarding (sign in → team → connect → notify → ping).
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
  final void Function(DaemonStatusResult status, String? openThreadId) onComplete;
  final DaemonStatusResult? initialStatus;
  final bool forceDebug;
  final OnboardingStep? initialStep;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

enum _TeamMode { setupChoose, setupCreate, setupJoin, roster }

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
  bool _hostsLoading = false;
  String? _selectedHost;
  bool _connectWaiting = false;
  String? _connectHint;
  Timer? _connectPoll;

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
      unawaited(_loadTeam());
    }
    if (_step == OnboardingStep.connect) {
      unawaited(_loadHosts());
    }
    if (_status?.signedIn == true && _status?.configured != true) {
      unawaited(_refreshSignedInStatus());
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

  String? _orgFromHandle(String? handle) {
    if (handle == null || !handle.contains('@')) return null;
    return handle.split('@').last;
  }

  Set<OnboardingStep> get _completedBefore {
    final s = <OnboardingStep>{};
    if (_status?.signedIn == true || _status?.configured == true) {
      s.add(OnboardingStep.signIn);
    }
    if (_status?.configured == true && _teamMode == _TeamMode.roster) {
      s.add(OnboardingStep.team);
    }
    if (widget.firstRunStore.connectComplete) s.add(OnboardingStep.connect);
    if (widget.firstRunStore.notificationsComplete) {
      s.add(OnboardingStep.notifications);
    }
    return s;
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
        _hosts = detections
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

  Future<void> _beginConnectHost(String host) async {
    if (!_hosts.any((h) => h.slug == host && h.installed)) {
      _showNotDetectedSheet(host);
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
        if (agents.agents.any((a) => a.slug.toLowerCase() == host.toLowerCase())) {
          await widget.firstRunStore.markConnectComplete();
          if (!mounted) return;
          setState(() {
            _connectWaiting = false;
            _step = OnboardingStep.notifications;
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

  void _showNotDetectedSheet(String host) {
    final label = AiHostIcon.displayName(host);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MutandeColors.stone50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$label not detected',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: MutandeColors.stone800,
                  ),
            ),
            const SizedBox(height: OnboardingSpace.xs),
            Text(
              'Install $label on this Mac first, then return here. '
              'mutande won’t treat config folders alone as installed.',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: MutandeColors.stone500,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: OnboardingSpace.lg),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    if (Platform.isMacOS) {
      try {
        await Process.run('open', [
          'x-apple.systempreferences:com.apple.Notifications-Settings.extension',
        ]);
      } catch (_) {}
    }
  }

  Future<void> _copyInviteLink() async {
    final base = widget.config.webAppUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/admin/invites';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied invite link: $url')),
    );
  }

  Future<void> _openInvitesWeb() async {
    final base = widget.config.webAppUrl.replaceAll(RegExp(r'/+$'), '');
    await Process.run('open', ['$base/admin/invites']);
  }

  void _skipNotifications() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip notifications?'),
        content: const Text(
          'Without notifications, you’ll need to check Threads yourself. '
          'Agents still deliver mail.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_finishNotifications(skipped: true));
            },
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishNotifications({bool skipped = false}) async {
    await widget.firstRunStore.markNotificationsComplete(skipped: skipped);
    if (!mounted) return;
    setState(() => _step = OnboardingStep.ping);
  }

  @override
  Widget build(BuildContext context) {
    if (_securing) {
      return OnboardingShell(
        step: OnboardingStep.signIn,
        centerContent: true,
        contentMaxWidth: 420,
        debugBanner: widget.forceDebug ? 'Debug — onboarding preview' : null,
        child: _securingBody(),
      );
    }
    if (_welcomeBack) {
      return _welcomeBackOverlay();
    }

    switch (_step) {
      case OnboardingStep.signIn:
        return OnboardingShell(
          step: _step,
          completedBefore: _completedBefore,
          debugBanner: widget.forceDebug ? 'Debug — onboarding preview' : null,
          child: _signInBody(),
        );
      case OnboardingStep.team:
        return OnboardingShell(
          step: _step,
          completedBefore: _completedBefore,
          debugBanner: widget.forceDebug ? 'Debug — onboarding preview' : null,
          child: _teamBody(),
        );
      case OnboardingStep.connect:
        return OnboardingShell(
          step: _step,
          completedBefore: _completedBefore,
          debugBanner: widget.forceDebug ? 'Debug — onboarding preview' : null,
          contentMaxWidth: 640,
          child: _connectBody(),
        );
      case OnboardingStep.notifications:
        return OnboardingShell(
          step: _step,
          completedBefore: _completedBefore,
          debugBanner: widget.forceDebug ? 'Debug — onboarding preview' : null,
          child: _notificationsBody(),
        );
      case OnboardingStep.ping:
        return OnboardingShell(
          step: _step,
          completedBefore: _completedBefore,
          debugBanner: widget.forceDebug ? 'Debug — onboarding preview' : null,
          child: FirstRunPingWizard(
            daemon: widget.daemon,
            firstRunStore: widget.firstRunStore,
            embedded: true,
            onComplete: (threadId) {
              final status = _status;
              if (status != null) {
                widget.onComplete(status, threadId);
              }
            },
          ),
        );
    }
  }

  Widget _welcomeBackOverlay() {
    final handle = _status?.handle ?? '';
    final org = _orgFromHandle(_status?.handle);
    return Scaffold(
      backgroundColor: MutandeColors.stone800,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MutandeOrb.standard(semanticLabel: 'Welcome back'),
            const SizedBox(height: OnboardingSpace.lg),
            Text(
              handle.isNotEmpty ? 'Welcome back, $handle' : 'Welcome back',
              style: OnboardingHeading.displayTitleStyle(
                Theme.of(context),
              ).copyWith(
                color: MutandeColors.stone50,
                fontSize: 34,
              ),
            ),
            if (org != null) ...[
              const SizedBox(height: OnboardingSpace.xs),
              Text(
                'You\'re on $org',
                style: const TextStyle(
                  color: MutandeColors.stone400,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
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
      return const Center(
        child: MutandeOrb.standard(semanticLabel: 'Loading team…'),
      );
    }
    final handle = _status?.handle ?? '';
    final org = _orgFromHandle(_status?.handle) ?? '';
    final humans =
        _contacts.where((c) => !c.isBroadcast && !c.isExternal).toList();
    final solo = humans.length <= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Your team',
          subtitle: handle.isNotEmpty ? '$handle on $org' : 'Your org members',
        ),
        const SizedBox(height: OnboardingSpace.lg),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MutandeColors.stone200),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: OnboardingSpace.md,
            vertical: OnboardingSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (solo)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'You\'re the only one here yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: MutandeColors.stone600,
                        ),
                  ),
                )
              else
                ...humans.map(
                  (c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 18,
                          color: MutandeColors.stone500,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            formatMailAddress(c.handle, myHandle: handle),
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: MutandeColors.stone800,
                            ),
                          ),
                        ),
                        if (c.handle == handle)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: MutandeColors.amberSoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'you',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: MutandeColors.amber,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: OnboardingSpace.lg),
        const Divider(color: MutandeColors.stone200, height: 1),
        const SizedBox(height: OnboardingSpace.lg),
        Text(
          'Invite teammates',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: MutandeColors.stone800,
              ),
        ),
        const SizedBox(height: OnboardingSpace.xs),
        Text(
          'Teammates need mutande on Mac to receive agent mail.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: MutandeColors.stone500,
                height: 1.4,
              ),
        ),
        OnboardingActions(
          topSpacing: OnboardingSpace.sm,
          primary: FilledButton(
            onPressed: () {
              setState(() => _step = OnboardingStep.connect);
              unawaited(_loadHosts());
            },
            child: const Text('Continue'),
          ),
          secondary: OutlinedButton(
            onPressed: _copyInviteLink,
            child: const Text('Copy invite link'),
          ),
          tertiary: TextButton(
            onPressed: _openInvitesWeb,
            child: const Text('Open invites on web'),
          ),
        ),
      ],
    );
  }

  Widget _teamSetupBody() {
    final title = switch (_teamMode) {
      _TeamMode.setupChoose => 'Set up your team',
      _TeamMode.setupCreate => 'Create a team',
      _ => 'Join with invite',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: title,
          subtitle: _teamMode == _TeamMode.setupChoose
              ? 'Create a new team, or join one you\'ve been invited to.'
              : null,
        ),
        const SizedBox(height: OnboardingSpace.lg),
        if (_teamMode == _TeamMode.setupChoose) ...[
          OnboardingActions(
            topSpacing: 0,
            primary: FilledButton(
              onPressed: () => setState(() => _teamMode = _TeamMode.setupCreate),
              child: const Text('Create a team'),
            ),
            secondary: OutlinedButton(
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
              onPressed: () => setState(() => _teamMode = _TeamMode.setupChoose),
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
              onPressed: () => setState(() => _teamMode = _TeamMode.setupChoose),
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
      return const Center(
        child: MutandeOrb.standard(semanticLabel: 'Detecting hosts…'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          variant: OnboardingHeadingVariant.display,
          title: 'Connect an AI host',
          subtitle:
              'Pick one host with the desktop app installed. MCP + skill in two steps.',
        ),
        const SizedBox(height: OnboardingSpace.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _hosts.length; i++) ...[
              if (i > 0) const SizedBox(width: OnboardingSpace.sm),
              Expanded(
                child: _HostTile(
                  presence: _hosts[i],
                  onTap: () => _beginConnectHost(_hosts[i].slug),
                ),
              ),
            ],
          ],
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
          ),
      ],
    );
  }

  Widget _notificationsBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MutandeColors.amberSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.notifications_outlined,
                size: 22,
                color: MutandeColors.amber,
              ),
            ),
            const SizedBox(width: OnboardingSpace.md),
            const Expanded(
              child: OnboardingHeading(
                variant: OnboardingHeadingVariant.display,
                title: 'Allow notifications',
                subtitle:
                    'So mutande can tell you when an agent has new mail — even when '
                    'you\'re in another app. Banners are metadata only, never message bodies.',
              ),
            ),
          ],
        ),
        OnboardingActions(
          primary: FilledButton(
            onPressed: _openNotificationSettings,
            child: const Text('Open Notification Settings'),
          ),
          secondary: OutlinedButton(
            onPressed: () => _finishNotifications(),
            child: const Text('I\'ve allowed notifications'),
          ),
          tertiary: TextButton(
            onPressed: _skipNotifications,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({required this.presence, required this.onTap});

  final AiHostPresence presence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = !presence.installed;
    final badge = presence.primaryBadge;
    final linked = presence.linked && presence.agentRegistered;
    final label = AiHostIcon.displayName(presence.slug);

    return Semantics(
      button: true,
      label: '$label, $badge',
      child: Material(
        color: linked
            ? MutandeColors.emeraldSoft
            : muted
                ? MutandeColors.stone100
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: linked
                    ? const Color(0xFF86EFAC)
                    : MutandeColors.stone200,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Opacity(
                  opacity: muted ? 0.4 : 1,
                  child: AiHostIcon(presence.slug, size: 36),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: -0.1,
                    color: muted
                        ? MutandeColors.stone400
                        : MutandeColors.stone800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  badge,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: badge == 'Not detected'
                        ? MutandeColors.stone400
                        : badge == 'Connected'
                            ? MutandeColors.emerald
                            : MutandeColors.amber,
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
