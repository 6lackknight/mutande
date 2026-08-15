# 003 — Gate everyday motion with disableAnimations

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: HIGH
- **Category**: Accessibility
- **Estimated scope**: 4 files (pills in 002 already gated)

## Problem

Everyday color/size motion ignores `MediaQuery.disableAnimationsOf`. People-row, search-open, and agents graph already gate. These do not:

```dart
/* app/lib/screens/threads_screen.dart:884-888 — current */
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            color: selected ? MutandeColors.stone100 : Colors.transparent,
```

```dart
/* app/lib/screens/collab_screen.dart:497-499 — current */
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 260,
```

```dart
/* app/lib/widgets/create_collab_sheet.dart:843-845 — current */
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
```

```dart
/* app/lib/widgets/create_collab_sheet.dart:943-945 — current */
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
```

```dart
/* app/lib/widgets/daemon_error_screen.dart:239-243 — current */
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState: _detailsOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
```

Reduced motion keeps opacity/color snaps and drops movement. Gating duration to `Duration.zero` is the repo pattern.

## Target

Use `MutandeMotion.of(context, …)` (plan 008). Fallback: `MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration`.

| Site | Moving duration when motion allowed |
| --- | --- |
| `_ThreadRow` | `MutandeMotion.hover` (140ms). Keep `Curves.easeOutCubic` **or** `MutandeMotion.easeOut` `Cubic(0.23, 1.0, 0.32, 1.0)` — do not switch to linear. |
| Collab lane hot | 120ms (drag affordance, still ≤160ms hover budget) via `MutandeMotion.of(context, const Duration(milliseconds: 120))`. Add `curve: MutandeMotion.ease` (`Cubic(0.25, 0.1, 0.25, 1.0)`). |
| Create-collab chips | `MutandeMotion.hover` + existing ease-out **or** `MutandeMotion.easeOut`. |
| Daemon details | `MutandeMotion.of(context, const Duration(milliseconds: 180))` on `AnimatedCrossFade`. |

Do **not** re-edit pills/thumbs from plan 002.

## Repo conventions to follow

- Exemplar: `app/lib/widgets/person_identity_row.dart:79-81`.
- Agents helper: `app/lib/screens/agents_screen.dart:67-68` `_agentsMotion`.
- Prefer `MutandeMotion.of` once 008 landed.
- `create_collab_sheet.dart` and `daemon_error_screen.dart` already import `mutande_macos_theme.dart`.

## Steps

1. `app/lib/screens/threads_screen.dart` `_ThreadRow.build`: `duration: MutandeMotion.of(context, MutandeMotion.hover)`. Leave padding, selected color, and `InkWell` to plan 005.
2. `app/lib/screens/collab_screen.dart` lane `AnimatedContainer`: `duration: MutandeMotion.of(context, const Duration(milliseconds: 120))`, `curve: MutandeMotion.ease`. Keep width 260 and bronzeSoft/stone100 fills.
3. `app/lib/widgets/create_collab_sheet.dart` both chip `AnimatedContainer`s (~843 and ~943): `duration: MutandeMotion.of(context, MutandeMotion.hover)`. Keep curves (or set `MutandeMotion.easeOut`).
4. `app/lib/widgets/daemon_error_screen.dart` `AnimatedCrossFade`: `duration: MutandeMotion.of(context, const Duration(milliseconds: 180))`.
5. Accordion `AnimatedSize` is plan 007 — skip `thread_relay_reading.dart` here.

## Boundaries

- Do NOT change `home_chrome_strip.dart`, `_ScopePill`, `_SegmentPill`, `_ScopeChip` (002).
- Do NOT change `thinking_orb.dart`, morph button, onboarding rail, people-row.
- Do NOT change InkWell splash (005).
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/screens/threads_screen.dart lib/screens/collab_screen.dart lib/widgets/create_collab_sheet.dart lib/widgets/daemon_error_screen.dart` then `flutter test test/create_collab_sheet_test.dart test/widget_test.dart`
- **Feel check**: Enable macOS Reduce motion. Thread row selection, collab lane highlight, create-collab chips, daemon Details expand all **snap**. Disable Reduce motion: they still ease over ~120–180ms. Color/fill still changes (feedback remains).
- **Done when**: every listed duration goes through `MutandeMotion.of` or an equivalent `disableAnimationsOf` ternary; pills from 002 are untouched.
