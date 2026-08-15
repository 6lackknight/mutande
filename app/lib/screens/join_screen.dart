import 'dart:async';

import 'package:flutter/material.dart';

import '../analytics_events.dart';
import '../config/app_config.dart';
import '../services/analytics.dart';
import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../widgets/home_chrome_buttons.dart';
import '../widgets/morphing_orb_button.dart';

enum _OnboardStep { signIn, choose, createTeam, joinInvite }

/// Auth0 sign-in → create team or join invite (same account as web).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.config,
    required this.daemon,
    this.status,
    required this.onOnboarded,
  });

  final AppConfig config;
  final DaemonClient daemon;
  final DaemonStatusResult? status;
  final void Function(DaemonStatusResult status) onOnboarded;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late _OnboardStep _step;
  late final TextEditingController _slug;
  late final TextEditingController _orgName;
  late final TextEditingController _handle;
  late final TextEditingController _invite;
  bool _submitting = false;
  String? _error;
  String? _email;

  @override
  void initState() {
    super.initState();
    // Only skip Sign in when hub confirmed signed-in + needs org setup.
    // Never treat a bare needsOnboarding flag (or hub blip) as create/join.
    final needsOrg =
        widget.status?.signedIn == true &&
        widget.status?.needsOnboarding == true &&
        widget.status?.configured != true;
    _step = needsOrg ? _OnboardStep.choose : _OnboardStep.signIn;
    _email = widget.status?.email;
    _slug = TextEditingController();
    _orgName = TextEditingController();
    _handle = TextEditingController();
    _invite = TextEditingController();
    if (needsOrg) {
      // Re-check hub: user may have joined on web since local tokens were saved.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refreshIfAlreadyOnboarded());
      });
    }
  }

  Future<void> _refreshIfAlreadyOnboarded() async {
    try {
      final status = await widget.daemon.getStatus();
      if (!mounted) return;
      if (status.configured) {
        widget.onOnboarded(status);
        return;
      }
      if (status.signedIn && status.needsOnboarding) {
        setState(() {
          _email = status.email ?? _email;
          _step = _OnboardStep.choose;
        });
      }
    } catch (_) {
      // Leave choose/sign-in as-is; transport errors are handled at RootScreen.
    }
  }

  Future<void> _finishIfConfigured() async {
    final status = await widget.daemon.getStatus();
    if (!mounted) return;
    if (status.configured) {
      widget.onOnboarded(status);
      return;
    }
    throw StateError('Still needs team setup');
  }

  @override
  void dispose() {
    _slug.dispose();
    _orgName.dispose();
    _handle.dispose();
    _invite.dispose();
    super.dispose();
  }

  String _friendlyError(Object e, {required String what}) {
    final base = friendlyDaemonError(e, what: what);
    final lower = base.toLowerCase();
    if (lower.contains('get /v1/me') || lower.contains('after auth0')) {
      return 'Browser sign-in worked, but the hub rejected the session. Try again.';
    }
    if (lower.contains('open settings') && _step == _OnboardStep.signIn) {
      return 'Sign-in was rejected. Try again with the same account you use on the web.';
    }
    return base;
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
        widget.onOnboarded(status);
        return;
      }
      Analytics.track(AnalyticsEvent.signInSuccess, {'needs_org': true});
      setState(() {
        _submitting = false;
        _email = status.email;
        _step = _OnboardStep.choose;
      });
    } catch (e) {
      if (!mounted) return;
      Analytics.track(AnalyticsEvent.signInFailure, {'reason': 'auth_error'});
      setState(() {
        _submitting = false;
        _error = _friendlyError(e, what: 'Sign-in');
      });
    }
  }

  Future<void> _createTeam() async {
    final slug = _slug.text.trim().toLowerCase();
    final handle = _handle.text.trim();
    if (slug.isEmpty) {
      setState(() => _error = 'Team slug is required.');
      return;
    }
    if (!RegExp(r'^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$').hasMatch(slug)) {
      setState(
        () => _error = 'Slug must be lowercase letters, numbers, hyphens.',
      );
      return;
    }
    if (handle.isNotEmpty && handle.contains('@')) {
      final handleErr = validateHandle(handle);
      if (handleErr != null) {
        setState(() => _error = handleErr);
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Analytics.track(AnalyticsEvent.createTeamClick);
    try {
      await widget.daemon.createOrg(
        slug: slug,
        name: _orgName.text.trim().isEmpty ? null : _orgName.text.trim(),
        handle: handle.isEmpty ? null : handle,
      );
      await _finishIfConfigured();
      Analytics.track(AnalyticsEvent.createTeamSuccess);
    } catch (e) {
      if (!mounted) return;
      // Web join may have completed for this Auth0 account already.
      if (_looksAlreadyOnboarded(e)) {
        try {
          await _finishIfConfigured();
          Analytics.track(AnalyticsEvent.createTeamSuccess, {
            'already_onboarded': true,
          });
          return;
        } catch (_) {}
      }
      setState(() {
        _submitting = false;
        _error = _friendlyError(e, what: 'Create team');
      });
      Analytics.track(AnalyticsEvent.createTeamFailure, {
        'reason': 'create_error',
      });
    }
  }

  Future<void> _joinInvite() async {
    final invite = _invite.text.trim();
    final handle = _handle.text.trim();
    if (invite.isEmpty) {
      setState(() => _error = 'Invite code is required.');
      return;
    }
    if (handle.contains('@')) {
      final err = validateHandle(handle);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Analytics.track(AnalyticsEvent.joinInviteClick);
    try {
      await widget.daemon.joinOrg(
        inviteCode: invite,
        handle: handle.isEmpty ? null : handle,
      );
      await _finishIfConfigured();
      Analytics.track(AnalyticsEvent.joinInviteSuccess);
    } catch (e) {
      if (!mounted) return;
      if (_looksAlreadyOnboarded(e)) {
        try {
          await _finishIfConfigured();
          Analytics.track(AnalyticsEvent.joinInviteSuccess, {
            'already_onboarded': true,
          });
          return;
        } catch (_) {}
      }
      setState(() {
        _submitting = false;
        _error = _friendlyError(e, what: 'Join');
      });
      Analytics.track(AnalyticsEvent.joinInviteFailure, {
        'reason': 'join_error',
      });
    }
  }

  bool _looksAlreadyOnboarded(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('already onboarded') ||
        msg.contains('already a member') ||
        msg.contains('already has an organization');
  }

  bool get _welcomeStep =>
      _step == _OnboardStep.signIn || _step == _OnboardStep.choose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _JoinAtmosphere()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Column(
                      key: ValueKey(_step),
                      crossAxisAlignment: _welcomeStep
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.stretch,
                      children: [
                        const _BrandMark(),
                        SizedBox(height: _welcomeStep ? 40 : 32),
                        Text(
                          _title(),
                          textAlign: _welcomeStep
                              ? TextAlign.center
                              : TextAlign.start,
                          style: text.headlineSmall?.copyWith(
                            color: MutandeColors.stone800,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _subtitle(),
                          textAlign: _welcomeStep
                              ? TextAlign.center
                              : TextAlign.start,
                          style: text.bodyMedium?.copyWith(
                            color: MutandeColors.stone500,
                            height: 1.45,
                            fontSize: 14.5,
                          ),
                        ),
                        if (_email != null && _email!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _email!,
                            textAlign: _welcomeStep
                                ? TextAlign.center
                                : TextAlign.start,
                            style: text.bodySmall?.copyWith(
                              color: MutandeColors.stone600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        SizedBox(height: _welcomeStep ? 32 : 28),
                        ..._stepBody(text),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBanner(message: _error!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _title() {
    switch (_step) {
      case _OnboardStep.signIn:
        return 'Sign in';
      case _OnboardStep.choose:
        return 'Set up your team';
      case _OnboardStep.createTeam:
        return 'Create a team';
      case _OnboardStep.joinInvite:
        return 'Join with invite';
    }
  }

  String _subtitle() {
    switch (_step) {
      case _OnboardStep.signIn:
        return 'Same account as the web. Your browser will open to continue.';
      case _OnboardStep.choose:
        return 'Create a new team, or join one you’ve been invited to.';
      case _OnboardStep.createTeam:
        return 'Choose a slug for your team. Handle is optional.';
      case _OnboardStep.joinInvite:
        return 'Paste the invite code from your admin.';
    }
  }

  ButtonStyle get _secondaryStyle => HomeChromeButtons.outlined;

  Widget _ghostLink({required String label, required VoidCallback? onPressed}) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: MutandeColors.bronze,
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      child: Text(label),
    );
  }

  List<Widget> _stepBody(TextTheme text) {
    switch (_step) {
      case _OnboardStep.signIn:
        return [
          MorphingOrbButton(
            label: 'Continue',
            loading: _submitting,
            loadingLabel: 'Signing in…',
            onPressed: _submitting ? null : _signIn,
          ),
        ];
      case _OnboardStep.choose:
        return [
          MorphingOrbButton(
            label: 'Create a team',
            loading: false,
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _error = null;
                    _step = _OnboardStep.createTeam;
                  }),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: _secondaryStyle,
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _error = null;
                      _step = _OnboardStep.joinInvite;
                    }),
              child: const Text('I have an invite'),
            ),
          ),
          const SizedBox(height: 6),
          _ghostLink(
            label: 'Use a different account',
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _error = null;
                    _step = _OnboardStep.signIn;
                  }),
          ),
        ];
      case _OnboardStep.createTeam:
        return [
          const _FieldLabel('Team slug'),
          const SizedBox(height: 6),
          TextField(
            controller: _slug,
            decoration: const InputDecoration(hintText: 'acme'),
            enabled: !_submitting,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Team name (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _orgName,
            enabled: !_submitting,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Handle (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _handle,
            decoration: const InputDecoration(hintText: 'alice or alice@acme'),
            enabled: !_submitting,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createTeam(),
          ),
          const SizedBox(height: 24),
          MorphingOrbButton(
            label: 'Create team',
            loading: _submitting,
            loadingLabel: 'Creating…',
            onPressed: _submitting ? null : _createTeam,
          ),
          const SizedBox(height: 4),
          _ghostLink(
            label: 'Back',
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _error = null;
                    _step = _OnboardStep.choose;
                  }),
          ),
        ];
      case _OnboardStep.joinInvite:
        return [
          const _FieldLabel('Invite code'),
          const SizedBox(height: 6),
          TextField(
            controller: _invite,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Paste invite'),
            enabled: !_submitting,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Handle (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _handle,
            decoration: const InputDecoration(hintText: 'alice or alice@acme'),
            enabled: !_submitting,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _joinInvite(),
          ),
          const SizedBox(height: 24),
          MorphingOrbButton(
            label: 'Join team',
            loading: _submitting,
            loadingLabel: 'Joining…',
            onPressed: _submitting ? null : _joinInvite,
          ),
          const SizedBox(height: 4),
          _ghostLink(
            label: 'Back',
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _error = null;
                    _step = _OnboardStep.choose;
                  }),
          ),
        ];
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF9F1239),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: MutandeColors.stone600,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140C0A09),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/tray_icon.png',
              width: 52,
              height: 52,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'mutande',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'mutande',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: MutandeColors.stone800,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
            height: 1.05,
          ),
        ),
      ],
    );
  }
}

/// Soft stone wash — quiet atmosphere without a flat void.
class _JoinAtmosphere extends StatelessWidget {
  const _JoinAtmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.4),
          radius: 1.2,
          colors: [
            Color(0xFFFFFCF9),
            MutandeColors.stone50,
            MutandeColors.stone100,
            MutandeColors.stone200,
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
        ),
      ),
      child: const CustomPaint(painter: _GrainPainter()),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0844403C);
    const step = 7.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        if (((x + y * 3).toInt() * 17) % 13 == 0) {
          canvas.drawCircle(Offset(x, y), 0.55, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
