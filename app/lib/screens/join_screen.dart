import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/daemon_client.dart';
import '../widgets/thinking_orb.dart';

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
    final signedIn = widget.status?.signedIn == true ||
        widget.status?.needsOnboarding == true;
    _step = signedIn ? _OnboardStep.choose : _OnboardStep.signIn;
    _email = widget.status?.email;
    _slug = TextEditingController();
    _orgName = TextEditingController();
    _handle = TextEditingController();
    _invite = TextEditingController();
  }

  @override
  void dispose() {
    _slug.dispose();
    _orgName.dispose();
    _handle.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
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
        widget.onOnboarded(status);
        return;
      }
      setState(() {
        _submitting = false;
        _email = status.email;
        _step = _OnboardStep.choose;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
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
    try {
      await widget.daemon.createOrg(
        slug: slug,
        name: _orgName.text.trim().isEmpty ? null : _orgName.text.trim(),
        handle: handle.isEmpty ? null : handle,
      );
      final status = await widget.daemon.getStatus();
      if (!mounted) return;
      widget.onOnboarded(status);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
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
    try {
      await widget.daemon.joinOrg(
        inviteCode: invite,
        handle: handle.isEmpty ? null : handle,
      );
      final status = await widget.daemon.getStatus();
      if (!mounted) return;
      widget.onOnboarded(status);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _JoinAtmosphere()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandMark(),
                      const SizedBox(height: 28),
                      Text(
                        _title(),
                        style: text.titleLarge?.copyWith(
                          color: const Color(0xFF292524),
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle(),
                        style: text.bodyMedium?.copyWith(
                          color: const Color(0xFF78716C),
                          height: 1.35,
                        ),
                      ),
                      if (_email != null && _email!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _email!,
                          style: text.bodySmall?.copyWith(
                            color: const Color(0xFF57534E),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      ..._stepBody(text),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: text.bodySmall?.copyWith(
                            color: const Color(0xFF991B1B),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
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
        return 'Use the same Auth0 account as the web app. A browser window will open.';
      case _OnboardStep.choose:
        return 'Create a new org or join one you were invited to.';
      case _OnboardStep.createTeam:
        return 'Pick a team slug and optional handle.';
      case _OnboardStep.joinInvite:
        return 'Paste the invite code from your admin.';
    }
  }

  List<Widget> _stepBody(TextTheme text) {
    switch (_step) {
      case _OnboardStep.signIn:
        return [
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _submitting ? null : _signIn,
              child: _submitting
                  ? const MutandeOrb.loading(semanticLabel: 'Signing in…')
                  : const Text('Sign in with Auth0'),
            ),
          ),
        ];
      case _OnboardStep.choose:
        return [
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _error = null;
                        _step = _OnboardStep.createTeam;
                      }),
              child: const Text('Create a team'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _error = null;
                        _step = _OnboardStep.joinInvite;
                      }),
              child: const Text('I have an invite'),
            ),
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
          const SizedBox(height: 22),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _submitting ? null : _createTeam,
              child: _submitting
                  ? const MutandeOrb.loading(semanticLabel: 'Creating…')
                  : const Text('Create team'),
            ),
          ),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _error = null;
                      _step = _OnboardStep.choose;
                    }),
            child: const Text('Back'),
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
          const SizedBox(height: 22),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _submitting ? null : _joinInvite,
              child: _submitting
                  ? const MutandeOrb.loading(semanticLabel: 'Joining…')
                  : const Text('Join team'),
            ),
          ),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _error = null;
                      _step = _OnboardStep.choose;
                    }),
            child: const Text('Back'),
          ),
        ];
    }
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
            color: const Color(0xFF57534E),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/tray_icon.png',
            width: 44,
            height: 44,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'mutande',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF292524),
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
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
          center: Alignment(0, -0.35),
          radius: 1.15,
          colors: [
            Color(0xFFFAFAF9),
            Color(0xFFF5F5F4),
            Color(0xFFE7E5E4),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: CustomPaint(painter: _GrainPainter()),
    );
  }
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0A44403C);
    const step = 6.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        if (((x + y * 3).toInt() * 17) % 11 == 0) {
          canvas.drawCircle(Offset(x, y), 0.6, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
