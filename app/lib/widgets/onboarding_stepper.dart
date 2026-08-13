import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Onboarding steps shown in the top progress rail.
enum OnboardingStep {
  signIn,
  team,
  connect,
  notifications,
  ping,
}

extension OnboardingStepLabels on OnboardingStep {
  String get label {
    switch (this) {
      case OnboardingStep.signIn:
        return 'Sign in';
      case OnboardingStep.team:
        return 'Your team';
      case OnboardingStep.connect:
        return 'Connect';
      case OnboardingStep.notifications:
        return 'Notify';
      case OnboardingStep.ping:
        return 'Ping';
    }
  }
}

/// Shared onboarding spacing scale (8px base).
abstract final class OnboardingSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Persistent 5-step rail for onboarding screens.
class OnboardingStepper extends StatelessWidget {
  const OnboardingStepper({
    super.key,
    required this.current,
    this.completedBefore,
  });

  final OnboardingStep current;
  final Set<OnboardingStep>? completedBefore;

  bool _done(OnboardingStep step) {
    if (completedBefore?.contains(step) ?? false) return true;
    return step.index < current.index;
  }

  @override
  Widget build(BuildContext context) {
    const steps = OnboardingStep.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OnboardingSpace.lg,
        OnboardingSpace.sm,
        OnboardingSpace.lg,
        OnboardingSpace.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: 1,
                    color: _done(steps[i])
                        ? MutandeColors.amber.withValues(alpha: 0.4)
                        : MutandeColors.stone200,
                  ),
                ),
              ),
            _StepDot(
              label: steps[i].label,
              active: steps[i] == current,
              done: _done(steps[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          letterSpacing: -0.1,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          color: active
              ? MutandeColors.stone800
              : done
                  ? MutandeColors.stone600
                  : MutandeColors.stone400,
        );
    return Semantics(
      label: '$label${done ? ', completed' : active ? ', current step' : ''}',
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? MutandeColors.amberSoft
                    : active
                        ? MutandeColors.amberSoft.withValues(alpha: 0.65)
                        : MutandeColors.stone100,
                border: Border.all(
                  color: done || active
                      ? MutandeColors.amber
                      : MutandeColors.stone200,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: done
                  ? Icon(Icons.check, size: 13, color: MutandeColors.amber)
                  : active
                      ? Center(
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: MutandeColors.amber,
                            ),
                          ),
                        )
                      : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared onboarding chrome: title bar area + stepper + scroll body.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.step,
    required this.child,
    this.completedBefore,
    this.debugBanner,
    this.contentMaxWidth = 560,
    this.centerContent = false,
  });

  final OnboardingStep step;
  final Widget child;
  final Set<OnboardingStep>? completedBefore;
  final String? debugBanner;
  final double contentMaxWidth;
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MutandeColors.stone50,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (debugBanner != null)
              Container(
                width: double.infinity,
                color: MutandeColors.stone800,
                padding: const EdgeInsets.symmetric(
                  horizontal: OnboardingSpace.sm,
                  vertical: 6,
                ),
                child: Text(
                  debugBanner!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MutandeColors.stone100,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OnboardingSpace.lg,
                OnboardingSpace.md,
                OnboardingSpace.lg,
                0,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/mt_mark_white_on_black.png',
                      width: 28,
                      height: 28,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'mutande',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: MutandeColors.stone800,
                        ),
                  ),
                ],
              ),
            ),
            OnboardingStepper(
              current: step,
              completedBefore: completedBefore,
            ),
            const Divider(height: 1, color: MutandeColors.stone200),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  OnboardingSpace.xl,
                  OnboardingSpace.lg,
                  OnboardingSpace.xl,
                  OnboardingSpace.xl,
                ),
                child: Align(
                  alignment:
                      centerContent ? Alignment.topCenter : Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step title typography — standard body steps vs landing-style display.
enum OnboardingHeadingVariant { standard, display }

/// Step title + optional subtitle — shared across onboarding bodies.
class OnboardingHeading extends StatelessWidget {
  const OnboardingHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.detail,
    this.kicker,
    this.variant = OnboardingHeadingVariant.standard,
    this.textAlign = TextAlign.start,
  });

  final String title;
  final String? subtitle;
  final String? detail;
  final String? kicker;
  final OnboardingHeadingVariant variant;
  final TextAlign textAlign;

  static TextStyle displayTitleStyle(ThemeData theme) {
    return theme.textTheme.headlineMedium!.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      height: 1.12,
      letterSpacing: -0.6,
      color: MutandeColors.stone800,
    );
  }

  static TextStyle standardTitleStyle(ThemeData theme) {
    return theme.textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.35,
      height: 1.15,
      color: MutandeColors.stone800,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final titleStyle = variant == OnboardingHeadingVariant.display
        ? displayTitleStyle(Theme.of(context))
        : standardTitleStyle(Theme.of(context));

    return Column(
      crossAxisAlignment: crossAxisAlignmentFor(textAlign),
      children: [
        if (kicker != null) ...[
          Text(
            kicker!,
            textAlign: textAlign,
            style: theme.labelSmall?.copyWith(
              color: MutandeColors.stone500,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          textAlign: textAlign,
          style: titleStyle,
        ),
        if (subtitle != null) ...[
          SizedBox(
            height: variant == OnboardingHeadingVariant.display
                ? OnboardingSpace.sm
                : OnboardingSpace.xs,
          ),
          Text(
            subtitle!,
            textAlign: textAlign,
            style: theme.bodyLarge?.copyWith(
              color: MutandeColors.stone600,
              height: 1.45,
              fontSize: variant == OnboardingHeadingVariant.display ? 17 : null,
            ),
          ),
        ],
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(
            detail!,
            textAlign: textAlign,
            style: theme.bodySmall?.copyWith(
              color: MutandeColors.stone500,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  static CrossAxisAlignment crossAxisAlignmentFor(TextAlign align) {
    return switch (align) {
      TextAlign.center => CrossAxisAlignment.center,
      TextAlign.end || TextAlign.right => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.stretch,
    };
  }
}

/// Inline error for onboarding forms.
class OnboardingErrorBanner extends StatelessWidget {
  const OnboardingErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: OnboardingSpace.sm,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF991B1B),
              height: 1.35,
            ),
      ),
    );
  }
}

/// Primary + secondary actions with consistent vertical rhythm.
class OnboardingActions extends StatelessWidget {
  const OnboardingActions({
    super.key,
    this.primary,
    this.secondary,
    this.tertiary,
    this.topSpacing = OnboardingSpace.lg,
  });

  final Widget? primary;
  final Widget? secondary;
  final Widget? tertiary;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: topSpacing),
        if (primary != null) primary!,
        if (secondary != null) ...[
          const SizedBox(height: OnboardingSpace.xs),
          secondary!,
        ],
        if (tertiary != null) ...[
          const SizedBox(height: 4),
          tertiary!,
        ],
      ],
    );
  }
}
