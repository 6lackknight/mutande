# mutande explainer (Manim)

~60s **1080×1080** film: **problem-first** like the landing hero (unreachable silos → paste buffer → handles → thread → team fan-out). Sibling to the silent Remotion loop in [`../video/`](../video/) — does **not** replace `npm run ship`.

## Setup

```bash
cd video-manim
python3.12 -m venv .venv   # 3.10+; Manim needs working pyobjc on macOS
source .venv/bin/activate
pip install 'manim>=0.18.0'
```

Requires FFmpeg (Manim dependency).

## Render

```bash
# Storyboard / beat list (quick)
manim -ql explainer.py MutandeStoryboard

# Full film — preview
manim -ql explainer.py MutandeExplainer

# Master
manim -qh explainer.py MutandeExplainer
```

Output under `media/videos/explainer/`.

## Docs embed (v1 target)

After a master render, copy a web-friendly encode into `web/public/brand/` (gitignored binaries) or R2 `brand/`, then embed on docs — suggested home: [`web/content/index.mdx`](../web/content/index.mdx) or [`web/content/concepts.mdx`](../web/content/concepts.mdx):

```mdx
<video
  playsInline
  muted
  controls
  preload="metadata"
  poster="/brand/org-explainer-poster.webp"
  className="w-full max-w-xl rounded-lg border border-stone-200"
>
  <source src="https://downloads.mutande.online/brand/org-explainer.webm" type="video/webm" />
  <source src="https://downloads.mutande.online/brand/org-explainer.mp4" type="video/mp4" />
</video>
```

Landing hero continues to use `landing-intro.*` from Remotion.

## Source layout

| File | Role |
|------|------|
| `script.py` | Beat times + Set A captions |
| `theme.py` | Stone/bronze palette |
| `ui_inset.py` | Simplified thread UI + seal glyph |
| `explainer.py` | `MutandeExplainer` scene |
| `captions.py` / `layout.py` / `motion.py` | Caption band, stage offset, easing |
| `problem_visuals.py` | Host silos, paste path, fan-out |

Timing and copy changes should start in `script.py`.
