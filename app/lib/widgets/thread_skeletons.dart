import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'collab/collab_dash_card.dart';

/// Quiet bone for a loading bar — same stone as the list, no shine stripe.
class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height, this.circle = false});

  final double width;
  final double height;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MutandeColors.stone200,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// Shared breath: stone200 ↔ stone100. Holds still under reduced motion.
class _Breath extends StatefulWidget {
  const _Breath({required this.child});

  final Widget child;

  @override
  State<_Breath> createState() => _BreathState();
}

class _BreathState extends State<_Breath> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        _inWidgetTest ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (reduced) {
      _ctrl.stop();
      _ctrl.value = 0.45;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return ColorFiltered(
          colorFilter: ColorFilter.mode(
            Color.lerp(MutandeColors.stone200, MutandeColors.stone100, t)!,
            BlendMode.srcATop,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Fade + slight rise for staggered dashboard / list entrances.
class MutandeArrive extends StatelessWidget {
  const MutandeArrive({super.key, required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) return child;
    final duration = MutandeMotion.of(
      context,
      Duration(milliseconds: 320 + order * 50),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Interval(
        (order * 0.08).clamp(0.0, 0.55),
        1,
        curve: MutandeMotion.easeOut,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Inbox-shaped placeholder: mark · title · snippet · time.
class ThreadListSkeleton extends StatelessWidget {
  const ThreadListSkeleton({
    super.key,
    this.rows = 7,
    this.semanticLabel = 'Loading threads',
  });

  final int rows;
  final String semanticLabel;

  static const _widths = [0.62, 0.48, 0.71, 0.55, 0.66, 0.42, 0.58];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: _Breath(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: rows,
          itemBuilder: (context, i) {
            final titleW = _widths[i % _widths.length];
            return MutandeArrive(
              order: i,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 12, 11),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    const _Bone(width: 44, height: 44, circle: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: titleW,
                            child: const _Bone(
                              width: double.infinity,
                              height: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FractionallySizedBox(
                            widthFactor: (titleW + 0.18).clamp(0.5, 0.88),
                            child: const _Bone(
                              width: double.infinity,
                              height: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _Bone(width: 22, height: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reading pane: a quiet OP block, then a heavier latest line.
class ThreadReadingSkeleton extends StatelessWidget {
  const ThreadReadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading thread',
      child: _Breath(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MutandeArrive(
                order: 0,
                child: Row(
                  children: [
                    _Bone(width: 28, height: 28, circle: true),
                    SizedBox(width: 10),
                    _Bone(width: 120, height: 10),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const MutandeArrive(
                order: 1,
                child: _Bone(width: 220, height: 11),
              ),
              const SizedBox(height: 10),
              for (final w in [1.0, 0.92, 0.74]) ...[
                MutandeArrive(
                  order: 2,
                  child: FractionallySizedBox(
                    widthFactor: w,
                    child: const _Bone(width: double.infinity, height: 9),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 18),
              const MutandeArrive(
                order: 3,
                child: Row(
                  children: [
                    _Bone(width: 22, height: 22, circle: true),
                    SizedBox(width: 8),
                    _Bone(width: 88, height: 10),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const MutandeArrive(
                order: 4,
                child: FractionallySizedBox(
                  widthFactor: 0.86,
                  child: _Bone(width: double.infinity, height: 11),
                ),
              ),
              const SizedBox(height: 8),
              const MutandeArrive(
                order: 5,
                child: FractionallySizedBox(
                  widthFactor: 0.64,
                  child: _Bone(width: double.infinity, height: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashPlate extends StatelessWidget {
  const _DashPlate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: child,
    );
  }
}

/// Metric value bones — labels stay on [CollabMetricRow].
class CollabMetricValueSkeleton extends StatelessWidget {
  const CollabMetricValueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Bone(width: 28, height: 22);
  }
}

/// Activity chart bones — title and subtitle stay on [CollabActivityCalendar].
class CollabActivitySkeleton extends StatelessWidget {
  const CollabActivitySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading activity',
      child: CollabDashCard(
        height: kCollabChartCardHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activity',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MutandeColors.stone800,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Card updates across all collabs',
              style: TextStyle(fontSize: 11, color: MutandeColors.stone500),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _Breath(
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: Wrap(
                          spacing: 3,
                          runSpacing: 3,
                          children: [
                            for (var i = 0; i < 28; i++)
                              _Bone(width: 11, height: 11),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: MutandeColors.stone200),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Column(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                const Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _Bone(width: 96, height: 9),
                                          SizedBox(height: 4),
                                          _Bone(width: 72, height: 8),
                                        ],
                                      ),
                                    ),
                                    _Bone(width: 24, height: 8),
                                  ],
                                ),
                              ],
                            ],
                          ),
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
    );
  }
}

/// Lanes chart bones — title and subtitle stay on [CollabLaneDonut].
class CollabLanesSkeleton extends StatelessWidget {
  const CollabLanesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading lanes',
      child: CollabDashCard(
        height: kCollabChartCardHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lanes',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MutandeColors.stone800,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Open cards by lane',
              style: TextStyle(fontSize: 11, color: MutandeColors.stone500),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _Breath(
                child: Row(
                  children: [
                    const _Bone(width: 108, height: 108, circle: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            const Row(
                              children: [
                                _Bone(width: 8, height: 8, circle: true),
                                SizedBox(width: 8),
                                Expanded(child: _Bone(width: 48, height: 9)),
                                _Bone(width: 16, height: 9),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collab table rows only — heading and column labels stay on the table.
class CollabTableRowsSkeleton extends StatelessWidget {
  const CollabTableRowsSkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading collabs',
      child: _Breath(
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              MutandeArrive(
                order: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      _Bone(width: 26, height: 26, circle: true),
                      SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: _Bone(width: double.infinity, height: 9),
                      ),
                      SizedBox(width: 16),
                      Expanded(child: _Bone(width: double.infinity, height: 8)),
                      SizedBox(width: 16),
                      _Bone(width: 28, height: 8),
                    ],
                  ),
                ),
              ),
              if (i < rows - 1)
                const Divider(height: 1, color: MutandeColors.stone200),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fixed roster panel — loading wrap and loaded wrap share this height.
const kOnboardingRosterPanelHeight = 200.0;

/// Fixed host panel — roster chips for connected and available hosts.
const kOnboardingHostPanelHeight = 220.0;

/// Two helper lines (12px) plus [OnboardingSpace.sm] between them.
const kOnboardingConnectHelperHeight = 52.0;

/// Onboarding team roster chips — heading and actions stay on the step.
class OnboardingRosterSkeleton extends StatelessWidget {
  const OnboardingRosterSkeleton({super.key});

  static const _chipWidths = [220.0, 200.0, 176.0, 208.0];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading team',
      child: _Breath(
        child: SizedBox(
          height: kOnboardingRosterPanelHeight,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _chipWidths.length; i++)
                  MutandeArrive(
                    order: i,
                    child: _PersonChipBone(width: _chipWidths[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Onboarding host tiles — heading stays on the connect step.
class OnboardingHostSkeleton extends StatelessWidget {
  const OnboardingHostSkeleton({super.key, this.tiles = 5});

  final int tiles;
  static const _chipWidths = [220.0, 200.0, 176.0, 208.0, 188.0];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Detecting hosts',
      child: _Breath(
        child: SizedBox(
          height: kOnboardingHostPanelHeight,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < tiles; i++)
                MutandeArrive(
                  order: i,
                  child: _PersonChipBone(
                    width: _chipWidths[i % _chipWidths.length],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dossier list bones — section headings stay on the dossier.
class CollabDossierListsSkeleton extends StatelessWidget {
  const CollabDossierListsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading collab',
      child: _Breath(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            for (var i = 0; i < 2; i++)
              MutandeArrive(
                order: i,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bone(width: double.infinity, height: 9),
                      SizedBox(height: 6),
                      _Bone(width: 72, height: 8),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Board: three lane columns with a couple of card bones each.
class CollabBoardSkeleton extends StatelessWidget {
  const CollabBoardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading board',
      child: _Breath(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: MutandeArrive(
                    order: i,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Bone(width: 72, height: 10),
                        const SizedBox(height: 12),
                        for (var c = 0; c < (i == 1 ? 3 : 2); c++) ...[
                          _DashPlate(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Bone(width: 80.0 + c * 18, height: 10),
                                const SizedBox(height: 8),
                                const _Bone(width: double.infinity, height: 8),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip-shaped bones for create-collab people / agents lists only.
class CreateCollabChipSkeleton extends StatelessWidget {
  const CreateCollabChipSkeleton.people({super.key}) : people = true;
  const CreateCollabChipSkeleton.agents({super.key}) : people = false;

  final bool people;

  static const _people = [148.0, 128.0, 110.0];
  static const _agents = [88.0, 104.0, 72.0, 96.0];

  @override
  Widget build(BuildContext context) {
    final widths = people ? _people : _agents;
    final height = people ? 44.0 : 28.0;
    return Semantics(
      label: people ? 'Loading people' : 'Loading agents',
      child: _Breath(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: people ? 168 : 132),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widths.length; i++)
                MutandeArrive(
                  order: i,
                  child: people
                      ? _PersonChipBone(width: widths[i])
                      : _Bone(width: widths[i], height: height),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonChipBone extends StatelessWidget {
  const _PersonChipBone({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 56,
      child: const Row(
        children: [
          _Bone(width: 40, height: 40, circle: true),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bone(width: double.infinity, height: 12),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.72,
                  child: _Bone(width: double.infinity, height: 9),
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          _Bone(width: 24, height: 24, circle: true),
        ],
      ),
    );
  }
}

/// Opacity-only crossfade for skeleton → content. No translation.
class MutandeFadeSwap extends StatelessWidget {
  const MutandeFadeSwap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MutandeMotion.of(context, MutandeMotion.ui),
      switchInCurve: MutandeMotion.easeOut,
      switchOutCurve: MutandeMotion.easeOut,
      layoutBuilder: (current, previous) {
        return Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: child,
    );
  }
}
