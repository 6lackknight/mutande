# Brand assets

Single edit surface for mutande product marks. Change masters here, then regenerate every consumer copy.

```bash
# from repo root
./scripts/sync-brand-assets.sh
```

## Sources

| File | Role |
|------|------|
| `sources/ai-mark.png` | Primary **`@i`** seal (white on solid black). 1024² preferred. Feeds AppIcon, web seal, apple-touch. |
| `sources/ai-glyph.png` | Black **`@i`** on transparent. Favicon, Mac/Windows tray, in-app / web BrandMark. |
| `sources/ai-glyph-white.png` | White **`@i`** on transparent. Dark surfaces. |
| `sources/ai-tray.png` | Plated tray glyph (kept; not currently synced — tray uses `ai-glyph`). |
| `sources/mt-ligature.png` | Legacy **MT** ligature — optional secondary mark only. |

Do **not** treat repo-root `new-logo.png` as live until it is intentionally copied into `sources/`.

Host icons (Cursor / Claude / ChatGPT) live under `app/assets/hosts/` and are out of this kit.

## Naming note

Public / Stitch URLs still use historical names:

| Master | Web | Flutter |
|--------|-----|---------|
| `ai-mark.png` | `brand/mt-mark.png` (this is **`@i`**, not MT letters), `brand/icon-192.png`, `brand/apple-touch-icon.png` | `app_icon.png` → macOS AppIcon |
| `ai-glyph.png` | `brand/tray-icon.png`, `brand/favicon-32.png`, `favicon-96x96.png`, `favicon.ico` | `tray_icon.png` |
| `ai-glyph-white.png` | `brand/ai-glyph-white.png` | — |
| `mt-ligature.png` | `brand/mt-ligature.png` | `mt_mark_white_on_black.png` |

Prod reference URLs: `https://mutande.online/brand/…`

## Size map (derived)

| Output | Size |
|--------|------|
| `app/assets/app_icon.png` | 1024² |
| `web/public/brand/mt-mark.png` | 512² |
| `web/public/brand/icon-192.png` | 192² |
| `web/public/brand/apple-touch-icon.png` | 180² |
| `web/public/brand/favicon-32.png` | 32² |
| `web/public/favicon-96x96.png` | 96² |
| tray copies | 44² |
| `web/public/brand/ai-glyph-white.png` | 512² |
| ligature copies | 512² (pass-through) |
| `video/public/brand/mt-mark.png` | 512² |
| `video/public/brand/mt-ligature.png` | 512² |

Landing-intro video/poster under `web/public/brand/` are **not** synced here — use `scripts/upload-brand-r2.sh` for CDN upload of those media files.

## Mark rules

- Primary brand mark is **`@i`** (Address Intelligence). Seal / AppIcon stay white on solid black. Tray + favicon use the transparent glyph.
- Wordmark is always lowercase **`mutande`** (never typed next to the logo when the mark already shows `@i`).
- Keep the MT ligature available where a wordmark/ligature still fits.
