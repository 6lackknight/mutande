import 'package:flutter/material.dart';

import 'thinking_orb.dart';

/// Dark welcome beat — working orb on black for a short fixed hold.
class WelcomeSplash extends StatefulWidget {
  const WelcomeSplash({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 3),
  });

  final Widget child;
  final Duration duration;

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
    if (!_showSplash) return widget.child;

    return const ColoredBox(
      color: Color(0xFF0C0A09),
      child: Center(
        child: ThinkingOrb(
          state: ThinkingOrbState.working,
          size: ThinkingOrbSize.panel,
          dark: true,
          semanticLabel: 'Welcome',
        ),
      ),
    );
  }
}
