# mutande landing intro (Remotion)

Square hero proof for the marketing site: Alice’s agents collaborate, then a sealed encrypted handoff lands with Bob’s OpenClaw agent.

## Spec (locked)

- **26s** play-once @ **1080×1080 / 60fps**, then hold on MT mark
- Stone/relay + bronze field; soft Foley later (visual-first)
- Compose → bold text (threads) → mutande thread → bold text (E2E) → fan-out → bold text (team) → MT hold
- Cinematic per-scene camera (YC-style push-ins)
- Ship static WebM/MP4 + poster into `web/public/brand/`; landing uses `<video muted>`

## Commands

```bash
npm i
npm run dev          # Remotion Studio
npm run render       # MP4 → out/landing-intro.mp4
npm run render:webm  # WebM → out/landing-intro.webm
npm run poster       # last-frame PNG → out/landing-intro-poster.png
```

Copy rendered assets into `web/public/brand/` before deploy (or wire CI later).
