# 013 — Create-collab sheet opens from the Create control

- **Status**: TODO
- **Commit**: b5369e9
- **Severity**: MEDIUM (missed opportunity + physicality)
- **Category**: Physicality & origin
- **Estimated scope**: 4 lib files + 1–2 tests (~80 lines)

## Problem

The create-collab dialog is a **trigger-anchored** surface (it comes from New collab / empty-state Create). Today it uses macos_ui `showMacosSheet`, which always **scale-bounces from center** on enter (450ms spring) and **fades only** on exit (120ms). That hides the spatial link to the button and overshoots the 300ms UI budget with bounce.

There is **no Create control in home chrome**. Callers are only:

1. Collab home empty state — `PaneQuietState` `retryLabel: 'Create'`
2. Collab dashboard metric row — `_CreateTile` labeled **New collab** (`Key('collab-create-tile')`)

```dart
/* app/lib/widgets/create_collab_sheet.dart:163-181 — current */
Future<CollabDetail?> showCreateCollabSheet({
  required BuildContext context,
  required DaemonClient daemon,
  String? handle,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = size.width.clamp(360.0, 480.0);
  final height = (size.height - 72).clamp(400.0, 560.0);
  return showMacosSheet<CollabDetail>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => MacosSheet(
      child: SizedBox(
        width: width,
        height: height,
        child: CreateCollabSheet(daemon: daemon, handle: handle),
      ),
    ),
  );
}
```

macos_ui `showMacosSheet` route (do not edit the package — this is why we stop calling it):

```dart
/* macos_ui-2.2.2 lib/src/sheets/macos_sheet.dart:168-211 — current (package) */
  Duration get transitionDuration => const Duration(milliseconds: 450);
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);
  // enter: ScaleTransition + _SubtleBounceCurve (SpringDescription damping 14, mass 1.4, stiffness 180)
  // exit (reverse): FadeTransition only, Curves.easeOutSine — no scale back to origin
```

```dart
/* app/lib/screens/collab_screen.dart:121-131, 157-184 — current */
  Future<void> _create() async {
    final created = await showCreateCollabSheet(
      context: context,
      daemon: widget.daemon,
      handle: widget.handle,
    );
    …
  }
  // empty: PaneQuietState(..., retryLabel: 'Create', onRetry: _create)
  // dash:  CollabMetricRow(..., onCreate: _create)
```

```dart
/* app/lib/widgets/collab/collab_metric_row.dart:16, 136-164 — current */
  final VoidCallback onCreate;
  …
class _CreateTile extends StatelessWidget {
  …
    return KeyedSubtree(
      key: const Key('collab-create-tile'),
      child: CollabDashCard(
        onTap: onTap,  // no Rect captured
```

## Target

Replace **only the route**. Keep `MacosSheet` as the **visual chrome** (12px radius, double border). Do **not** switch to `showModalBottomSheet`.

Enter and exit (same 200ms; route animation reverses on dismiss):

| Property | Value |
| --- | --- |
| Duration | `MutandeMotion.ui` = `Duration(milliseconds: 200)` |
| Reduced motion | `Duration.zero`; `transitionBuilder` returns `child` (snap — no scale) |
| Curve (enter **and** exit) | `MutandeMotion.easeOut` = `Cubic(0.23, 1.0, 0.32, 1.0)` (`cubic-bezier(0.23, 1, 0.32, 1)`) |
| Reverse curve | **also** `MutandeMotion.easeOut` — do **not** copy `Curves.easeInCubic` from connect-host (that is ease-in on the way out) |
| Scale | `Tween<double>(begin: 0.95, end: 1.0)` — never `0.0`; floor is 0.9–0.97 |
| Opacity | `FadeTransition` on the same `CurvedAnimation` |
| Transform origin | `ScaleTransition.alignment` from the **Create control’s screen rect**, same math as connect-host |
| Animate | `transform` + `opacity` only |
| Bounce | none — no springs, no `Curves.elastic*`, no macos `_SubtleBounceCurve` |

