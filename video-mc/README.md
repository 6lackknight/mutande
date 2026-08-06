# mutande landing intro (Motion Canvas)

Diagram-first alternative to the Remotion project in `../video/`.

Same story: **Address Intelligence** — identity → compose → explainer → agents → mutande → recipients → brand.

## Spec

- **1080×1080** · **60fps** · ~28s · muted · silent loop
- Stone / bronze palette (no purple AI gradients)
- Beams use `easeOutCubic` draw + traveling pulses

Remotion remains the primary ship path for host-window UI fidelity. Use this when iterating the routing graph / typography beats.

## Commands

```bash
npm i
npm start          # Motion Canvas editor (Chrome recommended)
npm run lint       # tsc
```

Render MP4 from the editor: **Video Settings → Render** (FFmpeg exporter is enabled via `@motion-canvas/ffmpeg`).

Output lands under `output/` by default. Copy into `../web/public/brand/` if you want to A/B against the Remotion asset.

## Layout

| Path | Role |
|------|------|
| `src/scenes/landingIntro.tsx` | Full beat scene |
| `src/theme.ts` | Shared palette |
| `src/project.meta` | 1080² @ 60fps + FFmpeg exporter |
| `../video/` | Remotion (primary) |
