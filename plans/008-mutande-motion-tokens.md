# 008 — Add MutandeMotion tokens

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: LOW
- **Category**: Cohesion & tokens
- **Estimated scope**: 1 file, ~40 lines added

## Problem

Color tokens live in `app/lib/theme/mutande_macos_theme.dart` but durations and curves are hand-copied across chrome, sheets, and lists. Five near-identical 140ms / `easeOutCubic` sites will drift. This plan only **adds** the token class. Other plans migrate call sites.

Current theme exports colors only:

```dart
/* app/lib/theme/mutande_macos_theme.dart:4-19 — current */
/// Stone surface tokens shared by Material content + macos_ui shell.
abstract final class MutandeColors {
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone800 = Color(0xFF292524);
  static const bronze = Color(0xFF92400E);
  static const bronzeSoft = Color(0xFFF5EDE6);
  static const amber = Color(0xFFB45309);
  static const amberSoft = Color(0xFFFEF3C7);
  static const emerald = Color(0xFF166534);
  static const emeraldSoft = Color(0xFFECFDF5);
}
```

## Target

Insert `MutandeMotion` immediately after `MutandeColors` (before `mutandeMaterialTheme`). Values copied from the animation audit playbook — do not invent parallels:

```dart
/* target — app/lib/theme/mutande_macos_theme.dart after MutandeColors */
/// Shared motion tokens. Cubic values match CSS:
/// `ease` = cubic-bezier(0.25, 0.1, 0.25, 1)
/// `--ease-out` = cubic-bezier(0.23, 1, 0.32, 1)
/// `--ease-in-out` = cubic-bezier(0.77, 0, 0.175, 1)
/// `--ease-drawer` = cubic-bezier(0.32, 0.72, 0, 1)
abstract final class MutandeMotion {
  /// Hover / color change.
  static const Cubic ease = Cubic(0.25, 0.1, 0.25, 1.0);

  /// Strong ease-out for UI enter and response.
  static const Cubic easeOut = Cubic(0.23, 1.0, 0.32, 1.0);

  /// Moving / morphing on screen.
  static const Cubic easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);

  /// Panel / drawer from an edge.
  static const Cubic easeDrawer = Cubic(0.32, 0.72, 0.0, 1.0);

  /// Hover / selection color. Budget 100–160ms.
  static const Duration hover = Duration(milliseconds: 140);

  /// Button press feedback. Budget 100–160ms.
  static const Duration press = Duration(milliseconds: 160);

  /// Small UI / modal enter. Budget 200ms (UI stays under 300ms; modals 200–500ms).
  static const Duration ui = Duration(milliseconds: 200);

  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
```

`Cubic` and `MediaQuery` come from `package:flutter/material.dart` (already imported).

## Repo conventions to follow

- Tokens sit next to `MutandeColors` in `app/lib/theme/mutande_macos_theme.dart`.
- Reduced-motion helper matches `app/lib/widgets/person_identity_row.dart:79-81`:

```dart
final reduce = MediaQuery.disableAnimationsOf(context);
final duration =
    reduce ? Duration.zero : const Duration(milliseconds: 140);
```

- Existing people-row hover is **140ms** `Curves.easeOutCubic` by design. `MutandeMotion.hover` is 140ms so later migrations can match without restyling that row in this plan.

## Steps

1. In `app/lib/theme/mutande_macos_theme.dart`, after the closing `}` of `MutandeColors` (line 19) and before `mutandeMaterialTheme`, paste the `MutandeMotion` class from Target verbatim.
2. Do not change `mutandeMaterialTheme`, `mutandeMacosTheme`, or `mutandeThemeBridge`.
3. Do not migrate any call sites in this plan.

## Boundaries

- Do NOT edit `app/lib/widgets/thinking_orb.dart`.
- Do NOT edit `app/lib/widgets/morphing_orb_button.dart`.
- Do NOT edit `app/lib/widgets/onboarding_address_rail.dart` or `app/lib/widgets/onboarding_chrome.dart`.
- Do NOT edit `app/lib/widgets/person_identity_row.dart` (hover already 140ms by design).
- Do NOT add pub dependencies.
- Do NOT change markup or colors.
- If `MutandeMotion` already exists with these values, STOP and report.

## Verification

- **Mechanical**: from `app/`, `dart analyze lib/theme/mutande_macos_theme.dart` — no errors. `flutter test` still passes (this file has no tests).
- **Feel check**: none in this plan (tokens unused until later plans). Confirm in the IDE that `MutandeMotion.ease`, `easeOut`, `easeInOut`, `easeDrawer`, `hover`, `press`, `ui`, and `of` resolve.
- **Done when**: `MutandeMotion` exists with the exact Cubics and Durations above; no other files changed.
