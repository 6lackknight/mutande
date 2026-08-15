import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'onboarding_chrome.dart';

/// The address as it exists so far. Null segments are still to be filled.
@immutable
class OnboardingAddress {
  const OnboardingAddress({this.name, this.org, this.agent});

  /// Splits `alice@acme` (the daemon handle) into its two segments.
  factory OnboardingAddress.fromHandle(String? handle, {String? agent}) {
    final h = handle?.trim().toLowerCase() ?? '';
    if (h.isEmpty) return OnboardingAddress(agent: _clean(agent));
    final at = h.indexOf('@');
    if (at <= 0) return OnboardingAddress(name: h, agent: _clean(agent));
    return OnboardingAddress(
      name: h.substring(0, at),
      org: h.substring(at + 1).isEmpty ? null : h.substring(at + 1),
      agent: _clean(agent),
    );
  }

  final String? name;
  final String? org;
  final String? agent;

  static String? _clean(String? value) {
    final v = value?.trim().toLowerCase();
    if (v == null || v.isEmpty || v == 'default') return null;
    return v;
  }

  /// Index of the segment being filled next; 3 once the address is whole.
  int get activeSegment {
    if (name == null) return 0;
    if (org == null) return 1;
    if (agent == null) return 2;
    return 3;
  }

  bool get isComplete => activeSegment == 3;

  @override
  bool operator ==(Object other) =>
      other is OnboardingAddress &&
      other.name == name &&
      other.org == org &&
      other.agent == agent;

  @override
  int get hashCode => Object.hash(name, org, agent);

  @override
  String toString() =>
      '${name ?? '?'}@${org ?? '?'}${agent == null ? '' : '/$agent'}';
}

/// Menlo advance as a fraction of the em, net of the display tracking — lets
/// slots and values share exact widths without measuring.
const _trackingEm = -0.02;
const _advanceEm = 0.602 + _trackingEm;

/// Where the waiting rule and the landing underline both sit, measured up from
/// the bottom of the line box, so they read as one line.
const _ruleBottomEm = 0.09;

/// Onboarding progress, told as the address assembling itself.
///
/// Replaces the five-dot wizard rail: waiting segments are empty rules, the one
/// being filled breathes, each value lands with an amber underline, and the
/// first delivery sweeps the whole address.
class OnboardingAddressRail extends StatefulWidget {
  const OnboardingAddressRail({
    super.key,
    required this.address,
    required this.step,
    this.delivered = false,
    this.fontSize = 64,
  });

  final OnboardingAddress address;
  final OnboardingStep step;

  /// Set once the first mail lands — plays the delivery sweep.
  final bool delivered;

  final double fontSize;

  /// Slot widths, so an empty address still reads as an address.
  static const _placeholder = [5, 4, 6];

  @override
  State<OnboardingAddressRail> createState() => _OnboardingAddressRailState();
}

class _OnboardingAddressRailState extends State<OnboardingAddressRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  /// True only under `flutter test` — an endless breath never settles.
  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  bool get _reduced =>
      _inWidgetTest || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: hold the slot still instead of pulsing.
    if (_reduced) {
      _breath.stop();
      _breath.value = 0.5;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.address;
    final size = widget.fontSize;
    final active = address.activeSegment;

    return Semantics(
      label: 'Your address so far: $address',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _DeliveryLift(
                active: widget.delivered,
                reduced: _reduced,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _part(address.name, 0, active),
                    _punctuation('@', active > 1, size),
                    _part(address.org, 1, active),
                    _punctuation('/', active > 2, size),
                    _part(address.agent, 2, active),
                  ],
                ),
              ),
            ),
          ),
          _DeliverySweep(
            active: widget.delivered,
            fontSize: size,
            reduced: _reduced,
          ),
          const SizedBox(height: 12),
          _StepCaption(step: widget.step, delivered: widget.delivered),
        ],
      ),
    );
  }

  Widget _part(String? value, int index, int active) {
    if (value != null && value.isNotEmpty) {
      return _FilledSegment(
        key: ValueKey('segment-$index-$value'),
        value: value,
        fontSize: widget.fontSize,
        reduced: _reduced,
      );
    }
    return _EmptySlot(
      length: OnboardingAddressRail._placeholder[index],
      fontSize: widget.fontSize,
      breath: index == active ? _breath : null,
    );
  }

  Widget _punctuation(String glyph, bool bothSidesFilled, double size) {
    return Text(
      glyph,
      style: _addressStyle(size).copyWith(
        color:
            bothSidesFilled ? MutandeColors.stone400 : MutandeColors.stone200,
      ),
    );
  }
}

