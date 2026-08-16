import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../services/daemon_errors.dart';
import '../theme/mutande_macos_theme.dart';
import 'morphing_orb_button.dart';
import 'onboarding_chrome.dart';

/// Distilled full-screen state when bootstrap cannot load session status.
class DaemonErrorScreen extends StatefulWidget {
  const DaemonErrorScreen({
    super.key,
    required this.error,
    required this.endpoint,
    this.daemonReachable = false,
    this.lastKnownHandle,
    required this.onRetry,
    this.onRestartCourier,
    this.onSignIn,
    this.onSignedIn,
  });

  final String error;
  final String endpoint;
  final bool daemonReachable;
  final String? lastKnownHandle;
  final VoidCallback onRetry;

  /// When set, shows a tertiary action to stop and respawn mutande-core.
  final Future<void> Function()? onRestartCourier;

  /// Auth0 PKCE/browser login (same path as onboarding). Null when courier is down.
  final Future<DaemonStatusResult> Function()? onSignIn;
  final Future<void> Function(DaemonStatusResult status)? onSignedIn;

  @override
  State<DaemonErrorScreen> createState() => _DaemonErrorScreenState();
}

class _DaemonErrorScreenState extends State<DaemonErrorScreen> {
  bool _detailsOpen = false;
  bool _restarting = false;
  bool _signingIn = false;
  bool _signInLocked = false;
  String? _signInError;

  bool get _busy => _restarting || _signingIn || _signInLocked;

  DaemonErrorKind get _kind => classifyDaemonError(
        error: widget.error,
        daemonReachable: widget.daemonReachable,
      );

  Future<void> _restart() async {
    final restart = widget.onRestartCourier;
    if (restart == null || _busy) return;
    setState(() {
      _restarting = true;
      _signInError = null;
    });
    try {
      await restart();
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  Future<void> _signIn() async {
    final signIn = widget.onSignIn;
    if (signIn == null || _busy) return;
    _signInLocked = true;
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      final status = await signIn();
      if (!mounted) return;
      final done = widget.onSignedIn;
      if (done != null) await done(status);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signInError = _friendlySignInError(e);
      });
    } finally {
      _signInLocked = false;
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final copy = daemonErrorCopy(
      kind,
      daemonReachable: widget.daemonReachable,
      handle: widget.lastKnownHandle,
    );
    final showSignIn =
        daemonErrorOffersSignIn(kind) && widget.onSignIn != null;
    final showRestart = daemonErrorOffersRestart(kind) &&
        widget.onRestartCourier != null;
    final accent = kind == DaemonErrorKind.keychainOrStarting
        ? MutandeColors.amber
        : MutandeColors.bronze;
    final icon = switch (kind) {
      DaemonErrorKind.keychainOrStarting => Icons.lock_outline,
      DaemonErrorKind.sessionExpired => Icons.login_outlined,
      DaemonErrorKind.hubTimeout => Icons.hourglass_empty,
      DaemonErrorKind.hubUnreachable => Icons.cloud_off_outlined,
      DaemonErrorKind.courierDown => Icons.cloud_off_outlined,
    };

    return Scaffold(
      backgroundColor: MutandeColors.stone100,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: 40, color: accent.withValues(alpha: 0.9)),
                  const SizedBox(height: 28),
                  Text(
                    'mutande',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: MutandeColors.stone800,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    copy.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: MutandeColors.stone800,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: MutandeColors.stone600,
                          height: 1.45,
                        ),
                  ),
                  if (_signInError != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: OnboardingErrorBanner(message: _signInError!),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (showSignIn)
                    MorphingOrbButton(
                      label: 'Sign in',
                      loading: _signingIn,
                      loadingLabel: 'Signing in…',
                      onPressed: _busy ? null : _signIn,
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : widget.onRetry,
                        child: Text(_restarting ? 'Restarting…' : 'Retry'),
                      ),
                    ),
                  if (showSignIn) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : widget.onRetry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MutandeColors.stone800,
                          side: const BorderSide(color: MutandeColors.stone200),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: -0.1,
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                  if (showRestart) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: showSignIn
                          ? TextButton(
                              onPressed: _busy ? null : _restart,
                              style: TextButton.styleFrom(
                                foregroundColor: MutandeColors.bronze,
                                minimumSize: const Size(44, 44),
                              ),
                              child: Text(
                                _restarting
                                    ? 'Restarting courier…'
                                    : 'Restart courier',
                              ),
                            )
                          : OutlinedButton(
                              onPressed: _busy ? null : _restart,
                              child: Text(
                                _restarting
                                    ? 'Restarting courier…'
                                    : 'Restart courier',
                              ),
                            ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _detailsOpen = !_detailsOpen),
                    style: TextButton.styleFrom(
                      foregroundColor: MutandeColors.stone500,
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(_detailsOpen ? 'Hide details' : 'Details'),
                  ),
                  AnimatedCrossFade(
                    duration: MutandeMotion.of(
                      context,
                      const Duration(milliseconds: 180),
                    ),
                    crossFadeState: _detailsOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            'HTTP: ${widget.endpoint}\n\n${_scrubError(widget.error)}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: MutandeColors.stone400,
                                      height: 1.4,
                                    ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _friendlySignInError(Object e) {
    final base = friendlyDaemonError(e, what: 'Sign-in');
    final lower = base.toLowerCase();
    if (lower.contains('get /v1/me') || lower.contains('after auth0')) {
      return 'Browser sign-in worked, but the hub rejected the session. Try again.';
    }
    if (lower.contains('open settings')) {
      return 'Sign-in was rejected. Try again with the same account you use on the web.';
    }
    return base;
  }

  String _scrubError(String raw) {
    var msg = raw;
    for (final prefix in [
      'DaemonException: ',
      'Exception: ',
      'ClientException: ',
    ]) {
      if (msg.startsWith(prefix)) {
        msg = msg.substring(prefix.length);
      }
    }
    return msg;
  }
}
