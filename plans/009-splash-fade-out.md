# 009 — Splash opacity fade out

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: LOW (missed opportunity)
- **Category**: Missed opportunities
- **Estimated scope**: 1 file, `welcome_splash.dart`

## Problem

The branded splash unmounts in one `setState`. Rare first-run/launch is allowed a short opacity fade. No movement.

```dart
/* app/lib/widgets/welcome_splash.dart:83-88 — current */
    void dismiss() {
      if (!mounted || !_showSplash) return;
      final g = widget.dismissWhen;
      if (g != null && !g.value) return;
      setState(() => _showSplash = false);
    }
```

```dart
/* app/lib/widgets/welcome_splash.dart:101-108 — current */
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF0C0A09),
```

## Target

Keep the overlay mounted until opacity reaches 0, then remove it.

- Duration: **200ms** (`MutandeMotion.ui` / `Duration(milliseconds: 200)`).
- Curve: `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)` (`cubic-bezier(0.23, 1, 0.32, 1)`).
- Animate **opacity only**. No translate, scale, or blur.
- Reduced motion: opacity transitions that aid comprehension **stay**. Still use 200ms fade (no position to drop). If `disableAnimations` is true, `Duration.zero` is acceptable so tests/CI don’t wait.

```dart
bool _showSplash = true;
bool _splashOpaque = true;

void dismiss() {
  if (!mounted || !_showSplash) return;
  final g = widget.dismissWhen;
  if (g != null && !g.value) return;
  final reduce = MediaQuery.disableAnimationsOf(context);
  if (reduce) {
    setState(() => _showSplash = false);
    return;
  }
  setState(() => _splashOpaque = false);
}

/* build overlay */
if (_showSplash)
  Positioned.fill(
    child: IgnorePointer(
      child: AnimatedOpacity(
        opacity: _splashOpaque ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: const Cubic(0.23, 1.0, 0.32, 1.0),
        onEnd: () {
          if (!_splashOpaque && mounted) {
            setState(() => _showSplash = false);
          }
        },
        child: ColoredBox(
          color: const Color(0xFF0C0A09),
          child: Stack( /* existing _MidGlow + wordmark + orb */ ),
        ),
      ),
    ),
  ),
```

Keep `widget.child` mounted underneath. Keep 3s `duration` hold and `dismissWhen` gate. Keep `MutandeOrb.standard` as the working orb (do not replace or restyle it).

`dismiss()` currently may run without a `BuildContext` that has `MediaQuery` if called from `initState` delay — use `if (mounted) MediaQuery.disableAnimationsOf(context)` only after the widget is mounted (it already checks `mounted`). `didChangeDependencies` is not required if you read `MediaQuery` inside `dismiss` after `mounted`.

Import `mutande_macos_theme.dart` only if you use `MutandeMotion`; otherwise inline the Cubic as above. `welcome_splash.dart` currently imports foundation, material, scheduler, thinking_orb.

## Repo conventions to follow

- Overlay-on-child so tray listeners keep running (comment at `:9-10`) — do not unmount `child`.
- Orb remains `MutandeOrb.standard` (`:123-126`).
- Do not introduce a second working-state animation.

## Steps

1. Add `_splashOpaque` (default `true`) beside `_showSplash`.
2. Change `dismiss()` to fade (`_splashOpaque = false`) instead of immediately clearing `_showSplash`, with `Duration.zero` / immediate unmount when `disableAnimationsOf` is true.
3. Wrap the existing overlay `ColoredBox` in `AnimatedOpacity` as Target. Call `onEnd` to set `_showSplash = false`.
4. Do not change `_tryDismiss` gating (`_minElapsed`, `dismissWhen`).

## Boundaries

- Do NOT change splash copy, 3s minimum, Keychain `dismissWhen`, or orb internals.
- Do NOT fade using `SlideTransition` or scale.
- Do NOT add dependencies.
- If `_showSplash` is used from tests expecting instant removal, keep the reduce-motion instant path.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/welcome_splash.dart && flutter test test/widget_test.dart`
- **Feel check**: cold launch the macOS app. After the hold, the dark splash **fades** ~200ms to home; the orb does not slide. Reduce motion: splash disappears instantly. Flutter DevTools 5×: opacity only.
- **Done when**: dismiss is a 200ms opacity fade (or instant under reduce); child stays mounted; no transform.
