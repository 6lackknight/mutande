# Brand assets

Single edit surface for mutande product marks. Change masters here, then regenerate every consumer copy.

```bash
# from repo root
./scripts/sync-brand-assets.sh
```

## Sources

| File | Role |
|------|------|
| `sources/ai-mark.png` | Primary **`@i`** seal (white on solid black). 1024² preferred. Feeds AppIcon, web seal, favicons. |
| `sources/ai-tray.png` | Menu-bar / in-app tray glyph (`@i` plate). Prefer high-res; sync downsizes to 44². |
| `sources/mt-ligature.png` | Legacy **MT** ligature — optional secondary mark only. |

Do **not** treat repo-root `new-logo.png` as live until it is intentionally copied into `sources/`.

Host icons (Cursor / Claude / ChatGPT) live under `app/assets/hosts/` and are out of this kit.

## Naming note

Public / Stitch URLs still use historical names:

| Master | Web (`web/public/brand/`) | Flutter (`app/assets/`) |
|--------|---------------------------|-------------------------|
| `ai-mark.png` | `mt-mark.png` (this is **`@i`**, not MT letters), `favicon-32.png`, `icon-192.png`, `apple-touch-icon.png` | `app_icon.png` → macOS AppIcon |
| `ai-tray.png` | `tray-icon.png` | `tray_icon.png` |
| `mt-ligature.png` | `mt-ligature.png` | `mt_mark_white_on_black.png` |

Prod reference URLs: `https://mutande.online/brand/…`

## Size map (derived)

| Output | Size |
|--------|------|
| `app/assets/app_icon.png` | 1024² |
| `web/public/brand/mt-mark.png` | 512² |
| `web/public/brand/icon-192.png` | 192² |
| `web/public/brand/apple-touch-icon.png` | 180² |
| `web/public/brand/favicon-32.png` | 32² |
| tray copies | 44² |
| ligature copies | 512² (pass-through) |
| `video/public/brand/mt-mark.png` | 512² |
| `video/public/brand/mt-ligature.png` | 512² |

Landing-intro video/poster under `web/public/brand/` are **not** synced here — use `scripts/upload-brand-r2.sh` for CDN upload of those media files.

## Mark rules

- Primary brand mark is **`@i`** (Address Intelligence), white on solid black for tray/seal/video.
- Wordmark is always lowercase **`mutande`** (never typed next to the logo when the mark already shows `@i`).
- Keep the MT ligature available where a wordmark/ligature still fits.
