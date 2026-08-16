# Animation plans

Plans from `improve-animations`. Executors have zero audit context — follow each plan’s Target, Steps, and Boundaries exactly. Do not edit `thinking_orb.dart` motion or the onboarding address rail unless a plan names that file. **013** is stamped **b5369e9**; 001–012 were written at **946c2bc**.

| # | File | Severity | Status | Title |
| --- | --- | --- | --- | --- |
| 008 | [008-mutande-motion-tokens.md](008-mutande-motion-tokens.md) | LOW | done | Add `MutandeMotion` tokens |
| 001 | [001-search-palette-no-animation.md](001-search-palette-no-animation.md) | HIGH | done | Remove search palette open animation |
| 002 | [002-chrome-pills-ease.md](002-chrome-pills-ease.md) | HIGH | done | Ease high-frequency pill/thumb color |
| 003 | [003-gate-disable-animations.md](003-gate-disable-animations.md) | HIGH | done | Gate everyday motion with `disableAnimations` |
| 004 | [004-connect-host-scale.md](004-connect-host-scale.md) | MEDIUM | done | Connect-host scale 0.95; delete dead check wait |
| 005 | [005-threads-list-kill-ink.md](005-threads-list-kill-ink.md) | MEDIUM | done | Kill Material ink on Threads list |
| 006 | [006-network-graph-enter.md](006-network-graph-enter.md) | MEDIUM | done | Cap Network graph enter; quiet hover |
| 007 | [007-mail-accordion.md](007-mail-accordion.md) | MEDIUM | done | Mail accordion: no layout animation |
| 009 | [009-splash-fade-out.md](009-splash-fade-out.md) | LOW | done | Splash 200ms opacity fade out |
| 010 | [010-inspector-slide-from-right.md](010-inspector-slide-from-right.md) | MEDIUM | done | Inspector slides from the right |
| 011 | [011-skeleton-content-crossfade.md](011-skeleton-content-crossfade.md) | LOW | done | Skeleton → content 200ms opacity crossfade |
| 012 | [012-composer-search-focus-ring.md](012-composer-search-focus-ring.md) | LOW | done | Match composer and search focus rings |
| 013 | [013-create-collab-sheet-from-button.md](013-create-collab-sheet-from-button.md) | MEDIUM | TODO | Create-collab sheet from Create control |

## Recommended execution order

1. **008** tokens first. Later plans call `MutandeMotion.ease` / `easeOut` / `easeDrawer` / `hover` / `press` / `ui` / `of`. If 008 is missing, each plan inlines the same Cubics and Durations.
2. **001** search open (independent).
3. **002** then **003** (002 gates pills/thumbs; 003 gates remaining everyday sites). Do not re-edit 002’s containers in 003.
4. **005** after **003** (`_ThreadRow` duration + ink in the same widget).
5. **012** after **002** (search field is not `_ScopeChip`; composer is separate). Safe in parallel with 005.
6. **004**, **006**, **007**, **009**, **010**, **011** — independent of each other. Can run in parallel after 008.

7. **013** after **008** (needs `MutandeMotion.ui` / `easeOut`). Independent of 001–012. Do not collide with in-flight inner stagger in `create_collab_sheet.dart` — 013 edits `showCreateCollabSheet` only in that file.

Suggested serial path: **008 → 001 → 002 → 003 → 005 → 012 → 004 → 006 → 007 → 009 → 010 → 011 → 013**.

## Dependencies

```
008 ─┬─ 002 ─ 003 ─ 005
     ├─ 012 (after 002 so search chips vs field stay distinct)
     ├─ 001
     ├─ 004
     ├─ 006
     ├─ 007
     ├─ 009
     ├─ 010
     ├─ 011
     └─ 013 (showCreateCollabSheet route only; leave MutandeStagger* alone)
```

- **002 ∩ 003:** `_ScopePill`, `_HeaderThumb`, `_SegmentPill`, `_ScopeChip` belong to 002 only.
- **003 ∩ 005:** `_ThreadRow` — 003 sets duration gate; 005 only removes ink.
- **001 ∩ 012:** 001 is `showSearchDialog` transition; 012 is `_DialogSearchField` border.
- **007 ∩ 012:** same file `thread_relay_reading.dart` — 007 is `_RailItem` `AnimatedSize`; 012 is `_CapsuleComposer`. Do not collide.
- **013 ∩ in-flight stagger:** same file `create_collab_sheet.dart` — 013 is `showCreateCollabSheet` presentation only. Do not edit `CreateCollabSheet` body / `MutandeStagger*`.

## Shared values (from AUDIT.md)

Do not approximate:

| Token | Flutter |
| --- | --- |
| CSS `ease` | `Cubic(0.25, 0.1, 0.25, 1.0)` |
| `--ease-out` `cubic-bezier(0.23, 1, 0.32, 1)` | `Cubic(0.23, 1.0, 0.32, 1.0)` |
| `--ease-in-out` `cubic-bezier(0.77, 0, 0.175, 1)` | `Cubic(0.77, 0.0, 0.175, 1.0)` |
| `--ease-drawer` `cubic-bezier(0.32, 0.72, 0, 1)` | `Cubic(0.32, 0.72, 0.0, 1.0)` |
| Hover / color | 140ms (`hover`) |
| Press | 160ms, scale 0.97 |
| UI / fade / drawer enter | 200ms |
| Reduced motion | `MediaQuery.disableAnimationsOf` → `Duration.zero` on movement; keep color/opacity snaps |

## Out of scope (do not “also fix”)

- `thinking_orb.dart` working orb
- `morphing_orb_button.dart` CTA↔orb morph
- `person_identity_row.dart` 140ms hover (by design; 008 does not migrate it)
- Onboarding address rail / heading stagger
- MacosSheet bounce globally / Settings `showMacosSheet` (not selected — **013** replaces the create-collab **route** only)
- Peer popover origin (not selected)
- Threads · Collab · Network tab **body** crossfades (high frequency — no animation)
