# 007 — Mail accordion: no layout animation, gate reduced motion

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: MEDIUM
- **Category**: Performance + Accessibility
- **Estimated scope**: 1 widget in `thread_relay_reading.dart`

## Problem

Expanding/collapsing a Relay message uses `AnimatedSize` (layout + paint) at 160ms with no `disableAnimations` gate.

```dart
/* app/lib/widgets/thread_relay_reading.dart:1111-1117 — current */
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 2),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
```

Animate **transform and opacity only**. Accordion size must snap. Reduced motion keeps opacity/color, drops movement.

## Target

1. Remove `AnimatedSize`. The `Column` stays a direct child of the `Padding`.
2. Size of open vs clamped body **snaps** (no height tween).
3. Optional comprehension fade on the **body that just appeared** only:

Wrap `_openBody()` (both OP and reply branches) in:

```dart
AnimatedOpacity(
  opacity: 1,
  duration: MutandeMotion.of(context, MutandeMotion.press),
  curve: MutandeMotion.easeOut,
  child: _openBody(),
)
```

`MutandeMotion.press` = `Duration(milliseconds: 160)`; `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)`; `of` → `Duration.zero` under `disableAnimations`.

Because `AnimatedOpacity` with a constant `opacity: 1` does **not** fade unless the widget is new, key it:

```dart
AnimatedOpacity(
  key: ValueKey('open-${message.id}'),
  opacity: 1,
  duration: MutandeMotion.of(context, MutandeMotion.press),
  curve: MutandeMotion.easeOut,
  child: _openBody(),
)
```

First frame of a new keyed opacity widget interpolates from 0 if you instead use a tiny Stateful wrapper. Simpler executor path that still meets the finding:

**Preferred (minimum):** delete `AnimatedSize`, leave the `Column` unwrapped. Open/close snaps. That satisfies “avoid layout animation” and reduced motion (nothing moves).

**Do not** keep `AnimatedSize` even with `Duration.zero` under reduce — delete it so motion-on also avoids layout.

File already imports `mutande_macos_theme.dart`. `_RailItem` is a `StatelessWidget` with `context` in `build`.

## Repo conventions to follow

- One message open at a time is product behavior — do not change that.
- `MutandeMotion.of` exemplar after 008; else `MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160)`.
- Do not restyle the rail painter or composer in this plan (composer is 012).

## Steps

1. In `_RailItem.build`, remove the `AnimatedSize` widget. Keep the `Padding` and inner `Column` (replyToLabel / OP / reply branches) identical.
2. Do not add `AnimatedAlign`, `SizeTransition`, or height `Tween`.
3. If you add an opacity fade, only wrap `_openBody()` with `AnimatedOpacity` + `ValueKey`, duration `MutandeMotion.of(context, MutandeMotion.press)`, curve `MutandeMotion.easeOut`. Skip fade if the keyed first-frame fade is unclear — snapping is the required outcome.

## Boundaries

- Do NOT change composer, attachments, inspector toggle, or thread list.
- Do NOT change `_kOpMaxLines` / `_kReplyMaxLines`.
- Do NOT add blur filters.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/widgets/thread_relay_reading.dart`
- **Feel check**: open a thread with several messages. Click the OP, then a reply. The rail/dot can change immediately; body height must **not** ease. No squashing text. Reduce motion: same snap (and any opacity fade is 0ms). Flutter DevTools 5×: no layout size tween on the column.
- **Done when**: `AnimatedSize` is gone from `_RailItem`; expand/collapse does not animate height.
