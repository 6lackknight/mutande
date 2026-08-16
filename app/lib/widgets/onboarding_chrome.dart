import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_chrome_buttons.dart';
import 'onboarding_address_rail.dart';

/// Onboarding steps, one per segment of the address plus its first delivery.
///
/// Notifications used to be a step of its own; it now rides along with the
/// ping wait, where the arriving pong proves the permission works.
enum OnboardingStep { signIn, team, connect, ping }

extension OnboardingStepLabels on OnboardingStep {
  String get label {
    switch (this) {
      case OnboardingStep.signIn:
        return 'Sign in';
      case OnboardingStep.team:
        return 'Your team';
      case OnboardingStep.connect:
        return 'Connect a host';
      case OnboardingStep.ping:
        return 'First ping';
    }
  }

  /// 1-based, for `Step 2 of 4`.
  int get position => index + 1;
}

/// Shared onboarding spacing scale (8px base).
abstract final class OnboardingSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Compact Mac titlebar height. Extra top inset when letterhead sits under
  /// overlay traffic lights (transparent titlebar, full-size content view).
  static const titlebar = 28.0;
}

/// Shared onboarding chrome: the address marquee over a narrow content column.
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.step,
    required this.child,
    this.address = const OnboardingAddress(),
    this.delivered = false,
    this.debugBanner,
    this.contentMaxWidth = 420,
    this.centerContent = false,
  });

  final OnboardingStep step;
  final Widget child;

  /// Drives the marquee — segments fill in as the flow earns them.
  final OnboardingAddress address;

  /// First mail landed; plays the delivery sweep under the address.
  final bool delivered;

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
                OnboardingSpace.xl,
                OnboardingSpace.xl,
                OnboardingSpace.xl,
                OnboardingSpace.lg,
              ),
              child: OnboardingAddressRail(
                address: address,
                step: step,
                delivered: delivered,
              ),
            ),
            // Letterhead rule — full bleed, so the address reads as stationery
            // and the empty right side has a job.
            const Divider(
              height: 1,
              thickness: 1,
              color: MutandeColors.stone200,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  OnboardingSpace.xl,
                  OnboardingSpace.xl,
                  OnboardingSpace.xl,
                  OnboardingSpace.xl,
                ),
                child: Align(
                  alignment: centerContent
                      ? Alignment.topCenter
                      : Alignment.topLeft,
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
    // Deliberately under the address marquee — the address is the hero.
    return theme.textTheme.headlineMedium!.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w600,
      height: 1.12,
      letterSpacing: -0.8,
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

    final lines = <Widget>[
      if (kicker != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            kicker!,
            textAlign: textAlign,
            style: theme.labelSmall?.copyWith(
              color: MutandeColors.stone500,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
      Text(title, textAlign: textAlign, style: titleStyle),
      if (subtitle != null)
        Padding(
          padding: EdgeInsets.only(
            top: variant == OnboardingHeadingVariant.display
                ? OnboardingSpace.sm
                : OnboardingSpace.xs,
          ),
          child: Text(
            subtitle!,
            textAlign: textAlign,
            style: theme.bodyLarge?.copyWith(
              color: MutandeColors.stone600,
              height: 1.45,
              fontSize: variant == OnboardingHeadingVariant.display ? 15 : null,
            ),
          ),
        ),
      if (detail != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            detail!,
            textAlign: textAlign,
            style: theme.bodySmall?.copyWith(
              color: MutandeColors.stone500,
              height: 1.4,
            ),
          ),
        ),
    ];

    final staggered =
        variant == OnboardingHeadingVariant.display &&
        !MediaQuery.disableAnimationsOf(context);

    return Column(
      // Keyed on the title so each step's words arrive fresh instead of
      // swapping in place.
      key: staggered ? ValueKey(title) : null,
      crossAxisAlignment: crossAxisAlignmentFor(textAlign),
      children: [
        for (var i = 0; i < lines.length; i++)
          if (staggered) _Arrive(order: i, child: lines[i]) else lines[i],
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

/// A line of the heading arriving: rises a few pixels into place, later lines
/// trailing the ones above them.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + order * 90),
      curve: Interval(
        (order * 0.16).clamp(0.0, 0.6),
        1,
        curve: Curves.easeOutQuart,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 7),
          child: child,
        ),
      ),
      child: child,
    );
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

/// One committed primary, with anything else as inline links beneath it.
///
/// Deliberately not three stacked full-width buttons — that stack made every
/// step look like the same form.
class OnboardingActions extends StatelessWidget {
  const OnboardingActions({
    super.key,
    this.primary,
    this.secondary,
    this.tertiary,
    this.topSpacing = OnboardingSpace.lg,
    this.hugPrimary = false,
  });

  final Widget? primary;
  final Widget? secondary;
  final Widget? tertiary;
  final double topSpacing;

  /// When true, the primary button sizes to its label instead of [primaryWidth].
  final bool hugPrimary;

  /// Wide enough to command the column, short of the full measure.
  static const primaryWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final links = <Widget>[?secondary, ?tertiary];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topSpacing),
        if (primary != null)
          hugPrimary
              ? HomeChromeButtons.theme(child: primary!)
              : SizedBox(
                  width: primaryWidth,
                  child: HomeChromeButtons.theme(child: primary!),
                ),
        if (links.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: primary == null ? 0 : 6),
            child: TextButtonTheme(
              data: TextButtonThemeData(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              child: Wrap(
                spacing: OnboardingSpace.lg,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: links,
              ),
            ),
          ),
      ],
    );
  }
}