```dart
/* target — createCollabSheetAlignment; copy connect-host math, do not edit connect_host_flow.dart */
Alignment createCollabSheetAlignment(Rect origin, Size screen) {
  if (screen.width <= 0 || screen.height <= 0) return Alignment.center;
  return Alignment(
    ((origin.center.dx / screen.width) * 2 - 1).clamp(-1.0, 1.0),
    ((origin.center.dy / screen.height) * 2 - 1).clamp(-1.0, 1.0),
  );
}

Rect? createCollabOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
```

```dart
/* target — showCreateCollabSheet */
Future<CollabDetail?> showCreateCollabSheet({
  required BuildContext context,
  required DaemonClient daemon,
  String? handle,
  Rect? origin,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = size.width.clamp(360.0, 480.0);
  final height = (size.height - 72).clamp(400.0, 560.0);
  final reduce = MediaQuery.disableAnimationsOf(context);
  final sheet = MacosSheet(
    child: SizedBox(
      width: width,
      height: height,
      child: CreateCollabSheet(daemon: daemon, handle: handle),
    ),
  );
  final alignment = (origin != null && !reduce)
      ? createCollabSheetAlignment(origin, size)
      : Alignment.center;

  return showGeneralDialog<CollabDetail>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Create collab',
    barrierColor: const Color(0x660C0A09),
    transitionDuration: reduce ? Duration.zero : MutandeMotion.ui,
    pageBuilder: (ctx, animation, secondary) => sheet,
    transitionBuilder: (ctx, animation, secondary, child) {
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: MutandeMotion.easeOut,
        reverseCurve: MutandeMotion.easeOut,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          alignment: alignment,
          child: child,
        ),
      );
    },
  );
}
```

`MacosSheet` already fills the overlay via its 140/48 inset padding, so `ScaleTransition.alignment` is in **overlay space** (same as connect-host’s `Dialog` + `Center`). Do not wrap in an extra `Center`.

Callers pass the tapped control’s `Rect`:

- `_CollabPanelState._create({Rect? origin})` → `showCreateCollabSheet(..., origin: origin)`
- `_CreateTile` captures `createCollabOrigin(context)` on tap; `CollabMetricRow.onCreate` becomes `void Function(Rect? origin)`
- Empty-state Create: `PaneQuietState.onRetryOrigin` (new optional) captures the **OutlinedButton** bounds, not the whole quiet pane

## Repo conventions to follow

- Morph-from-control: `app/lib/widgets/connect_host_flow.dart:49-108` (`morphOrigin` → `Alignment` → `showGeneralDialog` + `ScaleTransition` 0.95 + `FadeTransition`). Imitate that structure. **Differences required here:** `barrierDismissible: true`; `reverseCurve: MutandeMotion.easeOut` (not `Curves.easeInCubic`); reduced motion **snaps** (`Duration.zero` + identity builder) instead of falling back to `showDialog`.
- Origin capture at tap: `app/lib/screens/settings_screen.dart:1119-1124` (`localToGlobal(Offset.zero) & box.size`).
- Tokens: `app/lib/theme/mutande_macos_theme.dart:26-50` — `MutandeMotion.ui` (200ms), `MutandeMotion.easeOut` (`Cubic(0.23, 1.0, 0.32, 1.0)`), `MutandeMotion.of` / `MediaQuery.disableAnimationsOf` for reduced motion.
- Keep `MacosSheet` widget chrome. Settings (`app/lib/app.dart:915`) stays on `showMacosSheet` — do not migrate it.

## Steps

1. In `app/lib/widgets/create_collab_sheet.dart`, add top-level `createCollabOrigin` and `createCollabSheetAlignment` (exact bodies in Target). Replace `showCreateCollabSheet` as in Target. **Stop at the function** — do not edit `CreateCollabSheet` / `_CreateCollabSheetState` / `_formList` / any `MutandeStagger*` (inner stagger is in-flight on this file).

2. In `app/lib/widgets/collab/collab_metric_row.dart`, change `onCreate` / `_CreateTile.onTap` to `void Function(Rect? origin)`. In `_CreateTile.onTap`, call `onTap(createCollabOrigin(context))`. Import `create_collab_sheet.dart` only for `createCollabOrigin`, or duplicate the 4-line box read locally to avoid a collab-widget → sheet import — **prefer duplicating the 4 lines** (same as settings `_HostTile`) so metric row does not import the sheet.

