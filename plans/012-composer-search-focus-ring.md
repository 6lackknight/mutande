# 012 — Match composer and search focus-ring timing

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: LOW (missed opportunity)
- **Category**: Cohesion
- **Estimated scope**: 2 files

## Problem

Search field border eases 140ms (default **linear**). Capsule composer border **snaps**. Same focus-ring language must share timing.

```dart
/* app/lib/widgets/search_dialog.dart:459-469 — current */
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: MutandeColors.stone50,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: focused ? MutandeColors.stone800 : MutandeColors.stone200,
              width: focused ? 1.5 : 1,
            ),
          ),
```

```dart
/* app/lib/widgets/thread_relay_reading.dart:703-714 — current */
        Focus(
          onFocusChange: (v) => setState(() => _focused = v),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MutandeColors.stone100,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _focused
                    ? MutandeColors.stone800
                    : MutandeColors.stone200,
                width: _focused ? 1.5 : 1,
              ),
            ),
```

Hover/color budget is **100–160ms** with CSS `ease` = `cubic-bezier(0.25, 0.1, 0.25, 1)`.

## Target

Both rings:

```dart
duration: MutandeMotion.of(context, MutandeMotion.hover),
curve: MutandeMotion.ease,
```

- `MutandeMotion.hover` = `Duration(milliseconds: 140)`
- `MutandeMotion.ease` = `Cubic(0.25, 0.1, 0.25, 1.0)`
- `of` → `Duration.zero` when `disableAnimations` (color may still snap — that is the reduced path)

Search: add `curve` and gate duration on the existing `AnimatedContainer`. Do not change height 44 or stadium radius.

Composer: replace `DecoratedBox` with `AnimatedContainer` (or `AnimatedContainer` wrapping the same padding/child) using the same duration/curve and the same border colors/widths. Keep `stone100` fill, radius 18, inner `TextField`.

```dart
Focus(
  onFocusChange: (v) => setState(() => _focused = v),
  child: AnimatedContainer(
    duration: MutandeMotion.of(context, MutandeMotion.hover),
    curve: MutandeMotion.ease,
    decoration: BoxDecoration(
      color: MutandeColors.stone100,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: _focused ? MutandeColors.stone800 : MutandeColors.stone200,
        width: _focused ? 1.5 : 1,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row( /* existing */ ),
    ),
  ),
)
```

Do not animate composer height as the user types (maxLines 1–6). Only decoration (border color/width). `AnimatedContainer` will also lerp border width 1 → 1.5 — that is acceptable for a color/border ring.

Both files already import `mutande_macos_theme.dart`.

## Repo conventions to follow

- Plan 002 uses the same hover ease on pills — stay consistent.
- Do not change search **open** (plan 001 removes that animation).
- Do not change `_ScopeChip` here (002).

## Steps

1. `app/lib/widgets/search_dialog.dart` `_DialogSearchField`: set `duration: MutandeMotion.of(context, MutandeMotion.hover)`, `curve: MutandeMotion.ease` on the `AnimatedContainer`.
2. `app/lib/widgets/thread_relay_reading.dart` `_CapsuleComposerState`: swap `DecoratedBox` for `AnimatedContainer` with the same duration/curve; keep children/padding.
3. Do not wrap the `TextField` in another animation.

## Boundaries

- Do NOT restore search dialog open fade/slide.
- Do NOT change send-button `InkWell`.
- Do NOT change onboarding inputs.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/search_dialog.dart lib/widgets/thread_relay_reading.dart && flutter test test/search_dialog_test.dart`
- **Feel check**: focus the search field (open search with `/` — palette itself is instant after 001). Border eases ~140ms, not linear. Focus the Threads composer: **same** 140ms ease, not a snap. Blur both: same timing out. Reduce motion: both rings snap. Flutter DevTools 5×: both are ease, not linear, and match each other.
- **Done when**: both focus rings use 140ms `Cubic(0.25, 0.1, 0.25, 1.0)` gated by `MutandeMotion.of`.
