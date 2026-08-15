# 004 — Connect-host scale 0.95 and delete dead check wait

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: MEDIUM
- **Category**: Purpose & frequency + Physicality & origin
- **Estimated scope**: 1 file, ~40 lines removed / retimed

## Problem

The connect dialog scales from **0.78** over **420ms** (below the 0.9–0.97 floor; sluggish). `_checkCtrl` is a 420ms `AnimationController` that is forwarded twice and **never painted**, then another 280ms `Future.delayed` gates MCP → skill.

```dart
/* app/lib/widgets/connect_host_flow.dart:91-107 — current */
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, animation, secondary) => dialog,
    transitionBuilder: (ctx, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.78, end: 1).animate(curved),
          alignment: alignment,
          child: child,
        ),
      );
    },
```

```dart
/* app/lib/widgets/connect_host_flow.dart:134-158, 206-213, 263-265 — current */
class _ConnectHostFlowDialogState extends State<_ConnectHostFlowDialog>
    with SingleTickerProviderStateMixin {
  …
  late final AnimationController _checkCtrl;
  …
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  …
      if (!_reduceMotion) {
        await _checkCtrl.forward(from: 0);
      }
      await Future<void>.delayed(
        Duration(milliseconds: _reduceMotion ? 80 : 280),
      );
      if (!mounted) return;
      await _runSkill();
  …
      if (skill.ok && !_reduceMotion) {
        await _checkCtrl.forward(from: 0);
      }
```

`AnimatedSwitcher` at `:354-355` uses default **linear** enter (220ms) with no `layoutBuilder`.

## Target

Modal enter (budget 200–500ms; pick **200ms**):

- `transitionDuration: MutandeMotion.ui` → `Duration(milliseconds: 200)` (or `Duration.zero` when `reduceMotion` is already true — this branch uses `showDialog` instead, so only the `showGeneralDialog` path needs 200ms).
- Scale tween **0.95 → 1.0** (range 0.9–0.97). Keep `alignment` from `morphOrigin`.
- Opacity via existing `FadeTransition`.
- Curve: `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)` (`cubic-bezier(0.23, 1, 0.32, 1)`). Keep `reverseCurve: Curves.easeInCubic` (exit pairing).

Delete `_checkCtrl` entirely. After MCP success `setState`, call `await _runSkill()` immediately (no 280ms delay). After skill success, do not `forward` anything.

`AnimatedSwitcher`:

```dart
final body = AnimatedSwitcher(
  duration: Duration(milliseconds: _reduceMotion ? 0 : 200),
  switchInCurve: MutandeMotion.easeOut,
  switchOutCurve: MutandeMotion.easeOut,
  layoutBuilder: (current, previous) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [...previous, ?current],
    );
  },
  child: KeyedSubtree(
    key: ValueKey('${_step}_$_busy$_error$_skillStatus'),
    child: _body(label, showSkillActions),
  ),
);
```

Leave `celebrateFirstHost` 520ms hold in `_finish` as-is.

## Repo conventions to follow

- Morph-from-tile `alignment` is by-design — keep it (`connect_host_flow.dart:81-84`).
- Stacked `AnimatedSwitcher` `layoutBuilder` exemplar: `app/lib/widgets/morphing_orb_button.dart:64-68`.
- Reduced-motion already skips this `showGeneralDialog` (`:71-77` uses plain `showDialog`). Do not remove that branch.
- File already imports `mutande_macos_theme.dart`.

## Steps

1. `showConnectHostFlow` `showGeneralDialog`: `transitionDuration: const Duration(milliseconds: 200)` (or `MutandeMotion.ui`). Scale `Tween<double>(begin: 0.95, end: 1)`. Curve `MutandeMotion.easeOut` on the `CurvedAnimation`.
2. Remove `SingleTickerProviderStateMixin` from `_ConnectHostFlowDialogState`.
3. Remove `_checkCtrl` field, init, dispose, both `forward(from: 0)` calls, and the `Future<void>.delayed` after MCP success. Call `await _runSkill()` right after the MCP success `setState` (still `if (!mounted) return` first).
4. Update `AnimatedSwitcher` as in Target.
5. Confirm `_checkCtrl` has no remaining references.

## Boundaries

- Do NOT change MCP/skill RPC, letterhead, Hero tag, or `celebrateFirstHost` delay.
- Do NOT edit `thinking_orb.dart` / morph button motion besides using morph’s `layoutBuilder` as a pattern.
- Do NOT add a painted checkmark.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/connect_host_flow.dart`. Grep the file: `_checkCtrl` must not appear.
- **Feel check**: Settings → connect a host from a tile (morphOrigin path). Dialog grows from the tile, starting visibly ~95% size, done in ~200ms — not a pop from 78%. MCP success advances to skill **immediately** (no ~700ms pause). Reduce motion: still the non-morph `showDialog` path. Flutter DevTools 5×: scale travel is small. Spam is not required (barrier is non-dismissible).
- **Done when**: scale begin is 0.95, duration 200ms, `_checkCtrl` gone, no post-MCP delay, switcher uses ease-out + stack layoutBuilder.
