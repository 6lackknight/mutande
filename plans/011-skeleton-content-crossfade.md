# 011 — Skeleton to content 200ms opacity crossfade

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: LOW (missed opportunity)
- **Category**: Missed opportunities
- **Estimated scope**: 2 files, load switches only

## Problem

Staggered skeletons unmount and real content pops in with no crossfade.

```dart
/* app/lib/screens/threads_screen.dart:577-580 — current */
  Widget _buildListPane(BuildContext context) {
    if (_loading) {
      return const ThreadListSkeleton();
    }
```

```dart
/* app/lib/screens/threads_screen.dart:1877-1878 — current */
        if (_loading)
          const Expanded(child: ThreadReadingSkeleton())
```

```dart
/* app/lib/screens/collab_screen.dart:126-128 — current */
    if (_loading) {
      return const CollabHomeSkeleton();
    }
```

```dart
/* app/lib/screens/collab_screen.dart:347-349 — current */
    if (_loading && _collab == null) {
      return const CollabBoardSkeleton();
    }
```

## Target

Crossfade **opacity only**, **200ms**, `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)`. Optional `ImageFilter.blur(sigmaX: 2, sigmaY: 2)` during the mix (keep blur **2px**, under 20px). Reduced motion: `Duration.zero` (snap). Do not translate.

Helper (put in `app/lib/widgets/thread_skeletons.dart` so both screens share it):

```dart
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
```

`MutandeMotion.ui` = `Duration(milliseconds: 200)`. `of` zeros under `disableAnimations`.

Usage: wrap the **result** of the load branch so the switcher sees a changing `Key`:

```dart
Widget _buildListPane(BuildContext context) {
  final Widget child;
  if (_loading) {
    child = const ThreadListSkeleton(key: ValueKey('sk'));
  } else if (_error != null) {
    child = PaneQuietState(…); // existing
  } else if (_visible.isEmpty) {
    child = …; // existing empty
  } else {
    child = … existing list, key: const ValueKey('list');
  }
  return MutandeFadeSwap(child: child);
}
```

Do **not** wrap the entire Threads split or tab body. Do not animate filter changes of an already-loaded list (high frequency).

Reading pane: wrap the `if (_loading) / else if (_detail == null) / else` **Expanded** child in one `AnimatedSwitcher`/`MutandeFadeSwap` so skeleton → reading fades. Keep `Expanded`.

Collab home and board: same pattern around the loading vs content return.

Blur is optional. If used:

```dart
FadeTransition(
  opacity: animation,
  child: ImageFiltered(
    imageFilter: ImageFilter.blur(
      sigmaX: 2 * (1 - animation.value),
      sigmaY: 2 * (1 - animation.value),
    ),
    child: child,
  ),
)
```

Requires `dart:ui` `ImageFilter`. Skip blur if it fights `CustomPaint` skeletons — opacity-only is enough.

`thread_skeletons.dart` already imports `mutande_macos_theme.dart`.

## Repo conventions to follow

- Stacked switcher `layoutBuilder`: `app/lib/widgets/morphing_orb_button.dart:64-68`.
- Skeleton stagger/breath is by design — do not change `_Arrive` / `_Breath`.
- `collab_screen.dart` and `threads_screen.dart` already import `thread_skeletons.dart`.

## Steps

1. Add `MutandeFadeSwap` to `app/lib/widgets/thread_skeletons.dart` (bottom of file). Export is automatic (same library).
2. `threads_screen.dart` `_buildListPane`: assign the existing branches to a keyed `child`, return `MutandeFadeSwap(child: child)`. Do not change list row widgets.
3. `threads_screen.dart` reading column: replace the `if (_loading) Expanded(ThreadReadingSkeleton)` / quiet / `ThreadRelayReading` chain with one `Expanded(child: MutandeFadeSwap(child: keyedChild))`.
4. `collab_screen.dart` home: wrap loading vs dashboard in `MutandeFadeSwap`.
5. `collab_screen.dart` board: wrap `CollabBoardSkeleton` vs board column the same way.

## Boundaries

- Do NOT fade Threads · Collab · Network tab switches.
- Do NOT fade thread selection (list tap → other thread).
- Do NOT change skeleton bones, breath, or `_Arrive` stagger.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/thread_skeletons.dart lib/screens/threads_screen.dart lib/screens/collab_screen.dart && flutter test test/collab_home_dashboard_test.dart test/widget_test.dart`
- **Feel check**: quit and reopen so Threads list loads from network (or toggle airplane then back). Skeleton **fades** into rows ~200ms; no horizontal slide. Collab home: same. Reduce motion: snap. Flutter DevTools 5×: two opacities cross; blur if present stays ~2px.
- **Done when**: the four load seams use 200ms opacity `AnimatedSwitcher`/`MutandeFadeSwap`; tab and thread-select swaps stay instant.