TextStyle _addressStyle(double size) => TextStyle(
      fontFamily: 'Menlo',
      fontSize: size,
      height: 1.1,
      letterSpacing: size * _trackingEm,
      color: MutandeColors.stone800,
    );

/// A value that has landed. Rises into place under an amber underline that
/// sweeps across it and then decays — the one beat repeated on every step.
class _FilledSegment extends StatelessWidget {
  const _FilledSegment({
    super.key,
    required this.value,
    required this.fontSize,
    required this.reduced,
  });

  final String value;
  final double fontSize;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final width = value.length * fontSize * _advanceEm;
    final height = fontSize * 1.1;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: Duration(milliseconds: reduced ? 0 : 420),
      curve: Curves.easeOutQuart,
      builder: (context, t, child) {
        // Underline sweeps over the first half, then fades out.
        final sweep = (t / 0.55).clamp(0.0, 1.0);
        final decay = t <= 0.55 ? 1.0 : 1 - ((t - 0.55) / 0.45);
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * fontSize * 0.09),
                    child: child,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: fontSize * _ruleBottomEm,
                child: Opacity(
                  opacity: decay.clamp(0.0, 1.0),
                  child: Container(
                    width: width * sweep,
                    height: fontSize * 0.05,
                    color: MutandeColors.amber,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: Text(value, style: _addressStyle(fontSize)),
    );
  }
}

/// A segment still to be earned — a rule at the baseline, not a run of
/// underscores (those pile into a redaction bar).
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    required this.length,
    required this.fontSize,
    required this.breath,
  });

  final int length;
  final double fontSize;

  /// Non-null when this is the slot being filled next.
  final Animation<double>? breath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: length * fontSize * _advanceEm,
      height: fontSize * 1.1,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: AnimatedBuilder(
          animation: breath ?? const AlwaysStoppedAnimation(0),
          builder: (context, _) => Container(
            height: fontSize * 0.035,
            // Inset so the rule reads as a waiting slot, not an underline
            // welded to the neighbouring glyphs.
            margin: EdgeInsets.only(
              right: fontSize * 0.1,
              bottom: fontSize * _ruleBottomEm,
            ),
            color: breath == null
                ? MutandeColors.stone200
                : Color.lerp(
                    MutandeColors.stone200,
                    MutandeColors.stone400,
                    breath!.value,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Delivery: the address takes a breath in before it settles.
class _DeliveryLift extends StatelessWidget {
  const _DeliveryLift({
    required this.active,
    required this.reduced,
    required this.child,
  });

  final bool active;
  final bool reduced;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active || reduced) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutQuart,
      builder: (context, t, child) {
        // Rises to 1.03 by a third of the way, then settles back.
        final lift = t < 0.34 ? t / 0.34 : 1 - ((t - 0.34) / 0.66);
        return Transform.scale(
          scale: 1 + 0.03 * lift.clamp(0.0, 1.0),
          alignment: Alignment.centerLeft,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Amber underline that sweeps the whole address when the first mail lands.
class _DeliverySweep extends StatelessWidget {
  const _DeliverySweep({
    required this.active,
    required this.fontSize,
    required this.reduced,
  });

  final bool active;
  final double fontSize;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: fontSize * 0.16,
      child: !active
          ? null
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: reduced ? 1 : 0, end: 1),
              duration: Duration(milliseconds: reduced ? 0 : 620),
              curve: Curves.easeOutQuart,
              builder: (context, t, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: t,
                  child: Container(
                    height: fontSize * 0.055,
                    margin: EdgeInsets.only(top: fontSize * 0.04),
                    color: MutandeColors.amber,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Explicit counting survives losing the dot rail — it just isn't the furniture.
class _StepCaption extends StatelessWidget {
  const _StepCaption({required this.step, required this.delivered});

  final OnboardingStep step;
  final bool delivered;

  @override
  Widget build(BuildContext context) {
    final text = delivered
        ? 'Done'
        : 'Step ${step.position} of ${OnboardingStep.values.length} — '
            '${step.label}';
    return Text(
      text,
      style: const TextStyle(
        color: MutandeColors.stone400,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
    );
  }
}
