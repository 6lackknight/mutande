# 015 — Thread select: do not replay message stagger

- **Status**: TODO
- **Commit**: f14dae9
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 2 files, ~25 lines

## Problem

Each thread switch remounts `MutandeStaggerScope(key: ValueKey(d.id))`, replaying up to 7 staggered opacity + 3px translate animations (40ms steps, 200ms each). Stagger is for **first paint after skeleton**, not list navigation (tens of times per day).

```dart
/* app/lib/widgets/thread_relay_reading.dart:917-919 — current */
          child: MutandeStaggerScope(
            key: ValueKey(d.id),
            child: ListView.builder(
```

Comment at 914-916 says “remounts on open/select” — select should **not** restagger.

## Target

Message rows appear **at rest** (opacity 1, translate 0) when the timeline mounts due to **thread selection**. Stagger may still run on the **first** timeline paint after a skeleton on cold load only.

**Option A (preferred, minimal):** Add `bool animateEnter = true` to `ThreadRelayReading`; pass `animateEnter: false` from `ThreadDetailPanel` when `_detail` was painted from cache on a thread-id change (track `_staggerEnter` flag cleared after first build).

When `animateEnter` is false, render `ListView.builder` **without** `MutandeStaggerScope` / `MutandeStaggerIn` wrappers — plain `_RailItem` children.

When `animateEnter` is true (cold load / skeleton → content), keep current `MutandeStaggerScope(key: ValueKey(d.id))` behavior.

**Option B:** Keep scope but pass a frozen gate — more invasive; use only if Option A duplicates too much list code.

No new durations. Stagger when enabled stays: `MutandeStaggerScope.stagger` = 40ms, `MutandeMotion.ui` = 200ms, `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)`.

## Repo conventions to follow

- Stagger implementation: `app/lib/widgets/mutande_stagger.dart` — gate freezes after first frame; do not change gate logic globally.
- `MutandeStaggerScope.maxItems` = 7, `maxDelay` = 240ms — unchanged.
- Exemplar for conditional stagger: onboarding uses stagger once; everyday lists freeze gate — same philosophy.

## Steps

1. `app/lib/widgets/thread_relay_reading.dart` — add `final bool animateEnter` to `ThreadRelayReading` (default `true` for tests/callers).
2. In `_RelayTimelineState.build`, branch:
   - `animateEnter == true`: existing `MutandeStaggerScope` + `MutandeStaggerIn` tree.
   - `animateEnter == false`: same `ListView.builder` with direct `_RailItem` children (no stagger wrappers).
3. `app/lib/screens/threads_screen.dart` — on `_ThreadDetailPanelState`, add `bool _animateReadingEnter = true`.
4. Set `_animateReadingEnter = false` when `_switchThread` / cache paint succeeds on thread id change; set `true` only when transitioning from skeleton (`_loading` was true and `_detail` was null).
5. Pass `animateEnter: _animateReadingEnter` into `ThreadRelayReading` at ~2112.

## Boundaries

- Do NOT remove stagger from cold load (skeleton → first content).
- Do NOT change `_Arrive` / skeleton breath in `thread_skeletons.dart`.
- Do NOT change collab stagger unless explicitly scoped later.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/thread_relay_reading.dart lib/screens/threads_screen.dart && flutter test`
- **Feel check**: with warm cache, switch threads rapidly — messages should **not** cascade fade/slide in. Cold open (clear mailbox / new thread): stagger still plays once after skeleton. DevTools 5× slow: confirm no stagger timers firing on select when `animateEnter: false`.
- **Done when**: thread select shows timeline at full opacity immediately; cold load retains stagger.

## Dependencies

Execute after **014** (so select path paints cache without skeleton flash first).
