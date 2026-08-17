# Desktop updates — v1 stub

## Status

**Mac:** DMG release script exists (`scripts/release-macos-dmg.sh`). Developer ID
signing + notarization via `mutande-notary` keychain profile. Sparkle
auto-updates remain deferred (PRD story 37).

**Windows:** Unsigned alpha zip via GitHub Actions
(`.github/workflows/release-windows.yml`). See `scripts/release-windows.md`.
SmartScreen warnings are expected; Authenticode deferred.

## Full desktop cut (preferred)

```bash
# Mac DMGs → R2, Windows Actions → R2, Vercel version + redeploy:
./scripts/release-desktop.sh
```

## Release (notarized DMG only)

```bash
# One-time (Apple ID + app-specific password from appleid.apple.com):
xcrun notarytool store-credentials "mutande-notary" \
  --apple-id "you@example.com" \
  --team-id "Q22P2YXR6M" \
  --password "<app-specific-password>"

# Both native arches (default) — Apple Silicon + Intel DMGs:
./scripts/release-macos-dmg.sh

# One arch only:
ARCH=arm64 ./scripts/release-macos-dmg.sh
ARCH=intel ./scripts/release-macos-dmg.sh

# Skip notary / keep version:
SKIP_NOTARIZE=1 SKIP_BUMP=1 ARCH=arm64 ./scripts/release-macos-dmg.sh

# Version controls:
#   BUMP=patch|minor|major|build   (default: patch — also always +1 build)
#   SKIP_BUMP=1                    keep app/pubspec.yaml as-is
```

Each release rewrites `app/pubspec.yaml`, `core/Cargo.toml`, and the default
`MAC_DMG_VERSION` in `web/src/lib/downloads.ts`.

Outputs (rolling alpha, no version archives):
- `mutande-alpha-arm64.dmg` — Apple Silicon (also copied to `mutande-alpha.dmg`)
- `mutande-alpha-intel.dmg` — Intel

Upload to R2 (not git, not Vercel):

```bash
./scripts/upload-downloads-r2.sh
# or: SRC_DIR=dist/macos ./scripts/upload-downloads-r2.sh
```

Objects land at the root of the public `mutande-releases` bucket (e.g.
`mutande-alpha.dmg`). Custom domain: `https://downloads.mutande.online`.
Set Vercel `NEXT_PUBLIC_DOWNLOADS_BASE` to that origin (no trailing slash).
Keep `web/public/downloads/*` gitignored for local smoke only. Hub `R2_*`
keys must allow write to `mutande-releases` (blobs-only tokens get AccessDenied).

Landing intro video/poster share the same bucket under `brand/`:

```bash
./scripts/upload-brand-r2.sh
# or after a Remotion cut: cd video && npm run ship
```

→ `https://downloads.mutande.online/brand/landing-intro.mp4` (also `.webm` + poster).
Web defaults to that CDN; set `NEXT_PUBLIC_BRAND_ASSETS_LOCAL=1` for offline `/brand/*`.

## Release (Windows unsigned installer)

```text
GitHub → Actions → "Release Windows alpha" → Run workflow
→ build job: Inno Setup mutande-alpha-windows-setup.exe (+ zip fallback)
→ publish-r2 job runs scripts/upload-downloads-r2.sh (same bucket as Mac)
→ https://downloads.mutande.online/mutande-alpha-windows-setup.exe
→ set NEXT_PUBLIC_WIN_ZIP_PUBLISHED=1 on Vercel if needed
```

Requires repo secrets `R2_ACCOUNT_ID`, `R2_DOWNLOADS_ACCESS_KEY_ID`,
`R2_DOWNLOADS_SECRET_ACCESS_KEY` (releases bucket — not hub blobs keys).
See `scripts/release-windows.md`.

Installer packs Flutter `Release/` + `mutande-core.exe` sidecar into
`%LOCALAPPDATA%\Programs\mutande` (per-user). No Authenticode / no MSIX.

## Intended path (Sparkle)

1. Sign and notarize `mutande.app` (Developer ID) — script above.
2. Embed [Sparkle](https://sparkle-project.org/) in the Flutter macOS Runner
   (native Swift/`AppDelegate` or a thin plugin).
3. Host an `appcast.xml` (GitHub Releases or CDN) with EdDSA signatures.
4. Menu: **Check for Updates…** on the tray / Session tab.

## Until Sparkle

- Ship fixes by redistributing a new `.dmg`.
- Release builds do **not** auto-gate on launch (2.0.7+). Opt-in only:
  `FORCE_UPDATE_GATE=1` or debug `PREVIEW_UPDATE_GATE=1`. Sparkle / Settings
  “Check for updates” will replace the startup poll.
- `mutande-core` is bundled as a sidecar in `Contents/Resources/mutande-core`
  (see `app/macos/Runner/Scripts/bundle_mutande_core.sh`); bump both app and
  core together.
- Version: `app/pubspec.yaml` (`version:`) and `core/Cargo.toml`.
