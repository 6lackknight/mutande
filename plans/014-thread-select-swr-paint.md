# 014 — Thread select: paint mailbox cache before clearing detail

- **Status**: TODO
- **Commit**: f14dae9
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 1 file, ~40 lines in `ThreadDetailPanel`

## Problem

Every list tap clears `_detail` and forces the loading branch, even when the mailbox already has the target thread. That triggers skeleton + crossfade + stagger on a **high-frequency** action (tens of times per day).

```dart
/* app/lib/screens/threads_screen.dart:1776-1785 — current */
  void didUpdateWidget(covariant ThreadDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      unawaited(_mailbox?.clearPreviewsForDetail(_detail));
      _reply.clear();
      _replyToMessageId = null;
      _replyToHandle = null;
      _detail = null;
      _softRefreshPending = false;
      _load();
```

```dart
/* app/lib/screens/threads_screen.dart:1840-1846 — current */
    } else if (!silent) {
      if (_detail == null) {
        setState(() {
          _loading = true;
          _error = null;
        });
```

Plan **011** explicitly scoped crossfade to **initial load**, not thread selection (`Do NOT fade thread selection`). Clearing `_detail` on select violates that intent.

## Target

On `threadId` change:

1. **Do not** set `_detail = null` before attempting a synchronous cache read path.
2. If mailbox has cached detail for the new id, `setState` paint it immediately with `_loading = false` (prototype variant **A** / **B**).
3. If no cache, keep **previous** `_detail` visible (variant **B**) until `loadThreadDetail` returns or daemon RPC completes — never flash `PaneQuietState` or skeleton when switching between two previously opened threads.
4. Only set `_loading = true` on **cold open** (first mount with no prior detail), not on select when holding previous content.

Add a field to track paint generation, e.g. `int _openGen = 0`, increment on each `threadId` change; ignore stale async results when `gen != _openGen`.

Sketch for `didUpdateWidget`:

```dart
if (oldWidget.threadId != widget.threadId) {
  final prevId = oldWidget.threadId;
  unawaited(_mailbox?.clearPreviewsForDetail(
    _detail?.id == prevId ? _detail : null,
  ));
  _reply.clear();
  _replyToMessageId = null;
  _replyToHandle = null;
  _softRefreshPending = false;
  final gen = ++_openGen;
  unawaited(_switchThread(gen: gen));
}
```

`_switchThread` async:

```dart
Future<void> _switchThread({required int gen}) async {
  final box = _mailbox;
  ThreadDetailResult? cached;
  if (box != null) {
    try {
      cached = await box.loadThreadDetail(widget.threadId);
    } catch (_) {}
  }
  if (!mounted || gen != _openGen) return;
  if (cached != null) {
    setState(() {
      _detail = cached;
      _loading = false;
      _error = null;
    });
    unawaited(_load(silent: true)); // freshness check only
    return;
  }
  // No cache: hold previous detail (do not null _detail), silent revalidate
  unawaited(_load(silent: _detail != null));
}
```

Remove `_detail = null` from the select path entirely.

## Repo conventions to follow

- SWR pattern already used for silent poll: `_load(silent: true)` and `mailbox_stale_bg` trace paths in the same file (~1864-1890).
- `MutandeMotion` / `disableAnimations`: no new motion on this fix — **snap** is correct.
- Exemplar: collab open in `app/lib/screens/collab_screen.dart:469-505` (cache-first, spinner only on cold miss).

## Steps

1. `app/lib/screens/threads_screen.dart` — add `int _openGen = 0` to `_ThreadDetailPanelState`.
2. Replace the `threadId` branch in `didUpdateWidget` with generation bump + `_switchThread` (no `_detail = null`).
3. Implement `_switchThread` as above using real `ThreadDetailResult?` and existing `_load(silent: …)` for stale revalidation.
4. Adjust `_load` so `silent: true` with existing `_detail` never sets `_loading = true` (verify current guard at ~1834-1838; extend if needed).
5. Ensure `initState` `_load()` unchanged for true cold open (`_detail == null` → skeleton OK once per panel lifetime).

## Boundaries

- Do NOT change `MutandeFadeSwap`, stagger, or list row widgets in this plan.
- Do NOT add IndexedStack / per-thread widget cache (memory tradeoff — separate decision).
- Do NOT change collab board unless the same bug is confirmed there.
- If `loadThreadDetail` signature differs, adapt without improvising new APIs.

## Verification

- **Mechanical**: `cd app && dart analyze lib/screens/threads_screen.dart && flutter test test/thread_repository_test.dart`
- **Feel check**: warm mailbox (open app, wait for sync). Rapidly click 5 different threads:
  - No skeleton flash between cached threads
  - No brief “Thread unavailable” pane
  - `[mutande.mail] thread.open path=mailbox_fresh` on repeat opens
  - First-ever open of a thread may still skeleton once (cold) — OK
  - Reduce motion: still instant paint, no extra fades from this plan
- **Done when**: thread select never sets `_loading = true` when mailbox returns a row for the target id; prior detail stays visible until replacement paints on cache miss.
