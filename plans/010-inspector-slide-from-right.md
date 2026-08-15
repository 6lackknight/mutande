# 010 — Inspector slides in from the right

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: MEDIUM (missed opportunity)
- **Category**: Missed opportunities
- **Estimated scope**: `threads_screen.dart` detail pane host only

## Problem

Toggling the inspector swaps two different trees (padded pane vs `ResizableContainer`). The 200px sidebar teleports.

```dart
/* app/lib/screens/threads_screen.dart:1713-1718 — current */
  Future<void> _toggleInspector() async {
    final next = !_inspectorVisible;
    setState(() => _inspectorVisible = next);
    await widget.notificationPrefs.update(
      (p) => p.copyWith(threadInspectorVisible: next),
    );
  }
```

```dart
/* app/lib/screens/threads_screen.dart:1936-1964 — current */
    if (!widget.embedded) return pane;

    if (_loading || _detail == null || !_inspectorVisible) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: pane,
      );
    }

    return ResizableContainer(
      direction: Axis.horizontal,
      children: [
        ResizableChild(
          size: const ResizableSize.expand(),
          divider: _splitDivider(1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: pane,
          ),
        ),
        ResizableChild(
          size: const ResizableSize.pixels(200, min: 180, max: 360),
          child: ThreadInspectorSidebar(
            detail: _detail!,
            myHandle: widget.myHandle,
          ),
        ),
      ],
    );
```

## Target

When `_detail != null && !_loading` (embedded), always build the `ResizableContainer` with two children so hide/show can retarget.

Wrap the sidebar in:

```dart
ClipRect(
  child: AnimatedSlide(
    offset: _inspectorVisible ? Offset.zero : const Offset(1, 0),
    duration: MutandeMotion.of(context, MutandeMotion.ui),
    curve: MutandeMotion.easeDrawer,
    child: AnimatedOpacity(
      opacity: _inspectorVisible ? 1 : 0,
      duration: MutandeMotion.of(context, MutandeMotion.ui),
      curve: MutandeMotion.easeOut,
      child: ThreadInspectorSidebar(
        detail: _detail!,
        myHandle: widget.myHandle,
      ),
    ),
  ),
)
```

Exact values:

- `MutandeMotion.ui` = `Duration(milliseconds: 200)` (modals/drawers 200–500ms; pick 200).
- `MutandeMotion.easeDrawer` = `Cubic(0.32, 0.72, 0.0, 1.0)` (`cubic-bezier(0.32, 0.72, 0, 1)`).
- `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)`.
- `MutandeMotion.of` → `Duration.zero` under `disableAnimations` (opacity may still snap to 0/1 — movement dropped).

When `_inspectorVisible` is false, set the second `ResizableChild` size to `const ResizableSize.pixels(0, min: 0, max: 360)` **only if** that API accepts 0. If `min: 180` cannot go to 0, keep `pixels(200, min: 180, max: 360)` while sliding content away with `ClipRect` (a 200px empty column is **not** acceptable). Preferred: `ResizableSize.pixels(_inspectorVisible ? 200 : 0, min: 0, max: 360)` if the package allows.

`AnimatedSlide` / width change is movement — under reduce, `Duration.zero` so the column appears/disappears without travel.

Do not restyle `ThreadInspectorSidebar` internals.

`_toggleInspector` can stay a boolean `setState`; implicit `AnimatedSlide` retargets if the user spam-toggles.

## Repo conventions to follow

- Split already uses `flutter_resizable_container` (`threads_screen.dart:3`). Do not add another package.
- `_splitDivider(1)` stays on the reading child.
- File already imports `mutande_macos_theme.dart`.
- Inspector contents: `app/lib/widgets/thread_inspector_sidebar.dart` — facts only, no enter of its own.

## Steps

1. Change the host so `_loading || _detail == null` still returns the padded pane only.
2. When `widget.embedded && _detail != null && !_loading`, **always** return `ResizableContainer` (even if inspector hidden).
3. Wrap `ThreadInspectorSidebar` with `ClipRect` + `AnimatedSlide` + `AnimatedOpacity` as Target.
4. Drive second child width from `_inspectorVisible` without animating `width` via `AnimatedContainer` if `ResizableSize` can switch 200 ↔ 0 instantly while slide handles the visual. If 0 is illegal, keep 200 and clip the sliding child — then **also** collapse the `ResizableChild` on `AnimatedSlide` completion via a local `_inspectorMounted` flag. Prefer the 200↔0 size if the package allows `min: 0`.
5. Leave prefs write in `_toggleInspector` unchanged.

## Boundaries

- Do NOT animate Threads · Collab · Network tab bodies (high frequency — no animation).
- Do NOT animate thread-to-thread reading swaps.
- Do NOT restyle sidebar facts/chips.
- Do NOT change default 200 / min 180 / max 360 when the inspector is **open**.
- Do NOT add dependencies.

## Verification

- **Mechanical**: `cd app && dart analyze lib/screens/threads_screen.dart && flutter test test/thread_inspector_sidebar_test.dart test/widget_test.dart`
- **Feel check**: open a thread, hide inspector, show it. Panel comes from the **right**, ~200ms, drawer curve (fast start). Hide reverses. Drag the split — still resizable when open. Spam the toggle: slide retargets, does not restart from a blank frame. Reduce motion: panel appears/disappears with no slide (opacity/instant). Flutter DevTools 5×: origin is the right edge, not center.
- **Done when**: show/hide uses 200ms `Offset(1,0)` slide + opacity; open size still ~200px and resizable; reduced motion drops the slide.