3. In `app/lib/widgets/pane_quiet_state.dart`, add optional `void Function(Rect? origin)? onRetryOrigin`. Wrap the existing `OutlinedButton` in a `Builder`. If `onRetryOrigin != null`, on press capture that **button** context with the same `localToGlobal` pattern and call `onRetryOrigin`; else call `onRetry`. Do not change title/body/retry styling. Other `PaneQuietState` call sites stay on `onRetry`.

4. In `app/lib/screens/collab_screen.dart`:
   - `Future<void> _create({Rect? origin}) async` and pass `origin:` into `showCreateCollabSheet`.
   - Metric row: `onCreate: (origin) => _create(origin: origin)`.
   - Empty state (`retryLabel: 'Create'` only): `onRetryOrigin: (origin) => _create(origin: origin)` and drop `onRetry` on that instance (or leave `onRetry` unused). Do **not** attach `onRetryOrigin` to the load-error quiet state (`onRetry: _reload`).

5. Tests:
   - `app/test/collab_home_dashboard_test.dart`: `onCreate: (_) => created = true` (or `(origin) { … }`).
   - Add a small test (new file `app/test/create_collab_sheet_origin_test.dart` **or** a group in `create_collab_sheet_test.dart`) for `createCollabSheetAlignment`: a rect in the bottom-right of a 1280×720 screen must produce `alignment.x > 0` and `alignment.y > 0`; a zero-size screen returns `Alignment.center`.
   - Existing `create_collab_sheet_test.dart` pumps `CreateCollabSheet` **without** the route — leave those tests alone (they cover form/stagger). `widget_test.dart` “create collab sheet opens…” still taps `Create` — keep passing; do not rewrite it.

6. `cd app && dart analyze lib/widgets/create_collab_sheet.dart lib/widgets/collab/collab_metric_row.dart lib/widgets/pane_quiet_state.dart lib/screens/collab_screen.dart` then `flutter test test/collab_home_dashboard_test.dart test/create_collab_sheet_test.dart` (plus the new origin test file if added).

## Boundaries

- Do **not** edit `CreateCollabSheet` build, `_formList`, `MutandeStaggerScope`, `MutandeStaggerIn`, chip skeletons, or submit/`_CreateButton`. Another agent owns inner stagger.
- Do **not** change `showMacosSheet` / Settings (`app.dart`), `connect_host_flow.dart`, `search_dialog.dart`, `home_chrome_strip.dart`, `thinking_orb.dart`, or macos_ui.
- Do **not** add a Hero on the + icon.
- Do **not** add dependencies or new easing tokens. No `Curves.easeIn*`, no bounce, no bottom-sheet slide, no `scale(0)`.
- Do **not** animate `width`/`height`/`padding`/`top`/`left`.
- If `showCreateCollabSheet` already takes `origin` or no longer calls `showMacosSheet` (drift since **b5369e9**), STOP and report.

## Verification

- **Mechanical**: analyze clean; dashboard test still taps `Key('collab-create-tile')`; create-collab form tests unchanged; alignment unit test green.
- **Feel check** (macOS app, Collab tab):
  - Empty list: tap **Create**. Sheet grows from that button (~95% → 100%) in ~200ms, ease-out (starts immediately — no 450ms bounce). Dismiss (barrier or Cancel) shrinks **back toward the same button** with fade, ~200ms, no bounce.
  - With collabs: tap **New collab** tile. Same motion from the tile, not from window center.
  - Flutter DevTools Animations at 0.1× / 10%: transform-origin sits on the control; scale travel is small (0.95 not 0).
  - Spam open/dismiss: motion continues from the current value (route transition), never restarts from scale 0.
  - Enable **Disable animations** (`MediaQuery.disableAnimations`): sheet **snaps** in/out; no scale travel.
- **Done when**: `showMacosSheet` is gone from `create_collab_sheet.dart`; enter/exit are 200ms `MutandeMotion.easeOut` scale 0.95 + fade from the Create control; reduced motion is `Duration.zero`; inner stagger widgets in this file are untouched.
