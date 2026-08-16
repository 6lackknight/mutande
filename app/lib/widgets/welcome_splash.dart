import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/mutande_macos_theme.dart';
import 'thinking_orb.dart';

/// Stitch launcher splash — dark hold with working orb + wordmark.
///
/// [child] stays mounted under the overlay so RootScreen / tray listeners
/// keep running during the hold.
///
/// Dismisses after [duration] *and* [dismissWhen] is true (when provided),
/// so Keychain authorization keeps the branded splash instead of a blank wait.
class WelcomeSplash extends StatefulWidget {
  const WelcomeSplash({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 3),
    this.appVersion = '1.0.0',
    this.dismissWhen,
    this.statusLabel,
  });

  final Widget child;
  final Duration duration;

  /// Display version from pubspec (`version:` before `+`).
  final String appVersion;

  /// When set, splash stays until this is true (and [duration] has elapsed).
  final ValueListenable<bool>? dismissWhen;

  /// Optional status under the wordmark (e.g. Waiting for Keychain).
  final ValueListenable<String?>? statusLabel;

  @override
  State<WelcomeSplash> createState() => _WelcomeSplashState();
}

class _WelcomeSplashState extends State<WelcomeSplash> {
  bool _showSplash = true;
  bool _splashOpaque = true;
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    widget.dismissWhen?.addListener(_onDismissSignal);
    if (widget.duration <= Duration.zero) {
      _minElapsed = true;
      _tryDismiss();
      return;
    }
    Future<void>.delayed(widget.duration, () {
      if (!mounted) return;
      _minElapsed = true;
      _tryDismiss();
    });
  }

  @override
  void didUpdateWidget(covariant WelcomeSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dismissWhen != widget.dismissWhen) {
      oldWidget.dismissWhen?.removeListener(_onDismissSignal);
      widget.dismissWhen?.addListener(_onDismissSignal);
      _tryDismiss();
    }
  }

  @override
  void dispose() {
    widget.dismissWhen?.removeListener(_onDismissSignal);
    super.dispose();
  }

  void _onDismissSignal() => _tryDismiss();

  void _tryDismiss() {
    if (!_showSplash || !_minElapsed) return;
    final gate = widget.dismissWhen;
    if (gate != null && !gate.value) return;

    void dismiss() {
      if (!mounted || !_showSplash) return;
      final g = widget.dismissWhen;
      if (g != null && !g.value) return;
      if (widget.duration <= Duration.zero) {
        setState(() => _showSplash = false);
        return;
      }
      final reduce = MediaQuery.disableAnimationsOf(context);
      if (reduce) {
        setState(() => _showSplash = false);
        return;
      }
      setState(() => _splashOpaque = false);
    }

    // Safe during post-frame callbacks (bootstrap notify); defer if mid-build.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      dismiss();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => dismiss());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_splashOpaque,
              child: AnimatedOpacity(
                opacity: _splashOpaque ? 1 : 0,
                duration: MutandeMotion.ui,
                curve: MutandeMotion.easeOut,
                onEnd: () {
                  if (!_splashOpaque && mounted) {
                    setState(() => _showSplash = false);
                  }
                },
                child: ColoredBox(
                  color: const Color(0xFF0C0A09),
                  child: Stack(
                fit: StackFit.expand,
                children: [
                  const _MidGlow(),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: Column(
                        children: [
                          const Spacer(flex: 3),
                          const MutandeOrb.standard(
                            dark: true,
                            semanticLabel: 'Starting',
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'mutande',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: const Color(0xFFFAFAF9),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.8,
                                  fontSize: 36,
                                  height: 1,
                                ),
                          ),
                          const SizedBox(height: 18),
                          _StatusLine(statusLabel: widget.statusLabel),
                          const Spacer(flex: 4),
                          _Footer(version: widget.appVersion),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MidGlow extends StatelessWidget {
  const _MidGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.08),
            radius: 0.85,
            colors: [
              const Color(0xFF292524).withValues(alpha: 0.55),
              const Color(0xFF0C0A09).withValues(alpha: 0),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({this.statusLabel});

  final ValueListenable<String?>? statusLabel;

  @override
  Widget build(BuildContext context) {
    final labelListenable = statusLabel;
    if (labelListenable == null) {
      return const _StatusText(label: 'STARTING');
    }
    return ValueListenableBuilder<String?>(
      valueListenable: labelListenable,
      builder: (context, value, _) {
        final raw = value?.trim();
        final label = (raw == null || raw.isEmpty)
            ? 'STARTING'
            : raw.toUpperCase();
        return _StatusText(label: label);
      },
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Color(0xFFE7E5E4),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFFA8A29E),
                fontWeight: FontWeight.w500,
                letterSpacing: 1.8,
                fontSize: 11,
              ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF57534E),
          fontSize: 11,
          letterSpacing: 0.2,
        );
    return Column(
      children: [
        const Divider(height: 1, thickness: 1, color: Color(0xFF292524)),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('v$version', style: style),
            const Spacer(),
            Text('macOS', style: style),
          ],
        ),
      ],
    );
  }
}
