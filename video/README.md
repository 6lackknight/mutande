# mutande landing intro (Remotion)

Primary ship path for the marketing hero: **Address Intelligence** (hosts + thread UI + sealed fan-out).

Motion Canvas alternative lives in [`../video-mc/`](../video-mc/) — better for diagram/beam iteration; Remotion stays the host-window UI path.

## Spec

- **~28s** @ **1080×1080 / 60fps** in Remotion; ship **30fps silent** web encodes
- Stone/relay + bronze; identity → compose → explainer → collab → handoff/beams → brand
- Ship **MP4 (H.264 Main, no audio, faststart)** + **WebM (VP9)** + poster into `web/public/brand/`, then upload to R2 (`downloads.mutande.online/brand/…`)

## Commands

```bash
npm i
npm run dev       # Remotion Studio
npm run render    # master MP4 → out/landing-intro.mp4
npm run optimize  # silent 30fps MP4 + WebM → ../web/public/brand/
npm run poster    # brand-frame PNG → out/landing-intro-poster.png
npm run upload:r2 # push landing-intro.* to mutande-releases/brand/
npm run ship      # render + optimize + poster + R2 upload
```

Landing `<video>` loads from the downloads CDN (WebM first, MP4 for Safari). Local `/brand/…` still works with `NEXT_PUBLIC_BRAND_ASSETS_LOCAL=1`.
