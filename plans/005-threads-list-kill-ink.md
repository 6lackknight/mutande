# 005 — Kill Material ink on the Threads list

- **Status**: TODO
- **Commit**: 946c2bc
- **Severity**: MEDIUM
- **Category**: Cohesion
- **Estimated scope**: 1 widget in 1 file

## Problem

The hottest list in the app uses Material `InkWell` splash/hover overlay. Titlebar tabs are quiet `GestureDetector` fills. Ripples are not a macOS quiet courier.

```dart
/* app/lib/screens/threads_screen.dart:850-888 — current */
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (details) {
            final items = <PopupMenuEntry<String>>[
              if (onMuteToggle != null)
                PopupMenuItem(
                  value: 'mute',
                  child: Text(muted ? 'Unmute' : 'Mute'),
                ),
              if (onClose != null)
                const PopupMenuItem(value: 'close', child: Text('Close')),
              if (onDelete != null)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ];
            if (items.isEmpty) return;
            showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              items: items,
            ).then((value) {
              if (value == 'mute') onMuteToggle?.call();
              if (value == 'close') onClose?.call();
              if (value == 'delete') onDelete?.call();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            color: selected ? MutandeColors.stone100 : Colors.transparent,
```

## Target

Keep `Material` + `InkWell` so `onSecondaryTapDown` / `showMenu` stay. Disable ink:

```dart
child: InkWell(
  onTap: onTap,
  splashFactory: NoSplash.splashFactory,
  overlayColor: const WidgetStatePropertyAll(Color(0x00000000)),
  hoverColor: const Color(0x00000000),
  highlightColor: const Color(0x00000000),
  splashColor: const Color(0x00000000),
  onSecondaryTapDown: (details) { /* unchanged showMenu */ },
  child: AnimatedContainer(
    duration: MutandeMotion.of(context, MutandeMotion.hover),
    curve: Curves.easeOutCubic,
    …
```

If plan 003 already set `duration: MutandeMotion.of(...)`, keep that — do not revert to a raw 140ms.

Do **not** add `Transform.scale(0.97)` on list rows (high-frequency list navigation must not scale).

## Repo conventions to follow

- Selected fill 140ms `easeOutCubic` matches people-row (`person_identity_row.dart:161-163`) — keep that language.
- Chrome tabs already avoid ink (`home_chrome_strip.dart` `GestureDetector`).
- `NoSplash.splashFactory` is Flutter material; no new package.

## Steps

1. In `_ThreadRow.build` (`app/lib/screens/threads_screen.dart`), on the existing `InkWell`, set `splashFactory: NoSplash.splashFactory`, `splashColor`, `highlightColor`, `hoverColor` to transparent, and `overlayColor: const WidgetStatePropertyAll(Color(0x00000000))`.
2. Leave `onTap`, `onSecondaryTapDown`, padding, selected `AnimatedContainer` color, and row children unchanged.
3. If 003 has not run, still add `MutandeMotion.of(context, MutandeMotion.hover)` (or `MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 140)`).

## Boundaries

- Do NOT change compose `InkWell`, collab cards, Settings tiles, or people-row splash.
- Do NOT wrap the row in `GestureDetector` if that drops secondary-click menus.
- Do NOT add row scale press feedback.
- Do NOT restyle unread dots or host marks.

## Verification

- **Mechanical**: `cd app && dart analyze lib/screens/threads_screen.dart && flutter test test/widget_test.dart`
- **Feel check**: click several Threads rows quickly. No circular ripple, no grey hover wash. Selected row still fills `stone100`. Right-click still opens Mute / Close / Delete. Reduce motion: fill snaps (if 003 applied).
- **Done when**: thread rows produce no Material ink; context menu still works; selected fill remains.
