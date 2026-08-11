# Penpot — mutande Mac UI

Design surface for the Flutter companion **without** running the full app. Source of truth for layout explorations; Flutter (`app/lib/theme/mutande_macos_theme.dart`) remains the shipped implementation.

## Start

1. Open [design.penpot.app](https://design.penpot.app) (SaaS). Keep **MCP Server → Connect** on the open file when iterating with Cursor.
2. Tokens: `tokens/mutande.tokens.json` (ink = interactive chrome; amber = pending / Needs you only).
3. Board size: **1280×720**.

## Boards

| Board | Job |
|-------|-----|
| Threads — mail split | Mail split; Compose (ink) + flex Search; Needs you |
| Network — Me | **Calm concentric** — you + agents on one orbit |
| Network — concentric · Org | Handles on ring; selected peer’s agents on local orbit |
| Network — concentric · External | Zoomed out — **orgs** on outer ring (not handles) |
| Network — inspector states | Self / peer fresh / peer stale / external panels |
| Agents — graph / list | Legacy — archive |
| Contacts | Handle · `@all@org` · teammates · external |
| Settings — hosts / trust | Hosts \| Trust segments |

**Zoom priority:** External → org avatar + name. Org → handles. Me → your agents.

**Network visual:** **concentric calm** (path spokes, soft glow on selection only). Force-scatter retired.

**Peer visibility (mock):** full peer agent expansion assumes hub peer-visibility API later.

## Rules (from `.impeccable.md`)

- Ink for interactive chrome / selection; amber only for pending / Needs you.
- Emerald = ready / linked / open / soft selection glow.
- Mail, not forum: no chat bubbles.
- Prefer sparse orbits over force-layout density.

## Flutter handoff

1. Reference PNGs in `exports/` (also copied under `/screenshots/`).
2. Network Me = concentric orbit in `app/lib/screens/agents_screen.dart`.
3. Implement against `MutandeColors`; sync tokens if hex changes.
4. Soft selection glow on Me; External zoom shows **orgs**, not handles.
