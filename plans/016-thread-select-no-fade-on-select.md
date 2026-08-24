# 016 — Thread select: bypass MutandeFadeSwap crossfade

- **Status**: TODO
- **Commit**: f14dae9
- **Severity**: HIGH
- **Category**: Performance / Purpose & frequency
- **Estimated scope**: 2 files, ~35 lines

## Problem

`MutandeFadeSwap` wraps the reading pane and runs a **200ms** `AnimatedSwitcher` stack whenever `_loading` or `_detail` keys change — including thread selection when **014**’s bug forces `_loading` true. Even after **014**, switching threads changes the child key (`read` vs `sk`) if any loading flicker remains.

```dart
/* app/lib/screens/threads_screen.dart:2101-2114 — current */
          child: MutandeFadeSwap(
            child: _loading
                ? const ThreadReadingSkeleton(key: ValueKey('sk'))
                : _detail == null
                ? PaneQuietState(
                    key: const ValueKey('missing'),
                    ...
                : ThreadRelayReading(
                    key: const ValueKey('read'),
```

```dart
/* app/lib/widgets/thread_skeletons.dart:721-744 — current */
class MutandeFadeSwap extends StatelessWidget {
  ...
    return AnimatedSwitcher(
      duration: MutandeMotion.of(context, MutandeMotion.ui),
```

Plan **011** boundary: “Do NOT fade thread selection (list tap → other thread).” Current wiring violates that on every select-induced skeleton.

Stacking outgoing + incoming reading panes during fade also doubles layout cost (full message list × 2) — frame drops on macOS.

## Target

- **Thread selection** (same `ThreadDetailPanel` instance, `threadId` changed): **instant child swap**, `Duration.zero`, no `AnimatedSwitcher`.
- **Cold load / skeleton → content** (first paint, filter change, force refresh): keep **200ms** opacity crossfade via `MutandeFadeSwap`, `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)`.
- Reduced motion: `MutandeMotion.of` already returns `Duration.zero` — unchanged.

Implementation: add optional parameter to fade helper:

```dart
class MutandeFadeSwap extends StatelessWidget {
  const MutandeFadeSwap({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return AnimatedSwitcher(
      duration: MutandeMotion.of(context, MutandeMotion.ui),
      ...
    );
  }
}
```

In `_ThreadDetailPanelState.build`, compute:

```dart
final fadeReading = _loading && _detail == null; // cold / force only
...
Expanded(
  child: MutandeFadeSwap(
    animate: fadeReading,
    child: keyedChild,
  ),
)
```

When swapping cached threads (**014**), `_detail` stays non-null → `animate: false` → snap.

Optional prototype variant **C**: if product wants a **100ms** select crossfade later, that is a separate LOW plan — default is **zero** per AUDIT frequency table (“tens of times per day → remove or drastically reduce”).

## Repo conventions to follow

- `MutandeFadeSwap` lives in `app/lib/widgets/thread_skeletons.dart` (plan 011).
- List pane `_buildListPane` keeps `MutandeFadeSwap` for **filter/load** only — do not change list select behavior there.
- Exemplar for zero-duration high-frequency UI: plan **001** search palette (no open animation).

## Steps

1. `app/lib/widgets/thread_skeletons.dart` — add `animate` parameter (default `true`); early-return `child` when `false`.
2. `app/lib/screens/threads_screen.dart` — define `fadeReading` as above; pass to reading pane `MutandeFadeSwap`.
3. Ensure `ThreadRelayReading` child key includes `widget.threadId` when not fading, e.g. `ValueKey('read-${widget.threadId}')`, so Flutter replaces the subtree without switcher animation when `animate: false`.
4. Verify force refresh (`_load(force: true)`) with existing `_detail` keeps `animate: false` (SWR: content stays visible).

## Boundaries

- Do NOT remove `MutandeFadeSwap` from list pane initial hydrate.
- Do NOT add blur (optional in 011) on select path.
- Do NOT change tab body crossfades (out of scope per README).
- Do NOT change collab board fade unless same pattern confirmed.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/thread_skeletons.dart lib/screens/threads_screen.dart`
- **Feel check**: warm cache, switch threads — **no** 200ms crossfade, no ghost of previous thread fading out. Cold start: skeleton still crossfades to content ~200ms. Record screen at 60fps: select should be 1-frame content swap after **014**+**015**.
- **Done when**: `animate: false` on all cache-hit thread selects; `animate: true` only when `_loading && _detail == null`.

## Dependencies

Execute after **014** (needs stable `_detail` on select). Safe in parallel with **015**; integrate both before feel-check.
