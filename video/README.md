# mutande landing intro (Remotion)

Primary ship path for the marketing hero: **Address Intelligence** (hosts + thread UI + sealed fan-out).

Motion Canvas alternative lives in [`../video-mc/`](../video-mc/) — better for diagram/beam iteration; Remotion stays the host-window UI path.

## Spec

- **~28s** @ **1080×1080 / 60fps**, muted loop
- Stone/relay + bronze; identity → compose → explainer → collab → handoff/beams → brand
- Ship MP4 + poster into `web/public/brand/`; landing uses `<video muted>`

## Commands

```bash
npm i
npm run dev          # Remotion Studio
npm run render       # MP4 → out/landing-intro.mp4
npm run render:webm  # WebM → out/landing-intro.webm
npm run poster       # brand-frame PNG → out/landing-intro-poster.png
```

Copy rendered assets into `web/public/brand/` before deploy.
