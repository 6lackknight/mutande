# mutande landing intro (Remotion)

Primary ship path for the marketing hero: **Address Intelligence** (hosts + thread UI + sealed fan-out).

Motion Canvas alternative lives in [`../video-mc/`](../video-mc/) — better for diagram/beam iteration; Remotion stays the host-window UI path.

## Spec

- **~28s** @ **1080×1080 / 60fps** in Remotion; ship **30fps silent** web encodes
- Stone/relay + bronze; identity → compose → explainer → collab → handoff/beams → brand
- Ship **MP4 (H.264 Main, no audio, faststart)** + **WebM (VP9)** + poster into `web/public/brand/`

## Commands

```bash
npm i
npm run dev       # Remotion Studio
npm run render    # master MP4 → out/landing-intro.mp4
npm run optimize  # silent 30fps MP4 + WebM → ../web/public/brand/
npm run poster    # brand-frame PNG → out/landing-intro-poster.png
npm run ship      # render + optimize + poster into web/public/brand/
```

Landing `<video>` prefers WebM, falls back to MP4 (Safari).
