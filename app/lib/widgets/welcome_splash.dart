import 'package:flutter/material.dart';

import 'thinking_orb.dart';

/// Stitch launcher splash — dark hold with working orb + wordmark.
///
/// [child] stays mounted under the overlay so RootScreen / tray listeners
/// keep running during the hold.
class WelcomeSplash extends StatefulWidget {
  const WelcomeSplash({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 3),
    this.appVersion = '1.0.0',
  });

  final Widget child;
  final Duration duration;

  /// Display version from pubspec (`version:` before `+`).
  final String appVersion;

  @override
  State<WelcomeSplash> createState() => _WelcomeSplashState();
}

class _WelcomeSplashState extends State<WelcomeSplash> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    if (widget.duration <= Duration.zero) {
      _showSplash = false;
      return;
    }
    Future<void>.delayed(widget.duration, () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
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
                          const ThinkingOrb(
                            state: ThinkingOrbState.working,
                            size: ThinkingOrbSize.panel,
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
                          const _StatusLine(),
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
  const _StatusLine();

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
          'STARTING',
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
