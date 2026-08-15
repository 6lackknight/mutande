# 006 — Cap Network graph enter and quiet hover

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: MEDIUM
- **Category**: Cohesion + Easing & duration
- **Estimated scope**: 1 file, graph enter / hover only

## Problem

People and Agents orbit graphs take **680ms** to enter (UI budget **under 300ms**). Nodes wait `180 + min(i * 70, 280)` then play **420ms**. Hover scales to **1.05** (playful). Press and release share **180ms** (release should snap). Appear scale starts at **0.86** (floor is 0.9–0.97). Reduced motion is already gated.

```dart
/* app/lib/screens/agents_screen.dart:798-800 and :1007-1009 — current */
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
```

```dart
/* app/lib/screens/agents_screen.dart:918-920 and :1128-1130 — current */
                    appearDelay: graphReady
                        ? Duration.zero
                        : Duration(milliseconds: 180 + math.min(i * 70, 280)),
```

```dart
/* app/lib/screens/agents_screen.dart:1212-1214, 1238-1291 — current */
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final motion = _agentsMotion(context, const Duration(milliseconds: 180));
    final hoverScale = widget.reduceMotion
        ? 1.0
        : _press
        ? 0.96
        : _hover
        ? 1.05
        : 1.0;
    …
              child: Transform.scale(
                scale: widget.reduceMotion ? 1 : 0.86 + 0.14 * at,
```

```dart
/* app/lib/screens/agents_screen.dart:67-75 — current */
Duration _agentsMotion(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
double _easeUnit(double t, double begin, double end) {
  …
  return Curves.easeOutCubic.transform(u);
}
```

## Target

| Parameter | Value |
| --- | --- |
| `_enter` duration (both graphs) | **300ms** (UI cap) |
| Node `_appear` duration | **200ms** (`MutandeMotion.ui`) |
| Stagger | **30–80ms**: `Duration(milliseconds: math.min(i * 40, 80))` when not `graphReady` |
| Appear scale | **0.95 + 0.05 * at** (starts 0.95) |
| Hover scale | **1.0** (color/border only; no grow) |
| Press scale | **0.97** (range 0.95–0.98) |
| Press duration | `MutandeMotion.press` = **160ms**, curve `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)` |
| Release duration | **`Duration.zero`** (system response snaps) |

Asymmetric press: when `_press` is true use 160ms ease-out; when false (hover or rest) use `Duration.zero` for the scale retarget so release snaps.

```dart
final scaleDuration = widget.reduceMotion || !_press
    ? Duration.zero
    : MutandeMotion.press;
final hoverScale = widget.reduceMotion
    ? 1.0
    : _press
    ? 0.97
    : 1.0;
```

`_easeUnit`: `MutandeMotion.easeOut.transform(u)` (`Cubic(0.23, 1.0, 0.32, 1.0)`). Add `import '../theme/mutande_macos_theme.dart';`.

Keep `_agentsMotion` and existing `disableAnimationsOf` jumps to `_enter.value = 1`.

## Repo conventions to follow

- `_agentsMotion` is the local reduced-motion helper — keep it.
- Do not restyle `peer_popover.dart` in this plan.
- Quiet courier: no 1.05 hover bounce.

## Steps

1. Import `../theme/mutande_macos_theme.dart` in `app/lib/screens/agents_screen.dart`.
2. Set both `_enter` controllers (`_PeopleOrbitGraphState`, `_AgentsGraphState`) to `duration: const Duration(milliseconds: 300)`.
3. Replace both `appearDelay` expressions with `graphReady ? Duration.zero : Duration(milliseconds: math.min(i * 40, 80))`.
4. `_OrbitDiscNodeState`: `_appear` duration 200ms; appear scale `0.95 + 0.05 * at`; hoverScale / AnimatedScale duration as Target; press 0.97.
5. `_easeUnit`: `MutandeMotion.easeOut.transform(u)` (fallback `const Cubic(0.23, 1.0, 0.32, 1.0).transform(u)`).

## Boundaries

- Do NOT change peer popover, list/graph toggle layout, or agent inspector `AnimatedSize` error banner.
- Do NOT change thinking orb / morph / onboarding.
- Do NOT add new packages.
- If graph widget class names differ from `_PeopleOrbitGraphState` / `_AgentsGraphState`, STOP and report.

## Verification

- **Mechanical**: `cd app && dart analyze lib/screens/agents_screen.dart`
- **Feel check**: Network → People, then Agents. Hub + rings finish by ~300ms; last disc is not still arriving at ~1s. Hovering a disc does not grow it. Pressing shrinks slightly (~3%) and **snaps** back on release. Reduce motion: graphs appear fully formed, no scale/inward travel. Flutter DevTools 5×: enter is a short ease-out, not a long cascade.
- **Done when**: both enters are 300ms, stagger ≤80ms, appear scale ≥0.95, hover scale 1.0, press 0.97 / 160ms / snap release.
