import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Quiet enter after skeleton/empty (list rows, reading-pane messages).
/// Opacity + 3px rise, no scale.
///
/// Plays once per [MutandeStaggerScope] mount. Inbox polls, selection, and
/// later rows do not replay — the gate freezes after the first frame.
class MutandeStaggerScope extends StatefulWidget {
  /// Delay between successive visible rows. Mail lists are long; 40ms keeps
  /// the last slotted row starting by [maxDelay].
  static const Duration stagger = Duration(milliseconds: 40);

  /// Form / dialog sections. 100–150ms; lists stay at [stagger].
  static const Duration sectionStagger = Duration(milliseconds: 120);

  /// First visible rows only. `(maxItems - 1) * stagger` = 240ms.
  static const int maxItems = 7;

  /// Last slotted row starts by this mark (200–250ms cap).
  static const Duration maxDelay = Duration(milliseconds: 240);

  static const double translateY = 3;

  const MutandeStaggerScope({
    super.key,
    required this.child,
    this.delay = stagger,
  });

  final Widget child;

  /// Gap before each successive slot. Lists use [stagger]; dialogs [sectionStagger].
  final Duration delay;

  static _StaggerInherited? _of(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_StaggerInherited>();
  }

  @override
  State<MutandeStaggerScope> createState() => _MutandeStaggerScopeState();
}

class _MutandeStaggerScopeState extends State<MutandeStaggerScope> {
  final _StaggerGate _gate = _StaggerGate();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gate.freeze();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gate.enabled = !MediaQuery.disableAnimationsOf(context);
  }

  @override
  Widget build(BuildContext context) {
    return _StaggerInherited(
      gate: _gate,
      delay: widget.delay,
      child: widget.child,
    );
  }
}

class _StaggerGate {
  bool enabled = true;
  bool _frozen = false;
  final Map<Object, int> _slots = {};

  int claim(Object id) {
    if (!enabled) return -1;
    final existing = _slots[id];
    if (existing != null) return existing;
    if (_frozen || _slots.length >= MutandeStaggerScope.maxItems) return -1;
    final slot = _slots.length;
    _slots[id] = slot;
    return slot;
  }

  void freeze() => _frozen = true;
}

class _StaggerInherited extends InheritedWidget {
  const _StaggerInherited({
    required this.gate,
    required this.delay,
    required super.child,
  });

  final _StaggerGate gate;
  final Duration delay;

  @override
  bool updateShouldNotify(_StaggerInherited old) => false;
}

/// One row in a [MutandeStaggerScope]. Without a scope, or after the gate
/// freezes, [child] is shown at rest.
class MutandeStaggerIn extends StatefulWidget {
  const MutandeStaggerIn({super.key, required this.id, required this.child});

  final Object id;
  final Widget child;

  @override
  State<MutandeStaggerIn> createState() => _MutandeStaggerInState();
}

class _MutandeStaggerInState extends State<MutandeStaggerIn>
    with SingleTickerProviderStateMixin {
  int? _slot;
  AnimationController? _controller;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_slot != null) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _slot = -1;
      return;
    }
    final motion = MutandeMotion.of(context, MutandeMotion.ui);
    final inherited = MutandeStaggerScope._of(context);
    final slot = inherited?.gate.claim(widget.id) ?? -1;
    _slot = slot;
    if (slot < 0 || motion == Duration.zero) {
      _slot = -1;
      return;
    }
    _controller = AnimationController(vsync: this, duration: motion);
    final step =
        inherited?.delay.inMilliseconds ??
        MutandeStaggerScope.stagger.inMilliseconds;
    final delay = Duration(
      milliseconds: (step * slot).clamp(
        0,
        MutandeStaggerScope.maxDelay.inMilliseconds,
      ),
    );
    if (delay == Duration.zero) {
      _controller!.forward();
    } else {
      _delay = Timer(delay, () {
        if (mounted) _controller?.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = MutandeMotion.easeOut.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * MutandeStaggerScope.translateY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
