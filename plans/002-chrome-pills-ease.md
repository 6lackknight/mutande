# 002 — Ease high-frequency pill and thumb color

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: HIGH
- **Category**: Easing & duration
- **Estimated scope**: 5 files, small edits

## Problem

Selected tab thumbs and filter pills use `AnimatedContainer` with Flutter’s default **`Curves.linear`**. Hover/color must use CSS `ease` = `cubic-bezier(0.25, 0.1, 0.25, 1)` and stay in **100–160ms**. Chrome icon hits wrap a no-op `AnimatedContainer` (color always transparent) while the icon color snaps.

```dart
/* app/lib/widgets/home_chrome_strip.dart:178-187 — current */
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: thumbHeight,
            constraints: const BoxConstraints(minWidth: 112),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? MutandeColors.stone50 : const Color(0x00000000),
              borderRadius: HomeChrome.thumbStadium,
            ),
```

```dart
/* app/lib/screens/threads_screen.dart:765-767 — current */
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
```

```dart
/* app/lib/screens/network_screen.dart:122-124 — current */
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
```

```dart
/* app/lib/widgets/search_dialog.dart:553-555 — current */
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
```

```dart
/* app/lib/widgets/home_chrome_pills.dart:126-138 — current */
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: HomeChrome.thumbHeight,
              alignment: Alignment.center,
              color: const Color(0x00000000),
              child: Icon(
                widget.icon,
                size: 16,
                color: _hover
                    ? MutandeColors.stone600
                    : HomeChrome.muteForeground,
              ),
            ),
```

## Target

Every selected-fill `AnimatedContainer` in this plan:

```dart
duration: MutandeMotion.of(context, MutandeMotion.hover),
curve: MutandeMotion.ease,
```

Exact values if `MutandeMotion` is missing: duration `Duration(milliseconds: 140)` unless `MediaQuery.disableAnimationsOf(context)` then `Duration.zero`; curve `const Cubic(0.25, 0.1, 0.25, 1.0)`.

`_ChromeIconHit`: delete `AnimatedContainer`. Use a `SizedBox(width: 36, height: HomeChrome.thumbHeight)` + centered `Icon`. Icon color stays instant (high-frequency chrome).

## Repo conventions to follow

- Tokens: `app/lib/theme/mutande_macos_theme.dart` `MutandeMotion` (plan 008). Run 008 first.
- Reduced-motion gate exemplar: `app/lib/widgets/person_identity_row.dart:79-81`.
- These files already import `mutande_macos_theme.dart` except confirm `home_chrome_strip.dart` (`import '../theme/mutande_macos_theme.dart';` exists).
- `threads_screen.dart` `_ThreadRow` already has `curve: Curves.easeOutCubic` — **do not change that row here** (plan 003 / 005).

## Steps

1. `app/lib/widgets/home_chrome_strip.dart` `_HeaderThumb`: add `curve: MutandeMotion.ease` and `duration: MutandeMotion.of(context, MutandeMotion.hover)` on the `AnimatedContainer`. Keep height, padding, fill colors.
2. `app/lib/screens/threads_screen.dart` `_ScopePill`: same duration/curve on its `AnimatedContainer`.
3. `app/lib/screens/network_screen.dart` `_SegmentPill`: same.
4. `app/lib/widgets/search_dialog.dart` `_ScopeChip` only (not `_DialogSearchField` — plan 012): same.
5. `app/lib/widgets/home_chrome_pills.dart` `_ChromeIconHit`: replace `AnimatedContainer` with:

```dart
child: SizedBox(
  width: 36,
  height: HomeChrome.thumbHeight,
  child: Icon(
    widget.icon,
    size: 16,
    color: _hover
        ? MutandeColors.stone600
        : HomeChrome.muteForeground,
  ),
),
```

Keep `MouseRegion` / `GestureDetector` / `Tooltip` / 36×thumb hit target.

## Boundaries

- Do NOT change `_ThreadRow` selected fill (003, 005).
- Do NOT change `_DialogSearchField` (012).
- Do NOT add press `scale(0.97)` in this plan.
- Do NOT restyle orb, morph button, onboarding rail, people-row.
- If a listed `AnimatedContainer` already has a `curve:`, STOP and report that site.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/home_chrome_strip.dart lib/widgets/home_chrome_pills.dart lib/screens/threads_screen.dart lib/screens/network_screen.dart lib/widgets/search_dialog.dart`
- **Feel check**: Threads home — click All / Needs you / Open. Fill should start moving immediately (ease, not linear lag) and finish by ~140ms. Titlebar Threads · Collab · Network thumbs: same. Settings → Accessibility → Reduce motion: fills snap. Chrome search/settings icons: hover recolors instantly, no 120ms empty container. Flutter DevTools slow 5×: pill fill eases, not a constant-speed lerp.
- **Done when**: all four selected-fill containers use `MutandeMotion.ease` + `MutandeMotion.hover` gated by `of`; `_ChromeIconHit` has no `AnimatedContainer`.
