# 001 — Remove search palette open animation

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 1 file, ~20 lines

## Problem

Search is a keyboard command palette (`/` , `⌘F`, `⌘K` in `app/lib/app.dart:876-884`). It currently fades and slides 200ms. Keyboard palettes must not animate.

```dart
/* app/lib/widgets/search_dialog.dart:138-171 — current */
  final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<SearchHit>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Search',
    barrierColor: MutandeColors.stone100,
    transitionDuration: Duration(milliseconds: reduce ? 0 : 200),
    pageBuilder: (ctx, animation, secondary) {
      return SearchDialog(
        daemon: daemon,
        myHandle: myHandle,
        recentQueries: recentQueries,
        onRememberQuery: onRememberQuery,
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) {
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
```

## Target

Open and close with **no** transition. Barrier still `MutandeColors.stone100`. Dialog content unchanged.

```dart
/* target — showSearchDialog */
  return showGeneralDialog<SearchHit>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Search',
    barrierColor: MutandeColors.stone100,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, animation, secondary) {
      return SearchDialog(
        daemon: daemon,
        myHandle: myHandle,
        recentQueries: recentQueries,
        onRememberQuery: onRememberQuery,
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) => child,
  );
```

Delete the unused `reduce` local in `showSearchDialog` if nothing else in that function reads it.

## Repo conventions to follow

- Prefer `MediaQuery.disableAnimationsOf(context)` at widget build sites (exemplar: `app/lib/widgets/person_identity_row.dart:79`). This function has no remaining motion, so no gate is needed.
- Do not change `_DialogSearchField` or `_ScopeChip` here (plans 002 / 012).

## Steps

1. In `app/lib/widgets/search_dialog.dart`, function `showSearchDialog`, set `transitionDuration: Duration.zero`.
2. Replace `transitionBuilder` with `(ctx, animation, secondary, child) => child`.
3. Remove the `reduce` local, the `CurvedAnimation`, `FadeTransition`, and `SlideTransition` from this function only.
4. Leave `SearchDialog` widget, chips, and field as they are.

## Boundaries

- Do NOT change `app/lib/app.dart` key bindings.
- Do NOT change chip/field `AnimatedContainer`s (002 / 012).
- Do NOT add dependencies.
- If `showSearchDialog` no longer uses `showGeneralDialog`, STOP and report.

## Verification

- **Mechanical**: `cd app && flutter test test/search_dialog_test.dart` — pass (`SearchDialog` is pumped directly; open transition is unused there). `dart analyze lib/widgets/search_dialog.dart` — no errors.
- **Feel check**: run the macOS app, press `/` (or `⌘K`) from Threads home:
  - Palette is on screen on the first frame — no fade, no 2% slide.
  - Esc / dismiss is equally instant.
  - Slow animations in Flutter DevTools to 5×: still no travel.
  - Reduce Motion on: still instant (same as default).
- **Done when**: `transitionDuration` is `Duration.zero` and `transitionBuilder` returns `child` unchanged.
